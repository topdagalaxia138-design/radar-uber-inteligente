import Foundation

struct RadarFinanceObservation: Codable, Identifiable {
    let metric: RadarFinanceMetric
    let value: Double
    let screen: String
    let weekKey: String?
    var observedAt: Date
    var id: String { metric.rawValue + "|" + (weekKey ?? "latest") }
}

struct RadarFinanceState: Codable {
    var observations: [RadarFinanceObservation] = []
    var movements: [RadarWalletMovement]? = nil

    mutating func observe(_ reading: RadarFinanceReading, at date: Date) {
        for (metric, value) in reading.values {
            guard !metric.isWeekly || reading.weekKey != nil else { continue }
            let observation = RadarFinanceObservation(metric: metric, value: value, screen: reading.screen,
                weekKey: metric.isWeekly ? reading.weekKey : nil, observedAt: date)
            observations.removeAll { $0.id == observation.id }
            observations.append(observation)
        }
        var captured = movements ?? []
        for movement in reading.movements {
            if let existing = captured.first(where: { $0.id == movement.id }),
               existing.kind == .cashTripBalance && movement.kind == .tripBalance { continue }
            captured.removeAll { $0.id == movement.id }
            captured.append(movement)
        }
        movements = Array(captured.sorted { $0.occurredAt > $1.occurredAt }.prefix(500))
        observations = Array(observations.sorted { $0.observedAt > $1.observedAt }.prefix(64))
    }

    func latest(_ metric: RadarFinanceMetric, now: Date) -> RadarFinanceObservation? {
        let week = RadarFinanceParser.weekKey(at: now)
        return observations.filter {
            $0.metric == metric && (!metric.isWeekly || $0.weekKey == week)
        }.max { $0.observedAt < $1.observedAt }
    }

    func capturedThisWeek(now: Date) -> [RadarWalletMovement] {
        let week = RadarFinanceParser.weekKey(at: now)
        return (movements ?? []).filter { RadarFinanceParser.weekKey(at: $0.occurredAt) == week }
    }

    static func confirmedReading(_ first: RadarFinanceReading?, _ second: RadarFinanceReading?) -> RadarFinanceReading? {
        guard let first, let second, first == second else { return nil }
        return first
    }
}

final class RadarFinanceStore {
    private let url: URL
    private let lock = NSLock()
    init(url: URL) { self.url = url }
    func load() -> RadarFinanceState {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }
    @discardableResult
    func observe(_ reading: RadarFinanceReading, at date: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var state = read()
        state.observe(reading, at: date)
        do {
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
            return true
        } catch { return false }
    }
    private func read() -> RadarFinanceState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(RadarFinanceState.self, from: data) else { return RadarFinanceState() }
        return state
    }
}
