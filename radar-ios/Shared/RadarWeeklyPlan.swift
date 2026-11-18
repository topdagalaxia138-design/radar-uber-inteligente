import Foundation

struct RadarWeeklyPlan: Codable {
    var rental = 835.0
    var monthlyPersonalGoal = 1000.0
    var workDays = 7
    var hoursPerDay = 6.0
    // nil means unknown, not zero. This is a budget, never an observed charge.
    var passBudget: Double?

    var isValid: Bool {
        rental.isFinite && rental >= 0
        && monthlyPersonalGoal.isFinite && monthlyPersonalGoal >= 0
        && (1...7).contains(workDays)
        && hoursPerDay.isFinite && hoursPerDay > 0 && hoursPerDay <= 6
        && (passBudget == nil || (passBudget!.isFinite && passBudget! >= 0))
    }
    var weeklyPersonalGoal: Double? {
        isValid ? monthlyPersonalGoal * 12 / 52 : nil
    }
    var plannedHours: Double? {
        isValid ? Double(workDays) * hoursPerDay : nil
    }
    // After fuel; covers the planned rent, the known Pass budget and personal goal.
    // Unknown Pass cost must not silently become a zero-cost estimate.
    var plannedHourlyRequirement: Double? {
        guard isValid, let passBudget, let goal = weeklyPersonalGoal,
              let hours = plannedHours else { return nil }
        return (rental + passBudget + goal) / hours
    }
}

struct RadarWeeklyOverview {
    let plan: RadarWeeklyPlan
    let ledger: RadarWeeklyLedger?
    // Only a confirmed ledger supplies earnings and completed trips.
    var confirmedReceived: Double? { ledger?.received }
    var registeredTrips: Int? { ledger?.weeklyTrips.count }
    var estimatedRentalRemaining: Double? { ledger?.rentalRemaining }
    var digitalCredits: Double? { ledger?.rentalCredits }
    var cashAndOwnTerminal: Double? {
        ledger?.weeklyTrips.filter { !$0.method.reducesRental }.reduce(0) { $0 + $1.received }
    }
    var registeredFuel: Double? {
        ledger?.weeklyTrips.reduce(0) { $0 + $1.fuel }
    }
}
