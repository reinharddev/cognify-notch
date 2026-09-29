import AppKit
import AVFoundation
import CoreAudio
import EventKit
import SwiftUI

// MARK: - Kalender macOS (EventKit)

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    var end: Date? = nil
    let allDay: Bool
    let calendar: String
    let color: Color
    /// Tautan rapat online (Zoom, Google Meet, Teams, Webex) dari URL, lokasi, atau catatan acara.
    var meeting: URL? = nil

    /// Tombol Gabung tampil dari 10 menit sebelum mulai sampai acara selesai.
    func joinable(at now: Date) -> Bool {
        guard meeting != nil, !allDay else { return false }
        return start.timeIntervalSince(now) <= 10 * 60 && (end ?? start.addingTimeInterval(3600)) > now
    }

    private static let meetingPattern = try! NSRegularExpression(
        pattern: #"https://[^\s<>"']*(zoom\.us/(j|my|w|s)/|meet\.google\.com/[a-z]|teams\.microsoft\.com/l/meetup-join|teams\.live\.com/meet|webex\.com/(meet|join|[a-z0-9.-]+/j\.php))[^\s<>"']*"#,
        options: [.caseInsensitive])

    static func meetingURL(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = meetingPattern.firstMatch(in: text, range: range), let r = Range(match.range, in: text),
               let url = URL(string: String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)>"))) {
                return url
            }
        }
        return nil
    }
}

/// Acara hari ini & besok dari app Kalender (iCloud, Google, dll. yang ditambahkan di Mac).
/// Hanya aktif jika dinyalakan di Pengaturan Cognify; izin Kalender diminta saat itu.
@MainActor
final class CalendarFeed: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var access: Access = .unknown

    private let store = EKEventStore()
    private var enabled = false
    private var observer: NSObjectProtocol?

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        guard value else {
            events = []
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            return
        }
        Task { await requestAndLoad() }
    }

    private func requestAndLoad() async {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { cont in store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) } }
        }
        access = granted ? .granted : .denied
        guard granted, enabled else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
        load()
    }

    func load() {
        guard enabled, access == .granted else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start)!
        let predicate = store.predicateForEvents(withStart: Date().addingTimeInterval(-15 * 60), end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { CalendarEvent(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? L("(Tanpa judul)", "(No title)"),
                                 start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay, calendar: $0.calendar.title,
                                 color: Color(nsColor: $0.calendar.color),
                                 meeting: CalendarEvent.meetingURL(in: [$0.url?.absoluteString, $0.location, $0.notes])) }
    }

    func join(_ event: CalendarEvent) {
        if let url = event.meeting { NSWorkspace.shared.open(url) }
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // Untuk snapshot.
    func preview(_ value: [CalendarEvent]) {
        events = value
        access = .granted
    }
}

// MARK: - Cermin kamera

/// Kamera depan hanya menyala selama tab Cermin terlihat; tidak ada yang direkam atau disimpan.
@MainActor
final class CameraMirror: ObservableObject {
    enum State { case idle, running, denied, unavailable }

    @Published private(set) var state: State = .idle
    let session = AVCaptureSession()
    /// Lapisan pratinjau milik kamera (bukan milik tampilan): terpasang ke sesi sekali saja.
    let preview = AVCaptureVideoPreviewLayer()
    /// Semua perintah ke sesi kamera (atur, mulai, berhenti) lewat satu antrean berurutan.
    /// Mulai & berhenti yang berjalan bersamaan (pindah tab cepat) membuat AVFoundation crash
    /// ("Collection was mutated while being enumerated").
    private let queue = DispatchQueue(label: "cognify.camera")
    private var configured = false
    /// Keinginan terakhir (tab Cermin terlihat atau tidak); antrean menyamakan sesi dengannya.
    private var wanted = false

    func start() {
        wanted = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                Task { @MainActor in ok ? self.run() : (self.state = .denied) }
            }
        default: state = .denied
        }
    }

    private func run() {
        guard wanted else { return } // tab sudah ditinggal sebelum izin dijawab
        if !configured {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                    ?? AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                state = .unavailable
                return
            }
            configured = true
            // Sekali saja, sebelum perintah mulai pertama masuk antrean: input + lapisan pratinjau
            // (yang menambah koneksi ke sesi). Membuat pratinjau saat sesi sedang dinyalakan
            // mengubah daftar koneksi di tengah `startRunning` → crash.
            session.beginConfiguration()
            session.sessionPreset = .medium
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            preview.session = session
            preview.videoGravity = .resizeAspectFill
            if let connection = preview.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true // seperti cermin
            }
        }
        state = .running
        sync()
    }

    func stop() {
        wanted = false
        guard state == .running else { return }
        state = .idle
        sync()
    }

    /// Nyalakan/matikan sesi sesuai `wanted`, satu perintah dalam satu waktu.
    private func sync() {
        let box = UncheckedBox(session)
        let want = wanted
        queue.async {
            let session = box.value
            if want, !session.isRunning {
                session.startRunning()
            } else if !want, session.isRunning {
                session.stopRunning()
            }
        }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }
}

/// Menampilkan lapisan pratinjau milik `CameraMirror`; tidak menyentuh sesi kamera sama sekali.
struct CameraPreview: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        layer.removeFromSuperlayer()
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        layer.frame = nsView.bounds
    }
}

struct MirrorPanel: View {
    @ObservedObject var camera: CameraMirror
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06))
                if camera.state == .running && !snapshot {
                    CameraPreview(layer: camera.preview)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else if camera.state == .denied {
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash.fill").font(.system(size: 20))
                        Text(L("Izin kamera ditolak", "Camera access denied")).font(.system(size: 11.5))
                        Button(L("Buka Pengaturan Sistem", "Open System Settings")) { camera.openPrivacySettings() }.buttonStyle(PillButtonStyle(prominent: true))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                } else if camera.state == .unavailable {
                    Label(L("Kamera tidak ditemukan", "No camera found"), systemImage: "video.slash").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                } else {
                    Image(systemName: "person.crop.square").font(.system(size: 36)).foregroundStyle(.white.opacity(0.25))
                }
            }
            .frame(width: 250, height: 146)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: L("Cermin", "Mirror"))
                Text(L("Cek rambut & latar sebelum kelas online atau video call.", "Check your hair and background before a class or video call."))
                    .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Circle().fill(camera.state == .running ? Color.green : .gray).frame(width: 6, height: 6)
                    Text(camera.state == .running ? L("Kamera menyala, tidak merekam", "Camera on, not recording") : L("Kamera mati", "Camera off"))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if !snapshot { camera.start() } }
        .onDisappear { camera.stop() }
    }
}

// MARK: - Pintasan (Siri Shortcuts)

@MainActor
final class ShortcutsModel: ObservableObject {
    @Published private(set) var names: [String] = []
    @Published private(set) var loaded = false
    @Published private(set) var running: String?

    func load() {
        Task.detached {
            let output = Self.run(["list"]) ?? ""
            let names = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted { $0.localizedCompare($1) == .orderedAscending }
            await MainActor.run {
                self.names = names
                self.loaded = true
            }
        }
    }

    func run(_ name: String, model: NotchModel) {
        running = name
        Task.detached {
            let ok = Self.run(["run", name]) != nil
            await MainActor.run {
                self.running = nil
                model.show(ok ? .done(L("“\(name)” selesai dijalankan", "“\(name)” finished")) : .failed(L("“\(name)” gagal dijalankan", "“\(name)” failed")))
            }
        }
    }

    func openShortcutsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// `/usr/bin/shortcuts <args>` → stdout, atau nil jika gagal.
    nonisolated private static func run(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    // Untuk snapshot.
    func preview(_ value: [String]) {
        names = value
        loaded = true
    }
}

struct ShortcutsPanel: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var shortcuts: ShortcutsModel
    @Environment(\.snapshot) private var snapshot

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: L("Pintasan", "Shortcuts"))
                Spacer()
                Button(L("Buka app Pintasan", "Open Shortcuts")) { shortcuts.openShortcutsApp() }.buttonStyle(PillButtonStyle(prominent: false))
            }
            if !shortcuts.loaded {
                Placeholder(icon: "hourglass", text: L("Memuat pintasan…", "Loading shortcuts…"))
            } else if shortcuts.names.isEmpty {
                Placeholder(icon: "bolt.slash", text: L("Belum ada pintasan. Buat dulu di app Pintasan.", "No shortcuts yet. Create one in the Shortcuts app."))
            } else if snapshot {
                grid
            } else {
                ScrollView(.vertical, showsIndicators: false) { grid }
            }
        }
        .onAppear { if !shortcuts.loaded { shortcuts.load() } }
    }

    private var grid: some View {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(shortcuts.names, id: \.self) { name in
                            Button { shortcuts.run(name, model: model) } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: shortcuts.running == name ? "hourglass" : "bolt.fill")
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accent)
                                    Text(name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                            .disabled(shortcuts.running != nil)
                        }
                    }
    }
}

// MARK: - Volume & kecerahan

/// Menampilkan perubahan volume dan kecerahan layar di notch. HUD bawaan macOS tetap muncul
/// (keputusan user): tidak perlu izin Aksesibilitas dan tidak rusak saat macOS diperbarui.
@MainActor
final class SystemLevels {
    var onChange: ((NotchModel.Level) -> Void)?

    private var enabled = false
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var lastVolume: Float?
    private var lastMuted: Bool?
    private var lastBrightness: Float?
    private var brightnessTimer: Timer?
    private let listener: AudioObjectPropertyListenerBlock
    private let deviceListener: AudioObjectPropertyListenerBlock

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private let getBrightness: GetBrightness? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
              let f = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(f, to: GetBrightness.self)
    }()

    init() {
        var weakSelf: SystemLevels?
        listener = { _, _ in Task { @MainActor in weakSelf?.readVolume(announce: true) } }
        deviceListener = { _, _ in Task { @MainActor in weakSelf?.bindDevice() } }
        weakSelf = self
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        if value {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceListener)
            bindDevice()
            lastBrightness = brightness()
            brightnessTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.readBrightness() }
            }
        } else {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceListener)
            unbindDevice()
            brightnessTimer?.invalidate()
            brightnessTimer = nil
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func bindDevice() {
        unbindDevice()
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return }
        device = id
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                var a = Self.address(selector, scope: kAudioDevicePropertyScopeOutput, element: element)
                if AudioObjectHasProperty(device, &a) { AudioObjectAddPropertyListenerBlock(device, &a, .main, listener) }
            }
        }
        readVolume(announce: false)
    }

    private func unbindDevice() {
        guard device != kAudioObjectUnknown else { return }
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                var a = Self.address(selector, scope: kAudioDevicePropertyScopeOutput, element: element)
                if AudioObjectHasProperty(device, &a) { AudioObjectRemovePropertyListenerBlock(device, &a, .main, listener) }
            }
        }
        device = AudioObjectID(kAudioObjectUnknown)
    }

    private func readVolume(announce: Bool) {
        var volume: Float32 = 0
        var found = false
        for element in [kAudioObjectPropertyElementMain, 1] where !found {
            var a = Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(device, &a), AudioObjectGetPropertyData(device, &a, 0, nil, &size, &volume) == noErr { found = true }
        }
        var muted: UInt32 = 0
        var m = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &m) { AudioObjectGetPropertyData(device, &m, 0, nil, &size, &muted) }
        guard found else { return }
        let changed = lastVolume.map { abs($0 - volume) > 0.001 } ?? false || lastMuted.map { $0 != (muted != 0) } ?? false
        lastVolume = volume
        lastMuted = muted != 0
        if announce && changed { onChange?(.volume(Double(volume), muted: muted != 0)) }
    }

    private func brightness() -> Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        return getBrightness(CGMainDisplayID(), &value) == 0 ? value : nil
    }

    private func readBrightness() {
        guard let value = brightness() else { return }
        if let last = lastBrightness, abs(last - value) > 0.004 { onChange?(.brightness(Double(value))) }
        lastBrightness = value
    }
}
