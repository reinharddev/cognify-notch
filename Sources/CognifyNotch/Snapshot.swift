import AppKit
import SwiftUI

/// `cognify-notch --snapshot <folder>`: render setiap keadaan notch ke PNG dengan data contoh,
/// tanpa membuka jendela. Dipakai untuk memeriksa tampilan (bentuk, teks, tata letak) saat
/// mengembangkan; tidak dipakai app.
@MainActor
enum Snapshot {
    static func run(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date()
        func iso(_ offset: TimeInterval) -> String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.string(from: now.addingTimeInterval(offset))
        }
        let sample = NotchState(events: [
            NotchEvent(id: "1", kind: "reminder", title: "Bayar uang kas", subtitle: "Catatan harian", dueAt: iso(25 * 60), allDay: false, path: "/reminders"),
            NotchEvent(id: "2", kind: "deadline", title: "Laporan praktikum fotosintesis", subtitle: "Biologi XI", dueAt: iso(5 * 3600), allDay: false, path: "/reminders"),
            NotchEvent(id: "3", kind: "reminder", title: "Ulangan matematika bab 4", subtitle: "Jadwal ujian", dueAt: iso(26 * 3600), allDay: true, path: "/reminders"),
        ], overdue: 1, processing: 2)

        func make(app: Bool = false, _ configure: (NotchModel) -> Void) -> NotchModel {
            let m = NotchModel(bridge: nil, appMode: app)
            m.connected = true
            m.state = sample
            m.now = now
            configure(m)
            return m
        }

        let song = NowPlaying(title: "Ada Selamanya", artist: "For Revenge", album: "Perayaan Patah Hati", duration: 236,
                              elapsed: 81, rate: 1, timestamp: now, playing: true, bundle: "com.spotify.client")
        let calendarSample = [
            CalendarEvent(id: "k1", title: "Kelas online Fisika", start: now.addingTimeInterval(95 * 60), allDay: false, calendar: "Sekolah", color: .blue),
            CalendarEvent(id: "k2", title: "Latihan band", start: now.addingTimeInterval(7 * 3600), allDay: false, calendar: "Pribadi", color: .pink),
        ]
        let meetingSample = [
            CalendarEvent(id: "m1", title: "Kelas online Fisika", start: now.addingTimeInterval(4 * 60), end: now.addingTimeInterval(64 * 60), allDay: false,
                          calendar: "Sekolah", color: .blue, meeting: URL(string: "https://meet.google.com/abc-defg-hij")),
            CalendarEvent(id: "m2", title: "Latihan band", start: now.addingTimeInterval(7 * 3600), allDay: false, calendar: "Pribadi", color: .pink),
        ]
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardized
        let trayFiles = ["prd-erd.md", "static/favicon.png", "docs/PROGRESS.md", "src-tauri/icons/icon.png"].map { repo.appendingPathComponent($0) }
        var all = NotchModel.Features()
        all.calendar = true

        let cases: [(String, NotchModel)] = [
            ("s2-timer-jalan", make(app: true) { $0.expanded = true; $0.tab = .timer; $0.timer.start() }),
            ("i-app-beranda", make(app: true) { $0.expanded = true; $0.preview(level: nil, features: all); $0.media.preview(song); $0.calendar.preview(calendarSample) }),
            ("j-app-catatan", make(app: true) { $0.expanded = true; $0.tab = .notes; $0.notes.preview(["Beli kertas folio + map biru", "Ide lagu: bridge pakai akor Am-F-C-G", "Tanya Bu Rina soal remedial"]) }),
            ("k-app-seret", make(app: true) { $0.expanded = true; $0.dropTargeted = true }),
            ("l-app-kalender-mati", make(app: true) { $0.expanded = true }),
            ("a-beranda-media-kalender", make { $0.expanded = true; $0.preview(level: nil, features: all); $0.media.preview(song); $0.calendar.preview(calendarSample) }),
            ("b-sayap-media", make { $0.state = NotchState(events: [], overdue: 0, processing: 0); $0.media.preview(song) }),
            ("c-sayap-volume", make { $0.preview(level: .volume(0.62, muted: false)) }),
            ("r-clipboard", make(app: true) { $0.expanded = true; $0.tab = .clipboard; $0.clipboard.preview(["https://meet.google.com/abc-defg-hij", "Rumus luas lingkaran: L = π × r²", "Kumpul di gerbang sekolah jam 06.30 ya", "https://id.wikipedia.org/wiki/Fotosintesis", "Bab 4 halaman 88 nomor 1-10", "Nomor kelompok 3"]) }),
            ("s-timer-atur", make(app: true) { $0.expanded = true; $0.tab = .timer; $0.timer.preview(focus: 50, rest: 10) }),
            ("t-rapat-gabung", make(app: true) { $0.expanded = true; $0.preview(level: nil, features: all); $0.calendar.preview(meetingSample) }),
            ("u-sayap-download", make { $0.state = NotchState(events: [], overdue: 0, processing: 0); $0.downloads.preview(.init(name: "Modul Biologi Bab 3.pdf", percent: 42)) }),
            ("v-media-lengkap", make(app: true) { $0.expanded = true; $0.preview(level: nil, features: all); $0.media.preview(song) }),
            ("w-rapat-alert", make(app: true) { $0.expanded = true; $0.toast = .alert(title: "Kelas online Fisika", detail: "Mulai 5 menit lagi", action: .join(URL(string: "https://meet.google.com/abc")!)) }),
            ("x-besar-inggris", make(app: true) { $0.prefs.scale = 1.12; $0.prefs.language = .en; $0.expanded = true; $0.preview(level: nil, features: all); $0.calendar.preview(meetingSample) }),
            ("p-sayap-lagu-baru", make { $0.state = NotchState(events: [], overdue: 0, processing: 0); $0.media.preview(song); $0.preview(songBanner: "Ada Selamanya (Versi Akustik Live di Jakarta)") }),
            ("q-sayap-lagu-pendek", make { $0.state = NotchState(events: [], overdue: 0, processing: 0); $0.media.preview(song); $0.preview(songBanner: "Ada Selamanya") }),
            ("m-sayap-charger", make { $0.state = NotchState(events: [], overdue: 0, processing: 0); $0.preview(notice: .charging(percent: 53, full: false)) }),
            ("n-sayap-airpods", make { $0.state = NotchState(events: [], overdue: 0, processing: 0); $0.preview(notice: .audioConnected(name: "AirPods Pro milik Reinhard", battery: "L 80% R 75%")) }),
            ("o-sayap-baterai-lemah", make { $0.preview(notice: .lowBattery(percent: 10)) }),
            ("d-sayap-kecerahan", make { $0.preview(level: .brightness(0.35)) }),
            ("e-tray", make { $0.expanded = true; $0.tab = .tray; $0.tray.preview(trayFiles) }),
            ("f-seret-pilih", make { $0.expanded = true; $0.dropTargeted = true }),
            ("g-cermin", make { $0.expanded = true; $0.tab = .mirror }),
            ("h-pintasan", make { $0.expanded = true; $0.tab = .shortcuts; $0.shortcuts.preview(["Mode belajar", "Matikan notifikasi", "Buka Classroom", "Catat jam belajar", "Putar lo-fi"]) }),
            ("1-tertutup", make { $0.state = NotchState(events: [], overdue: 0, processing: 0) }),
            ("2-sayap-deadline", make { _ in }),
            ("3-terbuka-beranda", make { $0.expanded = true; $0.note = "Kumpul tugas biologi besok jam 10" }),
            ("4-terbuka-timer", make { $0.expanded = true; $0.tab = .timer; $0.timer.start(); $0.timer.pause() }),
            ("6-tersimpan", make { $0.expanded = true; $0.toast = .done("“Bab 2 Fotosintesis” masuk Knowledge") }),
            ("7-timer-selesai", make { $0.expanded = true; $0.toast = .alert(title: "Waktu fokus selesai", detail: "Istirahat 5 menit dulu, lalu lanjut lagi.", action: .startTimer("Mulai istirahat")) }),
            ("8-sayap-timer", make { $0.state = NotchState(events: [], overdue: 0, processing: 0); $0.timer.start() }),
            ("9-tanpa-notch", make { $0.hasNotch = false; $0.notchSize = CGSize(width: 190, height: 24); $0.expanded = true }),
        ]
        for (name, model) in cases {
            Lang.english = model.prefs.language == .en
            let view = ZStack(alignment: .top) {
                // Latar menyerupai menu bar + desktop supaya bentuk notch hitam terlihat.
                LinearGradient(colors: [Color(white: 0.32), Color(white: 0.22)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color(white: 0.85)).frame(height: model.notchSize.height).opacity(0.9)
                NotchRoot(model: model).environment(\.snapshot, true)
            }
            .frame(width: NotchController.windowSize.width, height: NotchController.windowSize.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: folder.appendingPathComponent("\(name).png"))
            }
            model.timer.reset()
        }
        Lang.english = false
        print("snapshot → \(folder.path)")
    }
}
