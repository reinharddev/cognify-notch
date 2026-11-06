import Combine
import Foundation
import WidgetKit

/// Menulis `widget.json` (agenda + to-do) tiap data berubah, lalu meminta macOS menyegarkan widget.
/// Hanya berkas lokal; tidak ada jaringan. Widget membacanya dari dalam sandbox (lihat Widget/).
@MainActor
final class WidgetExport {
    private let model: NotchModel
    private var bag = Set<AnyCancellable>()
    private var last: WidgetSnapshot?

    init(model: NotchModel) { self.model = model }

    func start() {
        Publishers.MergeMany([
            model.calendar.$events.map { _ in () }.eraseToAnyPublisher(),
            model.todo.$items.map { _ in () }.eraseToAnyPublisher(),
            model.todo.$moodle.map { _ in () }.eraseToAnyPublisher(),
            model.weather.$now.map { _ in () }.eraseToAnyPublisher(),
            model.water.$sips.map { _ in () }.eraseToAnyPublisher(),
            model.water.$goal.map { _ in () }.eraseToAnyPublisher(),
            model.clock.$countdowns.map { _ in () }.eraseToAnyPublisher(),
            model.notes.$items.map { _ in () }.eraseToAnyPublisher(),
        ])
        .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
        .sink { [weak self] in MainActor.assumeIsolated { self?.write() } }
        .store(in: &bag)
        // Jaga-jaga bila ada perubahan yang terlewat (mis. hari berganti).
        Foundation.Timer.publish(every: 600, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.write() } }
            .store(in: &bag)
        write()
    }

    private func write() {
        let m = model
        let events = (m.calendar.events + m.todo.moodle).map {
            WidgetSnapshot.Event(id: $0.id, title: $0.title, start: $0.start.timeIntervalSince1970,
                                 end: $0.end?.timeIntervalSince1970, allDay: $0.allDay, calendar: $0.calendar, isTask: $0.isTask)
        }
        let todos = m.todo.items.map {
            WidgetSnapshot.Todo(id: $0.id.uuidString, title: $0.text, done: $0.done, due: $0.due?.timeIntervalSince1970)
        }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        var snap = WidgetSnapshot(updatedAt: 0, events: events.sorted { $0.start < $1.start }, todos: todos)
        snap.weather = m.weather.now.map { .init(tempC: $0.temperature, code: $0.code, place: $0.place) }
        snap.water = .init(goalMl: m.water.goal, todayMl: m.water.sips.filter { $0.date >= startOfToday }.reduce(0) { $0 + $1.ml })
        snap.timers = m.clock.countdowns.map { .init(id: $0.id.uuidString, title: $0.label, end: $0.end.timeIntervalSince1970, total: $0.total) }
        snap.notes = m.notes.items.prefix(8).map { .init(id: $0.id.uuidString, text: String($0.text.prefix(240)), date: $0.date.timeIntervalSince1970) }
        if snap == last { return }
        last = snap
        snap.updatedAt = Date().timeIntervalSince1970
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: WidgetSnapshot.folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(snap).write(to: WidgetSnapshot.file, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Folder tidak bisa ditulis: coba lagi pada perubahan berikutnya.
        }
    }
}
