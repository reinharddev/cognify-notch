import AVFoundation
import Speech
import SwiftUI

/// Rekam suara → teks di kolom catatan cepat. Pengenalan ucapan wajib berjalan di Mac ini
/// (`requiresOnDeviceRecognition`): bila bahasa itu belum punya model offline, perekaman ditolak
/// daripada suara dikirim ke server Apple. Suara tidak disimpan.
@MainActor
final class VoiceNote: ObservableObject {
    @Published private(set) var recording = false
    /// 0…1, untuk animasi tombol mikrofon.
    @Published private(set) var level: Float = 0

    /// Teks sementara/akhir (seluruh ucapan sejak mulai merekam).
    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var limit: Task<Void, Never>?
    private static let maxSeconds: UInt64 = 90

    func toggle() {
        if recording { stop() } else { Task { await start() } }
    }

    private func start() async {
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard speech == .authorized else {
            return fail(L("Izinkan Pengenalan Ucapan untuk Cognify Notch di Pengaturan Sistem → Privasi.",
                          "Allow Speech Recognition for Cognify Notch in System Settings → Privacy."))
        }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard mic else {
            return fail(L("Izinkan Mikrofon di Pengaturan Sistem → Privasi.", "Allow Microphone in System Settings → Privacy."))
        }
        let locale = Locale(identifier: Lang.english ? "en-US" : "id-ID")
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            return fail(L("Pengenal suara belum tersedia di Mac ini.", "Speech recognition isn't available on this Mac."))
        }
        guard recognizer.supportsOnDeviceRecognition else {
            return fail(L("Pengenal suara offline Bahasa Indonesia belum terpasang. Nyalakan Dikte di Pengaturan Sistem → Keyboard, lalu coba lagi.",
                          "Offline speech recognition isn't installed. Turn on Dictation in System Settings → Keyboard, then try again."))
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.rms(buffer)
            Task { @MainActor in self?.level = level }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return fail(L("Mikrofon tidak bisa dipakai: \(error.localizedDescription)", "Microphone unavailable: \(error.localizedDescription)"))
        }
        recording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || result?.isFinal == true
            Task { @MainActor in
                guard let self else { return }
                if let text, !text.isEmpty { self.onText?(text) }
                if done { self.finish() }
            }
        }
        limit = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.maxSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    /// Berhenti merekam; teks terakhir masih menyusul lewat `onText`.
    func stop() {
        guard recording else { return }
        limit?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recording = false
        level = 0
    }

    private func finish() {
        stop()
        task = nil
        request = nil
    }

    private func fail(_ message: String) {
        recording = false
        onError?(message)
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return min(1, sqrt(sum / Float(buffer.frameLength)) * 12)
    }
}

/// Tombol mikrofon di catatan cepat: merah dan berdenyut mengikuti suara saat merekam.
struct MicButton: View {
    @ObservedObject var voice: VoiceNote
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: voice.recording ? "stop.fill" : "mic.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 26, height: 22)
                .background(
                    Capsule().fill(voice.recording ? Color.red.opacity(0.85) : Color.white.opacity(0.12))
                        .scaleEffect(voice.recording ? 1 + CGFloat(voice.level) * 0.25 : 1)
                        .animation(.easeOut(duration: 0.1), value: voice.level)
                )
                .foregroundStyle(.white)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(voice.recording ? L("Berhenti merekam", "Stop recording") : L("Rekam suara jadi teks", "Dictate a note"))
    }
}
