import SwiftUI
import WidgetKit

// Widget macOS untuk Cognify Notch: Agenda dan To-do. Datanya dari widget.json yang ditulis app Notch
// (lihat Sources/CognifyNotch/WidgetShared.swift). Ekstensi ini tidak punya akses jaringan.

struct Entry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snap: Self.sample) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let snap = WidgetSnapshot.read()
        completion(Entry(date: .now, snap: context.isPreview && snap.events.isEmpty && snap.todos.isEmpty ? Self.sample : snap))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snap = WidgetSnapshot.read()
        let now = Date()
        // Satu entri per batas acara (mulai/selesai) supaya daftar "berikutnya" berganti tepat waktu.
        var stops: Set<Date> = [now]
        for e in snap.events {
            for t in [e.start, e.end].compactMap({ $0 }) where t > now.timeIntervalSince1970 && t < now.timeIntervalSince1970 + 86_400 {
                stops.insert(Date(timeIntervalSince1970: t))
            }
        }
        for c in snap.timers ?? [] where c.end > now.timeIntervalSince1970 && c.end < now.timeIntervalSince1970 + 86_400 {
            stops.insert(Date(timeIntervalSince1970: c.end))
        }
        // Tiap 10 menit selama 3 jam: wajah Mimik melirik ke arah lain tiap penyegaran.
        for i in 1...18 { stops.insert(Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 600) + Double(i)) * 600)) }
        let entries = stops.sorted().prefix(48).map { Entry(date: $0, snap: snap) }
        completion(Timeline(entries: Array(entries), policy: .after(now.addingTimeInterval(15 * 60))))
    }
    static var sample: WidgetSnapshot {
        let n = Date().timeIntervalSince1970
        return WidgetSnapshot(updatedAt: n, events: [
            .init(id: "1", title: "Kelas Fisika", start: n + 3600, end: n + 7200, allDay: false, calendar: "Kampus", isTask: false),
            .init(id: "2", title: "Rapat kelompok", start: n + 10_800, end: nil, allDay: false, calendar: "Cognify", isTask: false),
            .init(id: "3", title: "Laporan praktikum", start: n + 86_400, end: nil, allDay: false, calendar: "Fisika Dasar", isTask: true),
        ], todos: [
            .init(id: "a", title: "Baca bab 4", done: false, due: nil),
            .init(id: "b", title: "Kumpulkan esai", done: false, due: n + 20_000),
            .init(id: "c", title: "Beli buku", done: true, due: nil),
        ], weather: .init(tempC: 30, code: 3, place: "Bogor"),
           water: .init(goalMl: 2000, todayMl: 1200),
           timers: [.init(id: "t", title: "Fokus belajar", end: n + 1500, total: 1800)],
           notes: [.init(id: "n1", text: "Tanya dosen soal revisi bab 3", date: n - 600), .init(id: "n2", text: "Beli kertas A4", date: n - 4000)])
    }
}

func tr(_ a: String, _ b: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("id") == true ? a : b
}

/// "Moodle, SCK-CI_2026_Advanced Mathematics_12.2" -> "Advanced Mathematics" (nama mapel saja).
func shortCalendar(_ name: String) -> String {
    guard name.hasPrefix("Moodle") else { return name }
    let course = name.drop(while: { $0 != "," }).dropFirst().trimmingCharacters(in: .whitespaces)
    let parts = course.split(separator: "_").map(String.init)
    return parts.count >= 4 ? parts[2..<(parts.count - 1)].joined(separator: " ") : (course.isEmpty ? "Moodle" : course)
}

private struct EventRow: View {
    let e: WidgetSnapshot.Event
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(e.isTask ? Color.orange : Color.accentColor).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Group {
                    if e.allDay { Text(tr("Sepanjang hari", "All day")) }
                    else if e.isTask { Text(Date(timeIntervalSince1970: e.start), style: .relative) + Text(" · ") + Text(shortCalendar(e.calendar)) }
                    else { Text(Date(timeIntervalSince1970: e.start), style: .time) + Text(" · ") + Text(shortCalendar(e.calendar)) }
                }
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 30)
    }
}

struct AgendaView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family
    private var upcoming: [WidgetSnapshot.Event] {
        let now = entry.date.timeIntervalSince1970
        return entry.snap.events.filter { ($0.end ?? $0.start + (($0.allDay || $0.isTask) ? 86_400 : 0)) >= now }
    }
    var body: some View {
        let limit = family == .systemSmall ? 2 : family == .systemMedium ? 3 : 7
        let items = Array(upcoming.prefix(limit))
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Agenda", "Agenda")).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).textCase(.uppercase)
            if items.isEmpty {
                Spacer()
                Text(tr("Tidak ada acara terdekat", "Nothing coming up")).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(items) { EventRow(e: $0) }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct TodoView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let open = entry.snap.todos.filter { !$0.done }
        let done = entry.snap.todos.count - open.count
        let limit = family == .systemSmall ? 3 : family == .systemMedium ? 4 : 9
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("To-do").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                Text("\(done)/\(entry.snap.todos.count)").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
            if open.isEmpty {
                Spacer()
                Text(entry.snap.todos.isEmpty ? tr("Belum ada tugas", "No tasks yet") : tr("Semua selesai 🎉", "All done 🎉"))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(open.prefix(limit))) { t in
                    HStack(spacing: 6) {
                        Image(systemName: "circle").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(t.title).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 0)
                        if let due = t.due, family != .systemSmall {
                            Text(Date(timeIntervalSince1970: due), style: .time).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                if open.count > limit {
                    Text("+\(open.count - limit)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CognifyAgenda", provider: Provider()) { AgendaView(entry: $0) }
            .configurationDisplayName("Agenda")
            .description(tr("Acara, pengingat, dan tenggat tugas terdekat.", "Upcoming events, reminders and deadlines."))
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CognifyTodo", provider: Provider()) { TodoView(entry: $0) }
            .configurationDisplayName("To-do")
            .description(tr("Tugas yang belum selesai di Cognify Notch.", "Open tasks from Cognify Notch."))
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct CognifyWidgets: WidgetBundle {
    var body: some Widget {
        AgendaWidget()
        TodoWidget()
        MimikWidget()
        WeatherWidget()
        WaterWidget()
        TimerWidget()
        NotesWidget()
    }
}
