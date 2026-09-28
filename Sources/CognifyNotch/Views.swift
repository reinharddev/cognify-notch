import SwiftUI
import UniformTypeIdentifiers

// MARK: - Mode snapshot

private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Render ke gambar (Snapshot.swift): ImageRenderer tidak bisa menggambar komponen AppKit
    /// (kolom teks, spinner, area drop), jadi diganti gambar biasa.
    var snapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

// MARK: - Bentuk notch

/// Notch MacBook: sudut atas melengkung ke luar (menyatu dengan tepi layar), sudut bawah membulat.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + bottom, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - bottom), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Akar

struct NotchRoot: View {
    @ObservedObject var model: NotchModel
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(top: model.expanded ? 12 : 6, bottom: model.expanded ? 24 : 12)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(model.expanded ? 0.45 : 0), radius: 16, y: 6)
                content
                    .padding(.horizontal, model.expanded ? 12 : 6) // di dalam lengkungan atas
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipShape(NotchShape(top: model.expanded ? 12 : 6, bottom: model.expanded ? 24 : 12))
            }
            .frame(width: model.size.width, height: model.size.height)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onChange(of: model.dropTargeted) { targeted in
            if targeted { model.setExpanded(true) }
        }
    }

    @ViewBuilder private var content: some View {
        if model.expanded {
            ExpandedView(model: model)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).animation(.notch.delay(0.06)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
        } else if let live = model.live {
            LiveWings(live: live, gap: model.notchSize.width, media: model.media, spectrum: model.spectrum)
                .frame(height: model.notchSize.height)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}

// MARK: - Sayap saat tertutup

struct LiveWings: View {
    let live: NotchModel.Live
    let gap: CGFloat
    @ObservedObject var media: MediaMonitor
    let spectrum: Spectrum

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if live.media {
                    Artwork(media: media, size: 20)
                } else if let title = live.title {
                    HStack(spacing: 6) {
                        Image(systemName: live.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(live.tint)
                        Text(title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 8)
                } else {
                    Image(systemName: live.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(live.tint)
                }
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(width: gap - 12) // area notch fisik
            Group {
                if live.media {
                    Equalizer(playing: true, spectrum: spectrum)
                } else if let level = live.level {
                    LevelBar(value: level, tint: live.tint)
                } else {
                    Text(live.text)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct LevelBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.18))
            Capsule().fill(tint).frame(width: 46 * max(0, min(1, value)))
        }
        .frame(width: 46, height: 5)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: value)
    }
}

// MARK: - Terbuka

struct ExpandedView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.frame(height: model.notchSize.height)
            Group {
                if model.dropTargeted {
                    DropChoice(model: model)
                } else if let toast = model.toast, toast.isBanner {
                    ToastBanner(model: model, toast: toast)
                } else {
                    switch model.tab {
                    case .home: HomePanel(model: model, media: model.media, calendar: model.calendar)
                    case .notes: NotesPanel(model: model, notes: model.notes)
                    case .tray: TrayPanel(model: model, tray: model.tray)
                    case .timer: TimerPanel(timer: model.timer)
                    case .mirror: MirrorPanel(camera: model.camera)
                    case .shortcuts: ShortcutsPanel(model: model, shortcuts: model.shortcuts)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .foregroundStyle(.white)
    }

    /// Baris setinggi notch: kiri & kanan notch fisik, tengahnya dibiarkan kosong.
    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                if !model.appMode {
                    Circle().fill(model.connected ? Color.accent : .gray).frame(width: 7, height: 7)
                }
                Text("Cognify").font(.system(size: 12, weight: .semibold))
                if !model.appMode, let overdue = model.state?.overdue, overdue > 0 {
                    Text("\(overdue) terlambat")
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.red.opacity(0.28)))
                        .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.6))
                }
            }
            .padding(.leading, 12)
            Spacer(minLength: model.notchSize.width)
            HStack(spacing: 2) {
                ForEach(model.tabs, id: \.self) { tab in
                    TabButton(icon: tab.icon, label: tab.label, selected: model.tab == tab,
                              badge: tab == .tray && !model.tray.items.isEmpty ? model.tray.items.count : nil) { model.tab = tab }
                }
            }
            .padding(.trailing, 10)
        }
    }
}

struct TabButton: View {
    let icon: String
    let label: String
    let selected: Bool
    var badge: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: { withAnimation(.notch) { action() } }) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 30, height: 22)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0)))
                .foregroundStyle(selected ? .white : .white.opacity(0.55))
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text("\(badge)").font(.system(size: 8.5, weight: .bold)).padding(.horizontal, 3.5).padding(.vertical, 0.5)
                            .background(Capsule().fill(Color.accent)).offset(x: 3, y: -2)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// MARK: - Beranda: deadline + catatan cepat

struct HomePanel: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var media: MediaMonitor
    @ObservedObject var calendar: CalendarFeed

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if model.features.media, media.nowPlaying != nil {
                MediaCard(media: media, spectrum: model.spectrum).frame(width: 186)
                Divider().overlay(Color.white.opacity(0.08))
                AgendaList(model: model, calendar: calendar, rows: 3, compact: true).frame(width: 222)
                QuickNote(model: model, compact: true)
            } else {
                AgendaList(model: model, calendar: calendar, rows: 3).frame(width: 340)
                QuickNote(model: model, compact: false)
            }
        }
    }
}

/// Satu baris agenda: kegiatan/deadline Cognify atau acara Kalender macOS.
enum AgendaEntry: Identifiable {
    case cognify(NotchEvent)
    case calendar(CalendarEvent)

    var id: String {
        switch self {
        case .cognify(let e): return "c-" + e.id
        case .calendar(let e): return "k-" + e.id
        }
    }

    var date: Date {
        switch self {
        case .cognify(let e): return e.due
        case .calendar(let e): return e.start
        }
    }
}

struct AgendaList: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var calendar: CalendarFeed
    let rows: Int
    var compact = false

    private var entries: [AgendaEntry] {
        let cognify = model.appMode ? [] : (model.state?.events ?? []).map(AgendaEntry.cognify)
        let cal = model.features.calendar ? calendar.events.map(AgendaEntry.calendar) : []
        return (cognify + cal).sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: model.features.calendar ? "Agenda" : "Berikutnya").padding(.bottom, 2)
            if model.appMode && !model.features.calendar {
                Placeholder(icon: "calendar", text: "Nyalakan Kalender lewat ikon notch di menu bar")
            } else if model.appMode && entries.isEmpty {
                if calendar.access != .denied { Placeholder(icon: "checkmark.seal", text: "Tidak ada acara hari ini & besok") }
            } else if model.appMode {
                agendaRows
            } else if !model.connected {
                Placeholder(icon: "hourglass", text: "Menghubungkan ke Cognify…")
            } else if !entries.isEmpty {
                agendaRows
            } else if model.state != nil {
                Placeholder(icon: "checkmark.seal", text: "Tidak ada deadline 7 hari ke depan")
            }
            if model.features.calendar && calendar.access == .denied {
                Text("Izinkan Kalender di Pengaturan Sistem → Privasi untuk melihat acaramu di sini.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).padding(.leading, 6)
            }
            Spacer(minLength: 0)
            if !model.appMode, let processing = model.state?.processing, processing > 0 {
                HStack(spacing: 5) {
                    Spinner()
                    Text("Memproses \(processing) item…").font(.system(size: 10.5))
                }
                .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

struct EventRow: View {
    let event: NotchEvent
    let now: Date
    var compact = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: event.kind == "deadline" ? "calendar.badge.clock" : "bell.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(soon ? Color.orange : Color.accent)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill((soon ? Color.orange : Color.accent).opacity(0.18)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if compact {
                        Text([Relative.long(event.due, allDay: event.allDay, now: now), event.subtitle].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10.5)).foregroundStyle(soon ? Color.orange : .white.opacity(0.5)).lineLimit(1)
                    } else if let subtitle = event.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if !compact {
                    Text(Relative.long(event.due, allDay: event.allDay, now: now))
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(soon ? Color.orange : .white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hover ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var soon: Bool { !event.allDay && event.due.timeIntervalSince(now) < 60 * 60 }
}

extension AgendaList {
    var agendaRows: some View {
        ForEach(entries.prefix(rows)) { entry in
            switch entry {
            case .cognify(let event):
                EventRow(event: event, now: model.now, compact: compact) { model.open(event.path) }
            case .calendar(let event):
                CalendarRow(event: event, now: model.now, compact: compact) { calendar.openCalendarApp() }
            }
        }
    }
}

struct CalendarRow: View {
    let event: CalendarEvent
    let now: Date
    var compact = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 4, height: 24).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(compact ? "\(Relative.long(event.start, allDay: event.allDay, now: now)) · \(event.calendar)" : event.calendar)
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 6)
                if !compact {
                    Text(Relative.long(event.start, allDay: event.allDay, now: now))
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hover ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Buka app Kalender")
    }
}

struct QuickNote: View {
    @ObservedObject var model: NotchModel
    var compact = false
    @FocusState private var focused: Bool
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Catatan cepat")
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(focused ? 0.1 : 0.07))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accent.opacity(focused ? 0.7 : 0), lineWidth: 1))
                if snapshot {
                    Text(model.note.isEmpty ? "Tulis sesuatu, tekan Enter…" : model.note)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(model.note.isEmpty ? 0.4 : 1))
                        .padding(8)
                } else {
                    TextField("Tulis sesuatu, tekan Enter…", text: $model.note, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .lineLimit(3, reservesSpace: true)
                        .focused($focused)
                        .onSubmit { model.saveNote() }
                        .padding(8)
                }
            }
            .frame(height: 66)
            HStack(spacing: 5) {
                if !compact {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 10))
                    Text(model.appMode ? "Seret file ke notch → tray" : "Seret file atau tautan ke notch").font(.system(size: 10.5))
                }
                Spacer()
                Button(model.savingNote ? "Menyimpan…" : "Simpan") { model.saveNote() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(model.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.savingNote)
            }
            .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Timer

struct TimerPanel: View {
    @ObservedObject var timer: StudyTimer

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: timer.progress)
                VStack(spacing: 0) {
                    Text(StudyTimer.clock(timer.remaining))
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(timer.mode.label).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 104, height: 104)
            .padding(.leading, 6)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(StudyTimer.Mode.allCases, id: \.self) { mode in
                        Button("\(mode.label) \(mode.minutes)m") { withAnimation(.notch) { timer.select(mode) } }
                            .buttonStyle(PillButtonStyle(prominent: timer.mode == mode))
                    }
                }
                HStack(spacing: 8) {
                    Button(action: { timer.toggle() }) {
                        Label(timer.running ? "Jeda" : (timer.isIdle ? "Mulai" : "Lanjut"),
                              systemImage: timer.running ? "pause.fill" : "play.fill")
                            .frame(width: 92)
                    }
                    .buttonStyle(PillButtonStyle(prominent: true, large: true))
                    Button(action: { timer.reset() }) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(PillButtonStyle(prominent: false, large: true))
                    .disabled(timer.isIdle)
                    .help("Ulang")
                }
                Text(timer.sessionsToday == 0 ? "Belum ada sesi fokus hari ini" : "\(timer.sessionsToday) sesi fokus hari ini")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private var tint: Color { timer.mode == .focus ? .accent : .green }
}

// MARK: - Catatan (app mandiri)

struct NotesPanel: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var notes: LocalNotes
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: notes.items.isEmpty ? "Catatan" : "Catatan · \(notes.items.count)")
            if notes.items.isEmpty {
                Placeholder(icon: "note.text", text: "Belum ada catatan. Tulis di Beranda → Catatan cepat.")
            } else if snapshot {
                list
            } else {
                ScrollView(.vertical, showsIndicators: false) { list }
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(notes.items) { note in NoteRow(note: note, notes: notes, model: model) }
        }
    }
}

struct NoteRow: View {
    let note: LocalNote
    @ObservedObject var notes: LocalNotes
    @ObservedObject var model: NotchModel
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.text).font(.system(size: 12)).lineLimit(2)
                Text(Self.format(note.date)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 8)
            if hover {
                Button { notes.copy(note); model.show(.done("Catatan disalin")) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).help("Salin")
                Button { notes.remove(note) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("Hapus")
            }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hover ? 0.1 : 0.06)))
        .onHover { hover = $0 }
    }

    static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "'Hari ini' HH.mm" : "EEE d MMM, HH.mm"
        return f.string(from: date)
    }
}

// MARK: - Pesan

extension NotchModel.Toast {
    /// Pesan yang menggantikan isi panel saat notch terbuka (selain status "sedang menyimpan").
    var isBanner: Bool {
        if case .working = self { return false }
        return true
    }
}

struct ToastBanner: View {
    @ObservedObject var model: NotchModel
    let toast: NotchModel.Toast

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(Circle().fill(tint.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if case .alert(_, _, let action?) = toast {
                switch action {
                case .startTimer(let label):
                    Button(label) { model.toast = nil; model.timer.start() }.buttonStyle(PillButtonStyle(prominent: true, large: true))
                case .open(let path):
                    Button("Buka") { model.toast = nil; model.open(path) }.buttonStyle(PillButtonStyle(prominent: true, large: true))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    private var icon: String {
        switch toast {
        case .done: return "checkmark"
        case .failed: return "exclamationmark.triangle.fill"
        case .alert(_, _, .startTimer?): return "timer"
        default: return "bell.fill"
        }
    }

    private var tint: Color {
        switch toast {
        case .done: return .green
        case .failed: return .orange
        default: return .accent
        }
    }

    private var title: String {
        switch toast {
        case .done(let text), .failed(let text), .working(let text): return text
        case .alert(let title, _, _): return title
        }
    }

    private var detail: String? {
        if case .alert(_, let detail, _) = toast { return detail }
        if case .failed = toast { return "Coba lagi, atau buka Cognify untuk detailnya." }
        return nil
    }
}

// MARK: - Komponen kecil

/// Spinner kecil tanpa komponen AppKit (ProgressView tidak ikut terender di snapshot).
struct Spinner: View {
    @State private var spin = false
    var body: some View {
        Circle()
            .trim(from: 0.15, to: 1)
            .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true } }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.42))
            .padding(.leading, 6)
    }
}

struct Placeholder: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12))
            Text(text).font(.system(size: 11.5))
        }
        .foregroundStyle(.white.opacity(0.5))
        .padding(.leading, 6).padding(.top, 4)
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent: Bool
    var large = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 12 : 11, weight: .semibold))
            .padding(.horizontal, large ? 14 : 10)
            .padding(.vertical, large ? 7 : 4)
            .background(Capsule().fill(prominent ? Color.accent.opacity(enabled ? 0.9 : 0.35) : Color.white.opacity(0.12)))
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.5))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

// MARK: - Isi yang diseret

enum DropLoader {
    /// File lokal, tautan web, dan teks biasa dari item yang diseret (Finder, browser, editor).
    static func load(_ providers: [NSItemProvider], done: @escaping ([URL], [URL], [String]) -> Void) {
        var files: [URL] = [], links: [URL] = [], texts: [String] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for provider in providers {
            group.enter()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, url.isFileURL { lock.lock(); files.append(url); lock.unlock() }
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") { lock.lock(); links.append(url); lock.unlock() }
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    lock.lock()
                    if let url = URL(string: clean), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !clean.contains(" ") {
                        links.append(url)
                    } else if !clean.isEmpty {
                        texts.append(clean)
                    }
                    lock.unlock()
                    group.leave()
                }
            } else {
                group.leave()
            }
        }
        group.notify(queue: .main) { done(files, links, texts) }
    }
}
