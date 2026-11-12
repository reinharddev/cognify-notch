import NotchTime
import SwiftUI

/// Stopwatch (dengan lap) dan hitung mundur cepat ("10 menit" untuk masak), terpisah dari
/// Pomodoro. Hitung mundur disimpan sebagai jam selesai, jadi tetap benar walau notch dibuka
/// ulang; waktu ditampilkan hanya saat halaman terlihat atau di sayap notch.
@MainActor
final class ClockTools: ObservableObject {
    struct Countdown: Codable, Identifiable, Equatable {
        let id: UUID
        let label: String
        let end: Date
        let total: TimeInterval
    }

    // Stopwatch
    @Published private(set) var started: Date?          // sedang berjalan sejak
    @Published private(set) var accumulated: TimeInterval = 0 // waktu sebelum jeda terakhir
    @Published private(set) var laps: [TimeInterval] = []

    @Published private(set) var countdowns: [Countdown] = []
    var onFinish: ((Countdown) -> Void)?

    // Alarm: jam tertentu, berulang di hari terpilih (kosong = sekali saja). Disimpan sebagai jam dan hari, bukan satu waktu absolut.
    struct Alarm: Codable, Identifiable, Equatable {
        let id: UUID
        var hour: Int
        var minute: Int
        /// Hari berulang menurut Calendar.weekday (1 Minggu sampai 7 Sabtu); kosong = sekali.
        var days: [Int]
        var label: String
        var enabled: Bool
        /// Tanggal (yyyy-MM-dd) terakhir alarm berbunyi, supaya tidak berbunyi dua kali sehari.
        var firedOn: String?
    }
    @Published private(set) var alarms: [Alarm] = []
    var onAlarm: ((Alarm) -> Void)?
    private var alarmTicker: Timer?
    private let alarmKey = "clock.alarms"
    /// Alarm yang terlambat (Mac tidur atau notch baru dibuka) tetap berbunyi sampai selama ini sesudah jamnya.
    private static let alarmGrace = 10
    private var ticker: Timer?
    private let key = "clock.countdowns"

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([Countdown].self, from: data) {
            countdowns = saved.filter { $0.end > Date() }
        }
        schedule()
        if let data = UserDefaults.standard.data(forKey: alarmKey), let saved = try? JSONDecoder().decode([Alarm].self, from: data) { alarms = saved }
        let t = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAlarms() }
        }
        t.tolerance = 5
        alarmTicker = t
        checkAlarms()
    }

    var running: Bool { started != nil }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        accumulated + (started.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggleStopwatch() {
        if let started {
            accumulated += Date().timeIntervalSince(started)
            self.started = nil
        } else {
            started = Date()
        }
    }

    func lap() {
        guard running else { return }
        withAnimation(.notch) { laps.insert(elapsed(), at: 0) }
    }

    func resetStopwatch() {
        started = nil
        accumulated = 0
        withAnimation(.notch) { laps = [] }
    }

    // MARK: Hitung mundur

    func start(minutes: Int) {
        let total = TimeInterval(minutes * 60)
        let label = minutes < 60 ? L("\(minutes) menit", "\(minutes) min") : L("\(minutes / 60) jam", "\(minutes / 60) h")
        withAnimation(.notch) { countdowns.append(Countdown(id: UUID(), label: label, end: Date().addingTimeInterval(total), total: total)) }
        save()
        schedule()
    }

    func cancel(_ id: UUID) {
        withAnimation(.notch) { countdowns.removeAll { $0.id == id } }
        save()
        schedule()
    }

    // MARK: Alarm

    func addAlarm(hour: Int, minute: Int, days: [Int], label: String) {
        let alarm = Alarm(id: UUID(), hour: hour, minute: minute, days: days.sorted(), label: label.trimmingCharacters(in: .whitespaces), enabled: true, firedOn: nil)
        withAnimation(.notch) { alarms.append(alarm); alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) } }
        saveAlarms()
        checkAlarms()
    }

    func setAlarm(_ id: UUID, enabled: Bool) {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[i].enabled = enabled
        if enabled { alarms[i].firedOn = nil }
        saveAlarms()
    }

    func removeAlarm(_ id: UUID) {
        withAnimation(.notch) { alarms.removeAll { $0.id == id } }
        saveAlarms()
    }

    private func saveAlarms() {
        if let data = try? JSONEncoder().encode(alarms) { UserDefaults.standard.set(data, forKey: alarmKey) }
    }

    /// Alarm yang sedang jatuh tempo pada `now` (aturannya di NotchTime/AlarmSchedule.swift, ada tesnya).
    static func dueAlarms(_ alarms: [Alarm], at now: Date) -> [Alarm] {
        alarms.filter { AlarmSchedule.isDue(hour: $0.hour, minute: $0.minute, days: $0.days, enabled: $0.enabled, firedOn: $0.firedOn, now: now, graceMinutes: alarmGrace) }
    }

    private func checkAlarms() {
        let now = Date()
        let due = Self.dueAlarms(alarms, at: now)
        guard !due.isEmpty else { return }
        for alarm in due {
            guard let i = alarms.firstIndex(where: { $0.id == alarm.id }) else { continue }
            alarms[i].firedOn = AlarmSchedule.dayKey(now)
            if alarm.days.isEmpty { alarms[i].enabled = false } // alarm sekali padam sesudah berbunyi
        }
        saveAlarms()
        due.forEach { onAlarm?($0) }
    }

    /// Hitung mundur yang paling cepat selesai (untuk sayap notch).
    var nearest: Countdown? { countdowns.min { $0.end < $1.end } }

    private func save() {
        if let data = try? JSONEncoder().encode(countdowns) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// Satu timer menunggu hitung mundur terdekat selesai (tanpa detak tiap detik).
    private func schedule() {
        ticker?.invalidate()
        guard let next = nearest else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: max(0.05, next.end.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
    }

    private func fire() {
        let now = Date()
        let done = countdowns.filter { $0.end <= now.addingTimeInterval(0.2) }
        withAnimation(.notch) { countdowns.removeAll { done.contains($0) } }
        save()
        done.forEach { onFinish?($0) }
        schedule()
    }

    static func clock(_ seconds: TimeInterval, tenths: Bool = false) -> String {
        let s = max(0, seconds)
        let whole = Int(s)
        let base = whole >= 3600 ? String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
                                 : String(format: "%02d:%02d", whole / 60, whole % 60)
        return tenths ? base + String(format: ".%d", Int((s - Double(whole)) * 10)) : base
    }

    // Untuk snapshot.
    func preview(elapsed: TimeInterval, laps: [TimeInterval], countdowns: [Countdown]) {
        accumulated = elapsed
        self.laps = laps
        self.countdowns = countdowns
    }
}

/// Halaman Stopwatch & Timer: stopwatch di kiri, hitung mundur di kanan.
struct ClockPanel: View {
    @ObservedObject var clock: ClockTools
    @State private var custom = 20
    @Environment(\.snapshot) private var snapshot

    private static let presets = [1, 3, 5, 10, 15, 30]

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            stopwatch.frame(width: 250, alignment: .leading)
            Divider().overlay(Color.white.opacity(0.08))
            countdownColumn
            Divider().overlay(Color.white.opacity(0.08))
            alarmColumn
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var stopwatch: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L("Stopwatch", "Stopwatch"))
            Group {
                if clock.running && !snapshot {
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        Text(ClockTools.clock(clock.elapsed(at: context.date), tenths: true))
                    }
                } else {
                    Text(ClockTools.clock(clock.elapsed(), tenths: true))
                }
            }
            .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
            HStack(spacing: 6) {
                Button(action: clock.toggleStopwatch) {
                    Label(clock.running ? L("Jeda", "Pause") : (clock.elapsed() > 0 ? L("Lanjut", "Resume") : L("Mulai", "Start")),
                          systemImage: clock.running ? "pause.fill" : "play.fill")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                Button(L("Lap", "Lap"), action: clock.lap).buttonStyle(PillButtonStyle(prominent: false)).disabled(!clock.running)
                Button(L("Ulang", "Reset"), action: clock.resetStopwatch).buttonStyle(PillButtonStyle(prominent: false))
                    .disabled(clock.running || clock.elapsed() == 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(clock.laps.prefix(3).enumerated()), id: \.offset) { index, value in
                    Text("Lap \(clock.laps.count - index)   \(ClockTools.clock(value, tenths: true))")
                        .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    @State private var alarmTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var alarmDays: Set<Int> = []
    @State private var alarmLabel = ""

    private static let dayOrder: [(weekday: Int, id: String, en: String)] = [(2, "Sen", "Mon"), (3, "Sel", "Tue"), (4, "Rab", "Wed"), (5, "Kam", "Thu"), (6, "Jum", "Fri"), (7, "Sab", "Sat"), (1, "Min", "Sun")]

    private var alarmColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L("Alarm", "Alarm"))
            HStack(spacing: 6) {
                DatePicker("", selection: $alarmTime, displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.field)
                Button {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
                    clock.addAlarm(hour: c.hour ?? 7, minute: c.minute ?? 0, days: Array(alarmDays), label: alarmLabel)
                    alarmLabel = ""
                } label: { Label(L("Tambah", "Add"), systemImage: "plus") }
                    .buttonStyle(PillButtonStyle(prominent: true))
            }
            HStack(spacing: 3) {
                ForEach(Self.dayOrder, id: \.weekday) { d in
                    let on = alarmDays.contains(d.weekday)
                    Button { if on { alarmDays.remove(d.weekday) } else { alarmDays.insert(d.weekday) } } label: {
                        Text(L(d.id, d.en)).font(.system(size: 9.5, weight: .semibold)).lineLimit(1).fixedSize()
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(Capsule().fill(on ? Color.accent.opacity(0.85) : Color.white.opacity(0.1)))
                            .foregroundStyle(on ? Color.black : Color.white.opacity(0.75))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            Text(alarmDays.isEmpty ? L("Tanpa hari dipilih: berbunyi sekali.", "No day picked: rings once.") : L("Berulang di hari terpilih.", "Repeats on the picked days."))
                .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
            if clock.alarms.isEmpty {
                Placeholder(icon: "alarm", text: L("Atur jam, lalu Tambah.", "Set a time, then Add."))
            } else {
                VStack(spacing: 5) {
                    ForEach(clock.alarms) { alarm in
                        HStack(spacing: 8) {
                            Text(String(format: "%02d:%02d", alarm.hour, alarm.minute))
                                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(alarm.enabled ? .white : .white.opacity(0.35))
                            Text(alarmSubtitle(alarm)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                            Spacer()
                            Toggle("", isOn: Binding(get: { alarm.enabled }, set: { clock.setAlarm(alarm.id, enabled: $0) }))
                                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                            Button { clock.removeAlarm(alarm.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).help(L("Hapus", "Delete"))
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06)))
                    }
                }
            }
        }
        .frame(width: 250, alignment: .leading)
    }

    private func alarmSubtitle(_ a: ClockTools.Alarm) -> String {
        let days = a.days.isEmpty ? L("sekali", "once") : (a.days.count == 7 ? L("tiap hari", "every day") : Self.dayOrder.filter { a.days.contains($0.weekday) }.map { L($0.id, $0.en) }.joined(separator: " "))
        return a.label.isEmpty ? days : "\(a.label) · \(days)"
    }

    private var countdownColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L("Hitung mundur", "Countdown"))
            HStack(spacing: 4) {
                ForEach(Self.presets, id: \.self) { minutes in
                    Button { clock.start(minutes: minutes) } label: {
                        Text("\(minutes)m").font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            HStack(spacing: 4) {
                Button { custom = max(1, custom - 5) } label: { Image(systemName: "minus").font(.system(size: 9, weight: .bold)).frame(width: 10, height: 14) }
                    .buttonStyle(PillButtonStyle(prominent: false))
                Text(L("\(custom) menit", "\(custom) min")).font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .lineLimit(1).fixedSize().frame(minWidth: 58)
                Button { custom = min(240, custom + 5) } label: { Image(systemName: "plus").font(.system(size: 9, weight: .bold)).frame(width: 10, height: 14) }
                    .buttonStyle(PillButtonStyle(prominent: false))
                Button { clock.start(minutes: custom) } label: { Label(L("Mulai", "Start"), systemImage: "play.fill") }
                    .buttonStyle(PillButtonStyle(prominent: true))
            }
            if clock.countdowns.isEmpty {
                Placeholder(icon: "hourglass", text: L("Pilih durasi untuk mulai menghitung mundur.", "Pick a length to start a countdown."))
            } else if snapshot {
                rows(Date())
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in rows(context.date) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rows(_ now: Date) -> some View {
        VStack(spacing: 5) {
            ForEach(clock.countdowns.sorted { $0.end < $1.end }) { item in
                HStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 2.5)
                        Circle().trim(from: 0, to: CGFloat(1 - item.end.timeIntervalSince(now) / item.total))
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    .frame(width: 16, height: 16)
                    Text(item.label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(ClockTools.clock(item.end.timeIntervalSince(now)))
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    Button { clock.cancel(item.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).help(L("Batalkan", "Cancel"))
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06)))
            }
        }
    }
}
