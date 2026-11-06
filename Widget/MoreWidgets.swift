import SwiftUI
import WidgetKit

// Widget tambahan: Mimik, Cuaca, Air minum, Timer, Catatan cepat. Tiap widget membawa wajah Mimik kecil
// yang ekspresinya mengikuti isinya. Data dari widget.json (WidgetShared.swift).

private let inkText = Color(red: 0.914, green: 0.922, blue: 0.925)

private func weatherInfo(_ code: Int) -> (symbol: String, text: String, expression: String) {
    switch code {
    case 0: return ("sun.max.fill", tr("Cerah", "Clear"), "happy")
    case 1, 2: return ("cloud.sun.fill", tr("Cerah berawan", "Partly cloudy"), "content")
    case 3: return ("cloud.fill", tr("Berawan", "Cloudy"), "idle")
    case 45, 48: return ("cloud.fog.fill", tr("Berkabut", "Foggy"), "curious")
    case 51...57: return ("cloud.drizzle.fill", tr("Gerimis", "Drizzle"), "content")
    case 61...67, 80...82: return ("cloud.rain.fill", tr("Hujan", "Rain"), "sad")
    case 71...77, 85, 86: return ("cloud.snow.fill", tr("Salju", "Snow"), "surprised")
    case 95...99: return ("cloud.bolt.rain.fill", tr("Badai petir", "Thunderstorm"), "scared")
    default: return ("cloud.fill", tr("Berawan", "Cloudy"), "idle")
    }
}

/// Wajah di lingkaran gelap, supaya tampil sama di latar terang maupun gelap.
private struct FaceBadge: View {
    let expression: String
    var body: some View {
        MimikFace(expression: expression).clipShape(Circle())
    }
}

// MARK: Mimik

struct MimikView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let mood = Mood.overall(entry.snap, now: entry.date)
        Group {
            if family == .systemSmall {
                VStack(spacing: 8) {
                    MimikFace(expression: mood.expression, look: Mood.wander(entry.date))
                    Text(mood.line).font(.system(size: 12, weight: .semibold)).foregroundStyle(inkText)
                        .lineLimit(2).multilineTextAlignment(.center)
                }
            } else {
                HStack(spacing: 16) {
                    MimikFace(expression: mood.expression, look: Mood.wander(entry.date))
                    Text(mood.line).font(.system(size: family == .systemMedium ? 17 : 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(inkText).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .containerBackground(Color.black, for: .widget)
    }
}

struct MimikWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CognifyMimik", provider: Provider()) { MimikView(entry: $0) }
            .configurationDisplayName("Mimik")
            .description(tr("Wajah kecil yang berubah ekspresi mengikuti harimu: tenggat, minum, tugas, jam.", "A little face whose mood follows your day: deadlines, water, tasks, time."))
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: Cuaca

struct WeatherView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if let w = entry.snap.weather {
                let info = weatherInfo(w.code)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.place).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).lineLimit(1)
                        Text("\(w.tempC)°").font(.system(size: family == .systemSmall ? 40 : 52, weight: .semibold, design: .rounded))
                        Spacer(minLength: 0)
                        Image(systemName: info.symbol).symbolRenderingMode(.multicolor).font(.system(size: 18))
                        Text(info.text).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    FaceBadge(expression: w.tempC >= 33 ? "tired" : info.expression).frame(width: family == .systemSmall ? 34 : 64)
                }
            } else {
                Text(tr("Nyalakan Cuaca di Cognify Notch", "Turn on Weather in Cognify Notch")).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CognifyWeather", provider: Provider()) { WeatherView(entry: $0) }
            .configurationDisplayName(tr("Cuaca", "Weather"))
            .description(tr("Suhu dan kondisi dari cuaca Notch, dengan wajah Mimik.", "Temperature and conditions from Notch, with a Mimik face."))
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: Air minum

struct WaterView: View {
    let entry: Entry
    var body: some View {
        let w = entry.snap.water ?? .init(goalMl: 2000, todayMl: 0)
        let ratio = w.goalMl > 0 ? min(1, Double(w.todayMl) / Double(w.goalMl)) : 0
        let face = ratio >= 1 ? "joy" : ratio >= 0.5 ? "happy" : ratio > 0 ? "content" : "sleepy"
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.blue.opacity(0.2), lineWidth: 8)
                Circle().trim(from: 0, to: ratio).stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                MimikFace(expression: face).clipShape(Circle()).padding(11)
            }
            Text("\(w.todayMl) / \(w.goalMl) ml").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CognifyWater", provider: Provider()) { WaterView(entry: $0) }
            .configurationDisplayName(tr("Air minum", "Water"))
            .description(tr("Progres minum hari ini terhadap target.", "Today's water intake against your goal."))
            .supportedFamilies([.systemSmall])
    }
}

// MARK: Timer

struct TimerView: View {
    let entry: Entry
    var body: some View {
        let now = entry.date
        let running = (entry.snap.timers ?? []).filter { Date(timeIntervalSince1970: $0.end) > now }.sorted { $0.end < $1.end }
        Group {
            if let t = running.first {
                let end = Date(timeIntervalSince1970: t.end)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t.title.isEmpty ? "Timer" : t.title).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        FaceBadge(expression: "focus").frame(width: 30)
                    }
                    Spacer(minLength: 0)
                    Text(timerInterval: now...end, countsDown: true)
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
                    ProgressView(timerInterval: Date(timeIntervalSince1970: t.end - t.total)...end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(.orange)
                    if running.count > 1 { Text(tr("+\(running.count - 1) timer lain", "+\(running.count - 1) more")).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            } else {
                VStack(spacing: 8) {
                    FaceBadge(expression: "sleepy").frame(width: 56)
                    Text(tr("Tidak ada timer", "No timer running")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct TimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CognifyTimer", provider: Provider()) { TimerView(entry: $0) }
            .configurationDisplayName("Timer")
            .description(tr("Hitung mundur yang sedang berjalan di Notch.", "The countdown running in Notch."))
            .supportedFamilies([.systemSmall])
    }
}

// MARK: Catatan cepat

struct NotesView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let notes = (entry.snap.notes ?? []).sorted { $0.date > $1.date }
        let limit = family == .systemSmall ? 2 : family == .systemMedium ? 3 : 7
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tr("Catatan", "Notes")).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                FaceBadge(expression: notes.isEmpty ? "sleepy" : "curious").frame(width: 24)
            }
            if notes.isEmpty {
                Spacer()
                Text(tr("Belum ada catatan", "No notes yet")).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(notes.prefix(limit))) { n in
                    Text(n.text).font(.system(size: 13)).lineLimit(family == .systemSmall ? 2 : 2)
                        .padding(.vertical, 2)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct NotesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CognifyNotes", provider: Provider()) { NotesView(entry: $0) }
            .configurationDisplayName(tr("Catatan cepat", "Quick notes"))
            .description(tr("Catatan terbaru dari Notch.", "Your latest notes from Notch."))
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
