import Foundation

struct RadarJourneyReport: Identifiable {
    let journey: RadarJourney
    let receipts: [RadarReceipt]
    let distance: RadarDistanceReading?
    var id: String { journey.id }
    var completed: [RadarReceipt] { receipts.filter { $0.completedAt != nil && $0.cancelledAt == nil } }
    var confirmed: [RadarReceipt] { completed.filter { $0.status == .received && $0.amount != nil } }
    var received: Double { confirmed.reduce(0) { $0 + ($1.amount ?? 0) } }
    var pending: Int { completed.count - confirmed.count }
    var fuelCost: Double? {
        guard let distance, distance.unpricedKilometers == 0 else { return nil }
        return distance.fuelCost
    }
    var afterFuel: Double? { fuelCost.map { received - $0 } }
    var gpsComplete: Bool {
        guard let distance, !distance.hasGap, let first = distance.firstAt, let last = distance.lastAt else { return false }
        return first.timeIntervalSince(journey.startedAt) <= 30
            && (journey.endedAt ?? journey.lastHeartbeat).timeIntervalSince(last) <= 60
    }
    var eligibleForPlanning: Bool {
        journey.endedAt != nil && !journey.interrupted && journey.trackedSeconds >= 1800
            && completed.count >= 2 && pending == 0 && gpsComplete && afterFuel != nil
    }
    var hourlyAfterFuel: Double? {
        guard eligibleForPlanning, let afterFuel else { return nil }
        return afterFuel / (journey.trackedSeconds / 3600)
    }
    init(journey: RadarJourney, payments: RadarPaymentState, distances: RadarDistanceState) {
        self.journey = journey
        let end = journey.endedAt ?? journey.lastHeartbeat
        receipts = payments.receipts.filter {
            guard let completed = $0.completedAt else { return false }
            return completed >= journey.startedAt && completed <= end
        }
        distance = distances.readings.first { $0.id == journey.id }
    }
}

struct RadarPlanningWindow: Identifiable {
    let weekday: Int
    let startHour: Int
    let samples: Int
    let medianHourlyAfterFuel: Double
    var id: String { "\(weekday)|\(startHour)" }
}

enum RadarHistoryPlanner {
    static func windows(reports: [RadarJourneyReport], now: Date) -> [RadarPlanningWindow] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let groups = Dictionary(grouping: reports.filter {
            $0.eligibleForPlanning && $0.journey.startedAt <= now
                && now.timeIntervalSince($0.journey.startedAt) <= 56 * 86400
        }) { report in
            "\(calendar.component(.weekday, from: report.journey.startedAt))|\(calendar.component(.hour, from: report.journey.startedAt) / 3 * 3)"
        }
        return groups.values.compactMap { group in
            guard group.count >= 3, let first = group.first else { return nil }
            // One independent observation per day, not several restarts in one evening.
            let days = Set(group.map { calendar.startOfDay(for: $0.journey.startedAt) })
            guard days.count >= 3 else { return nil }
            let ratesByDay = Dictionary(grouping: group) { calendar.startOfDay(for: $0.journey.startedAt) }
            let daily = ratesByDay.values.compactMap { day -> Double? in
                let seconds = day.reduce(0) { $0 + $1.journey.trackedSeconds }
                guard seconds > 0 else { return nil }
                return day.reduce(0) { $0 + ($1.afterFuel ?? 0) } / (seconds / 3600)
            }.sorted()
            let center = daily.count / 2
            let median = daily.count % 2 == 0 ? (daily[center - 1] + daily[center]) / 2 : daily[center]
            return RadarPlanningWindow(weekday: calendar.component(.weekday, from: first.journey.startedAt),
                startHour: calendar.component(.hour, from: first.journey.startedAt) / 3 * 3,
                samples: days.count, medianHourlyAfterFuel: median)
        }.sorted { $0.medianHourlyAfterFuel > $1.medianHourlyAfterFuel }
    }
}
