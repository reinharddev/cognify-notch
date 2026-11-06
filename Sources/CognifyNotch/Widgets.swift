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
    var link: String? = nil
    var notes: String? = nil
    /// Tautan rapat online (Zoom, Google Meet, Teams, Webex) dari URL, lokasi, atau catatan acara.
    var meeting: URL? = nil
    /// Acara dari kalender Cognify: menit sebelum mulai saat pengingat berbunyi (nil = tanpa pengingat).
    var remindMin: Int? = nil
    var fromCognify: Bool { id.hasPrefix("cognify:") }
    /// Tugas (mis. dari Moodle), bukan acara berjam: tampil di To-do.
    var isTask = false

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

/// Acara Kalender dan Pengingat terjadwal hari ini & besok dari macOS.
/// Hanya aktif saat agenda dinyalakan; macOS meminta izin Kalender dan Pengingat.
@MainActor
final class CalendarFeed: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var access: Access = .unknown
    @Published private(set) var reminderAccess: Access = .unknown

    private let store = EKEventStore()
    private var enabled = false
    private var observer: NSObjectProtocol?
    private var agendaPoll: Foundation.Timer?
    private var agendaStamp: Date?

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        guard value else {
            events = []
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            agendaPoll?.invalidate()
            agendaPoll = nil
            return
        }
        // Agenda Cognify ikut dibaca walau izin Kalender ditolak; berkasnya dipantau tiap 15 detik (hanya tanggal ubah).
        let timer = Foundation.Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfAgendaChanged() }
        }
        timer.tolerance = 5
        agendaPoll = timer
        Task { await requestAndLoad() }
    }

    private func requestAndLoad() async {
        let calendarGranted: Bool
        if #available(macOS 14.0, *) {
            calendarGranted = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            calendarGranted = await withCheckedContinuation { cont in store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) } }
        }
        access = calendarGranted ? .granted : .denied

        let remindersGranted: Bool
        if #available(macOS 14.0, *) {
            remindersGranted = (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            remindersGranted = await withCheckedContinuation { cont in store.requestAccess(to: .reminder) { ok, _ in cont.resume(returning: ok) } }
        }
        reminderAccess = remindersGranted ? .granted : .denied
        guard enabled else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
        load()
    }

    private struct FetchedReminder: Sendable {
        let id: String
        let title: String
        let due: Date
        let allDay: Bool
        let list: String
        let link: String?
        let notes: String?
        let meeting: String?
    }

    func load() {
        guard enabled else { return }
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start)!
        let calendarEvents: [CalendarEvent]
        if access == .granted {
            let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-15 * 60), end: end, calendars: nil)
            calendarEvents = store.events(matching: predicate)
                .filter { $0.status != .canceled }
                .map { CalendarEvent(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? L("(Tanpa judul)", "(No title)"),
                                     start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay, calendar: $0.calendar.title,
                                     color: Color(nsColor: $0.calendar.color), link: $0.url?.absoluteString, notes: $0.notes,
                                     meeting: CalendarEvent.meetingURL(in: [$0.url?.absoluteString, $0.location, $0.notes])) }
        } else {
            calendarEvents = []
        }

        let cognify = Self.cognifyEvents(from: now.addingTimeInterval(-15 * 60), to: end)
        guard reminderAccess == .granted else {
            events = Array((calendarEvents + cognify).sorted { $0.start < $1.start }.prefix(8))
            return
        }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: now.addingTimeInterval(-15 * 60), ending: end, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let fetched = (reminders ?? []).compactMap { reminder -> FetchedReminder? in
                guard let components = reminder.dueDateComponents, let due = components.date else { return nil }
                let allDay = components.hour == nil && components.minute == nil
                let link = reminder.url?.absoluteString
                let notes = reminder.notes
                let meeting = CalendarEvent.meetingURL(in: [link, reminder.location, notes])?.absoluteString
                return FetchedReminder(id: reminder.calendarItemIdentifier, title: reminder.title ?? L("(Tanpa judul)", "(No title)"),
                                       due: due, allDay: allDay, list: reminder.calendar.title, link: link, notes: notes, meeting: meeting)
            }
            DispatchQueue.main.async {
                guard let self, self.enabled else { return }
                let reminderEvents = fetched.map { reminder in
                    CalendarEvent(id: "reminder-" + reminder.id, title: reminder.title, start: reminder.due,
                                  allDay: reminder.allDay, calendar: reminder.list, color: .accent, link: reminder.link, notes: reminder.notes,
                                  meeting: reminder.meeting.flatMap(URL.init(string:)))
                }
                self.events = Array((calendarEvents + reminderEvents + cognify).sorted { $0.start < $1.start }.prefix(8))
            }
        }
    }

    static var agendaFile: URL { NotchLink.folder.appendingPathComponent("cognify-agenda.json") }

    private func reloadIfAgendaChanged() {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: Self.agendaFile.path))?[.modificationDate] as? Date
        guard stamp != agendaStamp else { return }
        agendaStamp = stamp
        load()
    }

    private struct AgendaFile: Decodable {
        struct Item: Decodable {
            let id: String
            let title: String
            let start: String
            let end: String?
            let allDay: Bool?
            let remindMin: Int?
            let kind: String?
            let calendar: String?
        }
        let events: [Item]?
    }

    /// Acara dari kalender Cognify (cognify-agenda.json), hanya selagi Cognify terhubung (link.json menyatakan enabled).
    /// Satu elemen rusak dilewati tanpa membuang yang lain. Berkas lebih dari 1 MB diabaikan.
    static func cognifyEvents(from: Date, to: Date) -> [CalendarEvent] {
        let fm = FileManager.default
        let consentURL = NotchLink.folder.appendingPathComponent("link.json")
        guard let consentBytes = try? Data(contentsOf: consentURL),
              let consent = try? JSONDecoder().decode(NotchLink.Consent.self, from: consentBytes), consent.enabled == true,
              let size = (try? fm.attributesOfItem(atPath: agendaFile.path))?[.size] as? Int, size <= 1_000_000,
              let bytes = try? Data(contentsOf: agendaFile),
              let file = try? JSONDecoder().decode(AgendaFile.self, from: bytes) else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func date(_ text: String) -> Date? { iso.date(from: text) ?? plain.date(from: text) }
        return (file.events ?? []).compactMap { item -> CalendarEvent? in
            guard let start = date(item.start) else { return nil }
            let end = item.end.flatMap(date)
            guard (end ?? start) >= from, start <= to else { return nil }
            return CalendarEvent(id: "cognify:" + item.id, title: item.title, start: start, end: end, allDay: item.allDay ?? false,
                                 calendar: item.calendar ?? "Cognify", color: .accent, remindMin: item.remindMin.map { max(0, $0) }, isTask: item.kind == "task")
        }
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
struct CameraInputChoice: Identifiable {
    let id: String
    let name: String
}

@MainActor
final class CameraMirror: ObservableObject {
    enum State { case idle, running, denied, unavailable }

    @Published private(set) var state: State = .idle
    @Published private(set) var devices: [CameraInputChoice] = []
    @Published private(set) var selectedDeviceID: String? = UserDefaults.standard.string(forKey: "camera.input.id")
    let session = AVCaptureSession()
    /// Lapisan pratinjau milik kamera (bukan milik tampilan): terpasang ke sesi sekali saja.
    let preview = AVCaptureVideoPreviewLayer()
    /// Semua perintah ke sesi kamera (atur, mulai, berhenti) lewat satu antrean berurutan.
    private let queue = DispatchQueue(label: "cognify.camera")
    /// Keinginan terakhir (tab Cermin terlihat atau tidak); antrean menyamakan sesi dengannya.
    private var wanted = false
    private var discoveredDevices: [AVCaptureDevice] = []

    var selectedDeviceName: String {
        devices.first(where: { $0.id == selectedDeviceID })?.name ?? L("Pilih kamera", "Choose camera")
    }

    func refreshDevices() {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .externalUnknown]
        if #available(macOS 14.0, *) { types.append(.continuityCamera) }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified)
        let found = discovery.devices
        discoveredDevices = found
        devices = found.map { CameraInputChoice(id: $0.uniqueID, name: $0.localizedName) }
        if !devices.contains(where: { $0.id == selectedDeviceID }) {
            let preferred = found.first(where: { $0.position == .front }) ?? found.first
            selectedDeviceID = preferred?.uniqueID
        }
    }

    func selectDevice(_ id: String) {
        guard devices.contains(where: { $0.id == id }) else { return }
        selectedDeviceID = id
        UserDefaults.standard.set(id, forKey: "camera.input.id")
        guard wanted, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        run()
    }

    func start() {
        wanted = true
        refreshDevices()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                Task { @MainActor in
                    if ok { self.refreshDevices(); self.run() }
                    else { self.state = .denied }
                }
            }
        default: state = .denied
        }
    }

    private func run() {
        guard wanted else { return } // tab sudah ditinggal sebelum izin dijawab
        refreshDevices()
        guard let id = selectedDeviceID,
              let device = discoveredDevices.first(where: { $0.uniqueID == id }),
              let input = try? AVCaptureDeviceInput(device: device) else {
            state = .unavailable
            return
        }
        // Sambungkan preview sebelum sesi dijalankan; perubahan input berikutnya tetap melalui antrean.
        preview.session = session
        preview.videoGravity = .resizeAspectFill
        state = .running
        let sessionBox = UncheckedBox(session)
        let inputBox = UncheckedBox(input)
        queue.async { [weak self] in
            let session = sessionBox.value
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            session.sessionPreset = .medium
            for old in session.inputs { session.removeInput(old) }
            let added = session.canAddInput(inputBox.value)
            if added { session.addInput(inputBox.value) }
            session.commitConfiguration()
            if added { session.startRunning() }
            DispatchQueue.main.async {
                guard let self else { return }
                if !added { self.state = .unavailable; return }
                if let connection = self.preview.connection, connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }
        }
    }

    func stop() {
        wanted = false
        guard state == .running else { return }
        state = .idle
        let box = UncheckedBox(session)
        queue.async {
            if box.value.isRunning { box.value.stopRunning() }
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
                if !camera.devices.isEmpty {
                    Menu {
                        ForEach(camera.devices) { device in
                            Button {
                                camera.selectDevice(device.id)
                            } label: {
                                if device.id == camera.selectedDeviceID {
                                    Label(device.name, systemImage: "checkmark")
                                } else {
                                    Text(device.name)
                                }
                            }
                        }
                    } label: {
                        Label(camera.selectedDeviceName, systemImage: "video")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .menuStyle(.borderlessButton)
                    .help(L("Pilih kamera", "Choose camera"))
                }
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
    private var brightnessFast = false
    private var lastBrightnessChange = Date.distantPast
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
            scheduleBrightness(fast: false)
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

    /// Kecerahan dibaca 2x per detik saat diam (tiap pembacaan = panggilan ke layanan sistem),
    /// lalu 10x per detik selama 2 detik setelah berubah supaya bar di notch mengikuti tombol.
    private func scheduleBrightness(fast: Bool) {
        brightnessTimer?.invalidate()
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: fast ? 0.1 : 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readBrightness() }
        }
        brightnessTimer?.tolerance = fast ? 0.02 : 0.2 // diam: boleh digabung dengan bangun lain oleh macOS
        brightnessFast = fast
    }

    private func readBrightness() {
        guard let value = brightness() else { return }
        if let last = lastBrightness, abs(last - value) > 0.004 {
            onChange?(.brightness(Double(value)))
            lastBrightnessChange = Date()
            if !brightnessFast { scheduleBrightness(fast: true) }
        } else if brightnessFast, Date().timeIntervalSince(lastBrightnessChange) > 2 {
            scheduleBrightness(fast: false)
        }
        lastBrightness = value
    }
}
