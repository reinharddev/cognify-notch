import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import SwiftUI

/// Equalizer yang mengikuti suara asli: suara yang keluar dari Mac disadap lewat Core Audio tap
/// (macOS 14.2+), dipecah dengan FFT menjadi 4 pita nada (bass → treble), dan tinggi tiap batang
/// = kerasnya pita itu. Hanya 4 angka yang keluar dari sini; suara tidak disimpan atau dikirim.
///
/// macOS meminta izin "audio dari app lain" saat pertama berjalan. Ditolak / macOS lebih lama →
/// `bands` tetap nil dan Equalizer memakai animasi biasa.
@MainActor
final class Spectrum: ObservableObject {
    /// 0…1 per pita: 40–250 Hz, 250–1000 Hz, 1–4 kHz, 4–12 kHz.
    @Published private(set) var bands: [Float]?

    private var engine: AnyObject?
    private var wanted = false

    /// Jalan hanya saat musik diputar dan fitur dinyalakan.
    func setActive(_ active: Bool) {
        guard active != wanted else { return }
        wanted = active
        if active {
            if #available(macOS 14.2, *) {
                let tap = TapEngine { [weak self] values in
                    Task { @MainActor in
                        guard let self, self.wanted else { return }
                        self.bands = values
                    }
                }
                if tap.start() { engine = tap } else { bands = nil }
            }
        } else {
            if #available(macOS 14.2, *) { (engine as? TapEngine)?.stop() }
            engine = nil
            bands = nil
        }
    }
}

@available(macOS 14.2, *)
private final class TapEngine {
    private let onBands: ([Float]) -> Void
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "cognify.spectrum")

    // FFT
    private static let size = 2048
    private let fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(TapEngine.size))), radix: .radix2, ofType: DSPSplitComplex.self)!
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: TapEngine.size, isHalfWindow: false)
    private var ring = [Float](repeating: 0, count: TapEngine.size)
    private var filled = 0
    private var sampleRate: Float = 48_000
    private var smoothed: [Float] = [0, 0, 0, 0]
    private var peak: [Float] = [0.02, 0.02, 0.02, 0.02]
    private var lastEmit = Date.distantPast
    private static let edges: [Float] = [40, 250, 1000, 4000, 12_000]

    init(onBands: @escaping ([Float]) -> Void) {
        self.onBands = onBands
    }

    func start() -> Bool {
        // Semua suara sistem (tidak dibisukan, tidak terlihat sebagai perangkat).
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != kAudioObjectUnknown,
              let outputUID = Self.defaultOutputUID() else {
            stop()
            return false
        }
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Cognify Equalizer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregateID) == noErr else {
            stop()
            return false
        }
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr, format.mSampleRate > 0 {
            sampleRate = Float(format.mSampleRate)
        }
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.consume(input)
        }
        guard status == noErr, AudioDeviceStart(aggregateID, procID) == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private static func defaultOutputUID() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    /// Dipanggil Core Audio (thread audio): kumpulkan sampel mono, hitung pita ±30×/detik.
    private func consume(_ list: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, let data = first.mData else { return }
        let channels = Int(max(1, first.mNumberChannels))
        let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
        let samples = data.assumingMemoryBound(to: Float.self)
        for i in 0..<count {
            ring[filled % Self.size] = samples[i * channels] // kanal kiri cukup untuk bentuk batang
            filled += 1
        }
        guard filled >= Self.size, Date().timeIntervalSince(lastEmit) >= 1.0 / 30 else { return }
        lastEmit = Date()
        onBands(analyze())
    }

    private func analyze() -> [Float] {
        let start = filled % Self.size
        let ordered = Array(ring[start...] + ring[..<start])
        let windowed = vDSP.multiply(ordered, window)
        let half = Self.size / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: im.baseAddress!)
                windowed.withUnsafeBufferPointer { w in
                    w.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half)) }
                }
                fft.forward(input: split, output: &split)
                vDSP.absolute(split, result: &magnitudes)
            }
        }
        let binHz = sampleRate / Float(Self.size)
        var values: [Float] = []
        for band in 0..<4 {
            let lo = max(1, Int(Self.edges[band] / binHz)), hi = min(half - 1, Int(Self.edges[band + 1] / binHz))
            let energy = hi > lo ? vDSP.mean(magnitudes[lo...hi]) : 0
            // Penguatan otomatis per pita: puncak turun pelan, jadi lagu pelan pun tetap terlihat.
            peak[band] = max(energy, peak[band] * 0.995, 0.02)
            let level = min(1, energy / peak[band])
            // Naik cepat, turun pelan (seperti meter audio).
            smoothed[band] = level > smoothed[band] ? level * 0.7 + smoothed[band] * 0.3 : smoothed[band] * 0.82 + level * 0.18
            values.append(smoothed[band])
        }
        return values
    }
}
