import Foundation

struct RadarJourney: Codable, Identifiable {
    var id = UUID().uuidString
    let startedAt: Date
    var lastHeartbeat: Date
    var endedAt: Date?
    var trackedSeconds = 0.0
    var interrupted = false
}

struct RadarJourneyState: Codable {
    var journeys: [RadarJourney] = []
    var currentID: String?
    mutating func start(at date: Date) {
        if let i = journeys.firstIndex(where: { $0.id == currentID && $0.endedAt == nil }) {
            journeys[i].endedAt = journeys[i].lastHeartbeat
            journeys[i].interrupted = true
        }
        let item = RadarJourney(startedAt: date, lastHeartbeat: date)
        journeys.append(item)
        currentID = item.id
        if journeys.count > 500 { journeys.removeFirst(journeys.count - 500) }
    }
    mutating func heartbeat(at date: Date) {
        guard let i = journeys.firstIndex(where: { $0.id == currentID && $0.endedAt == nil }) else { return }
        let delta = date.timeIntervalSince(journeys[i].lastHeartbeat)
        guard delta > 0 else { return }
        if delta <= 20 { journeys[i].trackedSeconds += delta }
        else { journeys[i].interrupted = true }
        journeys[i].lastHeartbeat = date
    }
    mutating func finish(at date: Date, interrupted: Bool = false) {
        heartbeat(at: date)
        guard let i = journeys.firstIndex(where: { $0.id == currentID && $0.endedAt == nil }) else { return }
        journeys[i].endedAt = date
        journeys[i].interrupted = journeys[i].interrupted || interrupted
        currentID = nil
    }
    func active(at date: Date) -> RadarJourney? {
        journeys.first { $0.id == currentID && $0.endedAt == nil
            && date.timeIntervalSince($0.lastHeartbeat) >= 0 && date.timeIntervalSince($0.lastHeartbeat) <= 30 }
    }
}

final class RadarJourneyStore {
    private let url: URL
    private let lock = NSLock()
    init(url: URL) { self.url = url }
    func load() -> RadarJourneyState {
        lock.lock(); defer { lock.unlock() }; return read()
    }
    @discardableResult func update(_ change: (inout RadarJourneyState) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var value = read(); change(&value)
        do { try JSONEncoder().encode(value).write(to: url, options: .atomic); return true }
        catch { return false }
    }
    private func read() -> RadarJourneyState {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(RadarJourneyState.self, from: data) else { return .init() }
        return value
    }
}

struct RadarDistanceReading: Codable, Identifiable {
    let id: String // journey ID, no GPS coordinates are persisted
    var kilometers = 0.0
    var fuelLiters = 0.0
    var fuelCost = 0.0
    var unpricedKilometers = 0.0
    var hasGap = false
    var firstAt: Date?
    var lastAt: Date?
}

struct RadarDistanceState: Codable {
    var readings: [RadarDistanceReading] = []
    mutating func record(journeyID: String, kilometers: Double, at date: Date,
                         price: Double, consumption: Double, gap: Bool) {
        guard kilometers.isFinite, kilometers >= 0 else { return }
        if !readings.contains(where: { $0.id == journeyID }) { readings.append(.init(id: journeyID)) }
        let i = readings.firstIndex { $0.id == journeyID }!
        readings[i].kilometers += kilometers
        readings[i].hasGap = readings[i].hasGap || gap
        readings[i].firstAt = readings[i].firstAt ?? date
        readings[i].lastAt = date
        if RadarFuelCost.perKilometer(pricePerLiter: price, kilometersPerLiter: consumption) != nil {
            readings[i].fuelLiters += kilometers / consumption
            readings[i].fuelCost += kilometers / consumption * price
        } else { readings[i].unpricedKilometers += kilometers }
        if readings.count > 500 { readings.removeFirst(readings.count - 500) }
    }
}

final class RadarDistanceStore {
    private let url: URL
    private let lock = NSLock()
    init(url: URL) { self.url = url }
    func load() -> RadarDistanceState { lock.lock(); defer { lock.unlock() }; return read() }
    @discardableResult func update(_ change: (inout RadarDistanceState) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var value = read(); change(&value)
        do { try JSONEncoder().encode(value).write(to: url, options: .atomic); return true } catch { return false }
    }
    private func read() -> RadarDistanceState {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(RadarDistanceState.self, from: data) else { return .init() }
        return value
    }
}

enum RadarDistancePolicy {
    static func accepts(meters: Double, seconds: Double, accuracy: Double) -> Bool {
        meters.isFinite && seconds.isFinite && accuracy.isFinite && accuracy >= 0 && accuracy <= 35
            && seconds > 0 && seconds <= 60 && meters >= max(8, accuracy * 0.5) && meters / seconds <= 45
    }
}
