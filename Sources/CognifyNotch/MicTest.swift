import AVFoundation
import SwiftUI

/// Tes mikrofon di halaman "Camera & Mic". Mikrofon hanya menyala setelah tombol ditekan dan mati saat halaman
/// ditinggalkan. Rekaman 5 detik ditulis ke berkas sementara, dibaca ke memori, lalu berkasnya langsung dihapus:
/// tidak ada yang disimpan atau dikirim.
@MainActor
final class MicTest: NSObject, ObservableObject {
    enum State { case idle, testing, recording, playing, played, denied, unavailable }

    static let length: TimeInterval = 5

    @Published private(set) var state: State = .idle
    @Published private(set) var devices: [CameraInputChoice] = []
    @Published private(set) var selectedID: String? = UserDefaults.standard.string(forKey: "mic.input.id")
    /// 0…1 dari desibel rata-rata.
    @Published private(set) var level: Double = 0
    /// Terdengar cukup jelas dalam 1,5 detik terakhir.
    @Published private(set) var loudEnough = false
    @Published private(set) var elapsed: TimeInterval = 0

    private var session: AVCaptureSession?
    /// Baru tiap sesi: output lama dilepas di antrean belakang, jadi tidak boleh dipakai ulang.
    private var output = AVCaptureAudioFileOutput()
    private let queue = DispatchQueue(label: "cognify.mic")
    private var timer: Timer?
    private var player: AVAudioPlayer?
    private var started = Date()
    private var lastLoud = Date.distantPast

    private func discover() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = [.builtInMicrophone, .externalUnknown]
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .audio, position: .unspecified).devices
        devices = found.map { CameraInputChoice(id: $0.uniqueID, name: $0.localizedName) }
        if !devices.contains(where: { $0.id == selectedID }) { selectedID = AVCaptureDevice.default(for: .audio)?.uniqueID ?? devices.first?.id }
        return found
    }

    func refreshDevices() { _ = discover() }

    func selectDevice(_ id: String) {
        selectedID = id
        UserDefaults.standard.set(id, forKey: "mic.input.id")
        if state == .testing { stop(); begin(record: false) } else { stop() }
    }

    func begin(record: Bool) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: run(record: record)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                Task { @MainActor in if ok { self.run(record: record) } else { self.state = .denied } }
            }
        default: state = .denied
        }
    }

    private func run(record: Bool) {
        stop()
        guard let device = discover().first(where: { $0.uniqueID == selectedID }),
              let input = try? AVCaptureDeviceInput(device: device) else { state = .unavailable; return }
        let session = AVCaptureSession()
        guard session.canAddInput(input) else { state = .unavailable; return }
        session.addInput(input)
        output = AVCaptureAudioFileOutput()
        guard session.canAddOutput(output) else { state = .unavailable; return }
        session.addOutput(output)
        self.session = session
        state = record ? .recording : .testing
        started = Date()
        let box = UncheckedBox(session)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cognify-mic-\(UUID().uuidString).m4a")
        let outputBox = UncheckedBox(output)
        queue.async { [weak self] in
            box.value.startRunning()
            if record, let self { outputBox.value.startRecording(to: url, outputFileType: .m4a, recordingDelegate: self) }
        }
        tick(every: 0.05)
    }

    private func tick(every interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    private func update() {
        switch state {
        case .testing, .recording:
            let db = output.connection(with: .audio)?.audioChannels.first?.averagePowerLevel ?? -160
            level = max(0, min(1, (Double(db) + 50) / 50))
            if level > 0.35 { lastLoud = Date() }
            loudEnough = Date().timeIntervalSince(lastLoud) < 1.5
            if state == .recording {
                elapsed = Date().timeIntervalSince(started)
                if elapsed >= Self.length, output.isRecording { output.stopRecording() }
            }
        case .playing:
            elapsed = player?.currentTime ?? 0
            if player?.isPlaying != true { timer?.invalidate(); state = .played; level = 0 }
        default: break
        }
    }

    func playAgain() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
        state = .playing
        tick(every: 0.1)
    }

    private func stopCapture() {
        timer?.invalidate()
        timer = nil
        level = 0
        elapsed = 0
        if let session {
            let box = UncheckedBox(session), outputBox = UncheckedBox(output)
            queue.async {
                if outputBox.value.isRecording { outputBox.value.stopRecording() }
                box.value.stopRunning()
                box.value.removeOutput(outputBox.value)
            }
        }
        session = nil
    }

    /// Matikan mikrofon dan buang rekaman.
    func stop() {
        stopCapture()
        player?.stop()
        player = nil
        if state != .denied { state = .idle }
    }

    fileprivate func finished(_ data: Data?, from id: ObjectIdentifier) {
        // Halaman sudah ditinggalkan atau tes sudah diulang: rekaman dibuang.
        guard state == .recording, id == ObjectIdentifier(output) else { return }
        stopCapture()
        guard let data, let player = try? AVAudioPlayer(data: data) else { state = .unavailable; return }
        self.player = player
        playAgain()
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
}

extension MicTest: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        let data = try? Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        let id = ObjectIdentifier(output)
        Task { @MainActor in self.finished(data, from: id) }
    }
}

/// Kartu mikrofon: pilihan input, batang level, keterangan, lalu tombol.
struct MicCard: View {
    @ObservedObject var mic: MicTest
    private static let bars = 24

    private var clock: (TimeInterval) -> String { { String(format: "00:%02d", Int($0.rounded())) } }

    private var message: (text: String, tint: Color?) {
        switch mic.state {
        case .idle: return ("Press Test mic, then speak.", nil)
        case .testing: return mic.loudEnough ? ("Your voice is coming through clearly.", .green) : ("Too quiet. Move closer to the mic.", .orange)
        case .recording: return ("Recording \(clock(mic.elapsed)) of \(clock(MicTest.length)).", .red)
        case .playing: return ("Playing \(clock(mic.elapsed)) of \(clock(MicTest.length)). Not saved.", nil)
        case .played: return ("Done. The recording is not saved.", nil)
        case .denied: return ("Microphone access is off for Cognify Notch.", .orange)
        case .unavailable: return ("No microphone available.", .orange)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if !mic.devices.isEmpty {
                NotchDropdown("Microphone", selection: Binding(get: { mic.selectedID ?? "" }, set: { mic.selectDevice($0) }),
                              options: mic.devices.map { DropdownOption($0.id, $0.name) })
                    .labelsHidden()
            }
            HStack(spacing: 3) {
                ForEach(0..<Self.bars, id: \.self) { i in
                    Capsule().fill(Double(i) < mic.level * Double(Self.bars) ? (i < 14 ? Color.green : .orange) : Theme.track)
                }
            }
            .frame(height: 24)
            .accessibilityElement()
            .accessibilityLabel("Microphone level")
            .accessibilityValue("\(Int(mic.level * 100)) percent")
            HStack(spacing: 5) {
                if let tint = message.tint { Circle().fill(tint).frame(width: 6, height: 6) }
                Text(message.text).font(.system(size: 11)).foregroundStyle(message.tint ?? Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                switch mic.state {
                case .denied:
                    Button("Open System Settings") { mic.openPrivacySettings() }.buttonStyle(PillButtonStyle(prominent: true))
                case .testing, .recording:
                    Button { mic.stop() } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(PillButtonStyle(prominent: true))
                    Button("Record 5 sec") { mic.begin(record: true) }.buttonStyle(PillButtonStyle(prominent: false)).disabled(mic.state == .recording)
                case .playing, .played:
                    Button("Play again") { mic.playAgain() }.buttonStyle(PillButtonStyle(prominent: true))
                    Button("Record again") { mic.begin(record: true) }.buttonStyle(PillButtonStyle(prominent: false))
                default:
                    Button { mic.begin(record: false) } label: { Label("Test mic", systemImage: "mic.fill") }.buttonStyle(PillButtonStyle(prominent: true))
                    Button("Record 5 sec") { mic.begin(record: true) }.buttonStyle(PillButtonStyle(prominent: false))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .notchCard(padding: Theme.Space.s)
        .onAppear { mic.refreshDevices() }
        .onDisappear { mic.stop() }
    }
}
