import SwiftUI

/// Daftar tugas dengan pengingat. Tugas selesai disimpan sampai akhir hari berikutnya, lalu
/// dibuang; semua di UserDefaults Mac ini.
@MainActor
final class TodoStore: ObservableObject {
    struct Item: Codable, Identifiable, Equatable {
        let id: UUID
        var text: String
        var due: Date?
        var done = false
        var doneAt: Date?
        var notified = false
    }

    @Published private(set) var items: [Item] = []
    private let key = "todo.items"

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([Item].self, from: data) {
            let cutoff = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-86_400)
            items = saved.filter { !$0.done || ($0.doneAt ?? .distantPast) > cutoff }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// Urutan tampil: belum selesai (yang ada waktunya duluan, menurut waktu), lalu yang selesai.
    var sorted: [Item] {
        items.sorted { a, b in
            if a.done != b.done { return !a.done }
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return false
            }
        }
    }

    var doneToday: Int { items.filter { $0.done && Calendar.current.isDateInToday($0.doneAt ?? .distantPast) }.count }
    var totalToday: Int { doneToday + items.filter { !$0.done }.count }

    func add(_ text: String, due: Date?) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        withAnimation(.notch) { items.append(Item(id: UUID(), text: clean, due: due ?? Self.parseDue(clean))) }
        save()
    }

    func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.notch) {
            items[i].done.toggle()
            items[i].doneAt = items[i].done ? Date() : nil
        }
        save()
    }

    func remove(_ id: UUID) {
        withAnimation(.notch) { items.removeAll { $0.id == id } }
        save()
    }

    /// Tugas yang waktunya tiba dan belum diingatkan (sekali per tugas).
    func dueNow(_ now: Date = Date()) -> [Item] {
        var due: [Item] = []
        for i in items.indices where !items[i].done && !items[i].notified {
            if let time = items[i].due, time <= now, now.timeIntervalSince(time) < 6 * 3600 {
                items[i].notified = true
                due.append(items[i])
            }
        }
        if !due.isEmpty { save() }
        return due
    }

    /// Waktu dari teks: "jam 7", "pukul 19.30", "14:00", "besok jam 9", "at 5pm".
    nonisolated static func parseDue(_ text: String, now: Date = Date()) -> Date? {
        let lower = text.lowercased()
        let pattern = #"(?:jam|pukul|at|@)\s*(\d{1,2})(?:[.:](\d{2}))?\s*(am|pm|pagi|siang|sore|malam)?|\b(\d{1,2})[.:](\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: lower).map { String(lower[$0]) } }
        guard var hour = Int(group(1) ?? group(4) ?? ""), hour < 24 else { return nil }
        let minute = Int(group(2) ?? group(5) ?? "0") ?? 0
        guard minute < 60 else { return nil }
        switch group(3) {
        case "pm", "sore", "malam": if hour < 12 { hour += 12 }
        case "siang": if hour < 11 { hour += 12 }
        case "am", "pagi": if hour == 12 { hour = 0 }
        default: break
        }
        let calendar = Calendar.current
        var day = now
        if lower.contains("besok") || lower.contains("tomorrow") { day = calendar.date(byAdding: .day, value: 1, to: now) ?? now }
        guard var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
        // "jam 7" pukul 10 pagi tanpa keterangan pagi/sore = 19.00 hari ini, bukan 07.00 besok.
        if date < now, group(3) == nil, hour < 12,
           let evening = calendar.date(bySettingHour: hour + 12, minute: minute, second: 0, of: day), evening > now {
            date = evening
        }
        if date < now, !(lower.contains("besok") || lower.contains("tomorrow")) {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date // jam yang sudah lewat = besok
        }
        return date
    }

    // Untuk snapshot.
    func preview(_ list: [Item]) { items = list }
}

/// Halaman To-do: jumlah selesai hari ini + tambah tugas (kiri), daftar (kanan).
struct TodoPanel: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var todo: TodoStore
    @State private var text = ""
    /// Pilihan waktu cepat yang dipilih (indeks `Self.options`); waktunya dihitung saat tugas ditambah.
    @State private var choice: Int?
    @FocusState private var focused: Bool
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(todo.doneToday)").font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    Text("/\(todo.totalToday)").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                }
                Text(L("Tugas selesai hari ini", "Tasks done today")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                field
                quickTimes
            }
            .frame(width: 230, alignment: .leading)
            list
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var field: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(focused ? 0.1 : 0.07))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accent.opacity(focused ? 0.7 : 0), lineWidth: 1))
                if snapshot {
                    Text(L("Tugas baru, mis. PR jam 7", "New task, e.g. call at 5pm"))
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.4)).padding(.horizontal, 8)
                } else {
                    TextField(L("Tugas baru, mis. PR jam 7", "New task, e.g. call at 5pm"), text: $text)
                        .textFieldStyle(.plain).font(.system(size: 11.5)).padding(.horizontal, 8)
                        .focused($focused)
                        .onSubmit(add)
                }
            }
            .frame(height: 28)
            Button(action: add) { Image(systemName: "plus").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 28) }
                .buttonStyle(PressableStyle())
                .background(Circle().fill(Color.accent))
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(L("Tambah tugas", "Add task"))
        }
    }

    /// Pilihan waktu cepat; waktu di teks ("jam 7") dipakai bila tidak ada yang dipilih.
    private static var options: [(label: String, date: () -> Date?)] {
        [
            (L("+30 mnt", "+30 min"), { Date().addingTimeInterval(30 * 60) }),
            (L("+1 jam", "+1 h"), { Date().addingTimeInterval(3600) }),
            (L("19.00", "7 PM"), { at(19) }),
            (L("Besok 07", "Tmrw 7"), { at(7, tomorrow: true) }),
        ]
    }

    private var due: Date? { choice.flatMap { Self.options[$0].date() } }

    private var quickTimes: some View {
        let parsed = TodoStore.parseDue(text)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                ForEach(Array(Self.options.enumerated()), id: \.offset) { index, option in
                    let selected = choice == index
                    let label = option.label
                    Button { choice = selected ? nil : index } label: {
                        Text(label).font(.system(size: 10, weight: .semibold)).lineLimit(1).fixedSize()
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(Capsule().fill(selected ? Color.accent : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let when = due ?? parsed {
                Label(L("Diingatkan ", "Reminder ") + Relative.long(when, allDay: false, now: Date()), systemImage: "bell.fill")
                    .font(.system(size: 10)).foregroundStyle(Color.accent)
            }
        }
    }

    private var list: some View {
        Group {
            if todo.items.isEmpty {
                Placeholder(icon: "checklist", text: L("Belum ada tugas. Tulis di kiri, tekan Enter.", "No tasks yet. Type on the left and press Enter."))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if snapshot {
                rows
            } else {
                ScrollView(.vertical, showsIndicators: false) { rows }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(todo.sorted) { item in TodoRow(item: item, todo: todo, now: model.now) }
        }
    }

    private func add() {
        todo.add(text, due: due)
        text = ""
        choice = nil
    }

    private static func at(_ hour: Int, tomorrow: Bool = false) -> Date? {
        let calendar = Calendar.current
        let day = tomorrow ? calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date() : Date()
        guard var date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return nil }
        if date < Date() { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
        return date
    }
}

private struct TodoRow: View {
    let item: TodoStore.Item
    @ObservedObject var todo: TodoStore
    let now: Date
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Button { todo.toggle(item.id) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.done ? Color.green : .white.opacity(0.5))
            }
            .buttonStyle(PressableStyle())
            Text(item.text)
                .font(.system(size: 11.5, weight: .medium))
                .strikethrough(item.done)
                .foregroundStyle(.white.opacity(item.done ? 0.4 : 0.95))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let due = item.due, !item.done {
                Text(Relative.long(due, allDay: false, now: now))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(due < now ? Color.orange : .white.opacity(0.5))
                    .lineLimit(1)
            }
            if hover {
                Button { todo.remove(item.id) } label: { Image(systemName: "trash").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6)).help(L("Hapus", "Delete"))
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hover ? 0.1 : 0.06)))
        .notchHover { hover = $0 }
    }
}
