import Foundation

struct RadarPassStrategy {
    struct Cycle {
        let activatedAt: Date
        let expiresAt: Date
        let cost: Double
        let confirmedEarnings: Double
        var remainingToRecover: Double { max(0, cost - confirmedEarnings) }
        var recovered: Bool { remainingToRecover == 0 }
    }

    static func activeCycle(movements: [RadarWalletMovement], receipts: [RadarReceipt], now: Date) -> Cycle? {
        guard let debit = movements.filter({ $0.kind == .passDebit && $0.amount < 0 && $0.occurredAt <= now }).max(by: { $0.occurredAt < $1.occurredAt }) else { return nil }
        let expiry = debit.occurredAt.addingTimeInterval(86400)
        guard now < expiry else { return nil }
        let refunded = movements.contains { $0.kind == .passCredit && $0.occurredAt >= debit.occurredAt && $0.occurredAt <= now }
        guard !refunded else { return nil }
        var seen = Set<String>()
        let earnings = receipts.reduce(0.0) { sum, receipt in
            guard let completed = receipt.completedAt, completed >= debit.occurredAt, completed <= now,
                  receipt.cancelledAt == nil, let amount = receipt.driverEarnings, amount.isFinite, amount >= 0,
                  seen.insert(receipt.id).inserted else { return sum }
            return sum + amount
        }
        return Cycle(activatedAt: debit.occurredAt, expiresAt: expiry, cost: -debit.amount, confirmedEarnings: earnings)
    }

    struct WorkWindow {
        let start: Date
        let end: Date
        let estimatedNetPerHour: Double
    }
    struct Plan {
        let activation: Date
        let coveredHours: Double
        let estimatedNetAfterPass: Double
    }
    // Input windows must be non-overlapping and based on measured history.
    static func bestActivation(windows: [WorkWindow], cost: Double, now: Date) -> Plan? {
        guard cost.isFinite, cost >= 0 else { return nil }
        let valid = windows.filter { $0.end > max($0.start, now) && $0.estimatedNetPerHour.isFinite && $0.estimatedNetPerHour > 0 }.sorted { $0.start < $1.start }
        guard zip(valid, valid.dropFirst()).allSatisfy({ $0.0.end <= $0.1.start }) else { return nil }
        return valid.map { candidate in
            let start = max(now, candidate.start)
            let end = start.addingTimeInterval(86400)
            var hours = 0.0
            var net = -cost
            for window in valid {
                let overlap = max(0, min(end, window.end).timeIntervalSince(max(start, window.start))) / 3600
                hours += overlap
                net += overlap * window.estimatedNetPerHour
            }
            return Plan(activation: start, coveredHours: hours, estimatedNetAfterPass: net)
        }.filter { $0.estimatedNetAfterPass > 0 }.max { $0.estimatedNetAfterPass < $1.estimatedNetAfterPass }
    }
}
