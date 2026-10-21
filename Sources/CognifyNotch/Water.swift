import SwiftUI

/// Pengingat minum: target harian, catatan minum per jam, dan pengingat di jam aktif.
/// Semua tersimpan di UserDefaults Mac ini (catatan 14 hari terakhir).
@MainActor
final class WaterTracker: ObservableObject {
    struct Sip: Codable, Equatable {
        let date: Date
        let ml: Int
    }

    @Published private(set) var sips: [Sip] = []
    @Published var goal: Int { didSet { save() } }          // ml per hari
    @Published var glass: Int { didSet { save() } }         // ml sekali minum
    @Published var startHour: Int { didSet { save() } }     // jam aktif pengingat
    @Published var endHour: Int { didSet { save() } }
    @Published var interval: Int { didSet { save() } }      // menit antar pengingat
    @Published var reminders: Bool { didSet { save() } }

    private let defaults = UserDefaults.standard
    private var lastReminder: Date?
    private var loading = true

    init() {
        let d = UserDefaults.standard
        goal = d.object(forKey: "water.goal") as? Int ?? 2000
        glass = d.object(forKey: "water.glass") as? Int ?? 250
        startHour = d.object(forKey: "water.start") as? Int ?? 8
        endHour = d.object(forKey: "water.end") as? Int ?? 21
        interval = d.object(forKey: "water.interval") as? Int ?? 60
        reminders = d.object(forKey: "water.reminders") as? Bool ?? true
        if let data = d.data(forKey: "water.sips"), let saved = try? JSONDecoder().decode([Sip].self, from: data) {
            let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
            sips = saved.filter { $0.date > cutoff }
        }
        loading = false
    }

    private func save() {
        guard !loading else { return }
        defaults.set(goal, forKey: "water.goal")
        defaults.set(glass, forKey: "water.glass")
        defaults.set(startHour, forKey: "water.start")
        defaults.set(endHour, forKey: "water.end")
        defaults.set(interval, forKey: "water.interval")
        defaults.set(reminders, forKey: "water.reminders")
        if let data = try? JSONEncoder().encode(sips) { defaults.set(data, forKey: "water.sips") }
    }

    var today: [Sip] { sips.filter { Calendar.current.isDateInToday($0.date) } }
    var total: Int { today.reduce(0) { $0 + $1.ml } }
    var progress: Double { goal > 0 ? min(1, Double(total) / Double(goal)) : 0 }

    func drink(_ ml: Int? = nil) {
        withAnimation(.notch) { sips.append(Sip(date: Date(), ml: ml ?? glass)) }
        lastReminder = nil
        save()
    }

    func undo() {
        guard let last = today.last, let index = sips.lastIndex(of: last) else { return }
        withAnimation(.notch) { _ = sips.remove(at: index) }
        save()
    }

    /// ml per jam (jam aktif saja) untuk grafik.
    var hourly: [(hour: Int, ml: Int)] {
        let calendar = Calendar.current
        let hours = Array(min(startHour, endHour)...max(startHour, endHour))
        return hours.map { hour in (hour, today.filter { calendar.component(.hour, from: $0.date) == hour }.reduce(0) { $0 + $1.ml }) }
    }

    /// Waktunya mengingatkan: jam aktif, target belum tercapai, sudah lewat `interval` menit
    /// sejak minum terakhir (atau awal jam aktif) dan sejak pengingat terakhir.
    func reminderDue(at now: Date = Date()) -> Bool {
        guard reminders, total < goal else { return false }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        guard hour >= startHour, hour < endHour else { return false }
        let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: now) ?? now
        let lastSip = today.last?.date ?? start
        let since = max(lastSip, start, lastReminder ?? .distantPast)
        guard now.timeIntervalSince(since) >= Double(interval * 60) else { return false }
        lastReminder = now
        return true
    }

    // Untuk snapshot.
    func preview(_ list: [(hour: Int, ml: Int)]) {
        let calendar = Calendar.current
        sips = list.compactMap { item in
            calendar.date(bySettingHour: item.hour, minute: 15, second: 0, of: Date()).map { Sip(date: $0, ml: item.ml) }
        }
    }
}

/// Halaman Air: total hari ini + tombol minum (kiri), grafik per jam atau pengaturan (kanan).
struct WaterPanel: View {
    @ObservedObject var water: WaterTracker
    @State private var editing = false

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Self.liters(water.total))
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("/ " + Self.liters(water.goal) + " L")
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                }
                HStack(spacing: 6) {
                    Text(L("Hari ini", "Today")).foregroundStyle(.white.opacity(0.5))
                    Text("\(Int(water.progress * 100))%").fontWeight(.bold)
                    if water.total >= water.goal {
                        Text(L("Target tercapai", "Goal reached")).foregroundStyle(Color.green)
                    }
                }
                .font(.system(size: 11))
                ProgressBar(value: water.progress, tint: .cyan).frame(width: 190)
                HStack(spacing: 6) {
                    Button { water.drink() } label: { Label(L("Minum \(water.glass) ml", "Drink \(water.glass) ml"), systemImage: "drop.fill") }
                        .buttonStyle(PillButtonStyle(prominent: true))
                    Button { withAnimation(.notch) { editing.toggle() } } label: {
                        Label(editing ? L("Grafik", "Chart") : L("Atur", "Settings"), systemImage: editing ? "chart.bar.fill" : "slider.horizontal.3")
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    if !water.today.isEmpty {
                        Button { water.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                            .buttonStyle(PillButtonStyle(prominent: false)).help(L("Batalkan minum terakhir", "Undo last drink"))
                    }
                }
                Toggle(isOn: $water.reminders) {
                    Text(L("Ingatkan tiap \(water.interval) menit, \(water.startHour).00-\(water.endHour).00",
                           "Remind every \(water.interval) min, \(water.startHour):00-\(water.endHour):00"))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                }
                .toggleStyle(MiniSwitch())
            }
            .frame(width: 240, alignment: .leading)
            if editing {
                settings
            } else {
                chart
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var chart: some View {
        let data = water.hourly
        let top = max(data.map(\.ml).max() ?? 0, water.glass * 2)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(data, id: \.hour) { item in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.ml > 0 ? Color.cyan.opacity(0.85) : Color.white.opacity(0.08))
                        .frame(height: max(4, 96 * CGFloat(item.ml) / CGFloat(top)))
                    Text(item.hour % 3 == 0 ? String(format: "%02d", item.hour) : " ")
                        .font(.system(size: 8.5, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .help("\(item.hour).00: \(item.ml) ml")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 4)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper2(label: L("Target harian", "Daily goal"), value: "\(Self.liters(water.goal)) L") {
                water.goal = max(500, water.goal - 250)
            } plus: { water.goal = min(6000, water.goal + 250) }
            Stepper2(label: L("Sekali minum", "Per drink"), value: "\(water.glass) ml") {
                water.glass = max(50, water.glass - 50)
            } plus: { water.glass = min(1000, water.glass + 50) }
            Stepper2(label: L("Jam aktif", "Active hours"), value: "\(water.startHour).00-\(water.endHour).00") {
                if water.startHour > 0 { water.startHour -= 1 }
            } plus: { if water.startHour < water.endHour - 1 { water.startHour += 1 } }
                minus2: { if water.endHour > water.startHour + 1 { water.endHour -= 1 } }
                plus2: { if water.endHour < 24 { water.endHour += 1 } }
            Stepper2(label: L("Ingatkan tiap", "Remind every"), value: L("\(water.interval) menit", "\(water.interval) min")) {
                water.interval = max(15, water.interval - 15)
            } plus: { water.interval = min(240, water.interval + 15) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func liters(_ ml: Int) -> String {
        let value = Double(ml) / 1000
        let text = value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return Lang.english ? text : text.replacingOccurrences(of: ".", with: ",")
    }
}

/// "Label   [−] nilai [+]" (dan pasangan kedua untuk rentang jam).
private struct Stepper2: View {
    let label: String
    let value: String
    let minus: () -> Void
    let plus: () -> Void
    var minus2: (() -> Void)? = nil
    var plus2: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).frame(width: 96, alignment: .leading)
            small("minus", minus)
            if let minus2, let plus2 {
                small("plus", plus)
                Text(value).font(.system(size: 11.5, weight: .semibold).monospacedDigit()).frame(minWidth: 84)
                small("minus", minus2)
                small("plus", plus2)
            } else {
                Text(value).font(.system(size: 11.5, weight: .semibold).monospacedDigit()).frame(minWidth: 64)
                small("plus", plus)
            }
        }
    }

    private func small(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).frame(width: 22, height: 20)
                .background(Capsule().fill(Color.white.opacity(0.1))).contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Bar progres tipis.
struct ProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(tint).frame(width: geo.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 5)
        .animation(.notch, value: value)
    }
}

/// Saklar kecil bergaya notch (Toggle bawaan tidak ikut terender di snapshot).
struct MiniSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { withAnimation(.notch) { configuration.isOn.toggle() } } label: {
            HStack(spacing: 7) {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Color.accent : Color.white.opacity(0.18)).frame(width: 26, height: 15)
                    Circle().fill(.white).frame(width: 11, height: 11).padding(.horizontal, 2)
                }
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
