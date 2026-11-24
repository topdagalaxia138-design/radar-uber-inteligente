import XCTest
@testable import RadarCore

final class RadarProductFlowTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-11-24T15:00:00Z")!
    func testThreeBandsAndZeroMarginNeverTurnsYellow() {
        let settings = RadarDecisionSettings(fuelCostPerKilometer: 0, targetNetPerHour: 40, preferredMinimumFare: 25)
        func decide(_ fare: Double) -> RadarDecision {
            RadarDecisionEngine.evaluate(RadarOffer(fare: fare, pickupMinutes: 2, tripMinutes: 8,
                pickupKilometers: 1, tripKilometers: 2, rawText: ""), settings: settings)
        }
        guard case .accept = decide(7) else { return XCTFail() }
        guard case .caution = decide(6.4) else { return XCTFail() }
        guard case .reject = decide(5.9) else { return XCTFail() }
        XCTAssertEqual(RadarDecisionNotice(decide(6.4), destination: nil)?.title, "🟡 RADAR • ATENÇÃO")
        let expensive = RadarDecisionSettings(fuelCostPerKilometer: 10, targetNetPerHour: 40, preferredMinimumFare: 25)
        guard case .reject = RadarDecisionEngine.evaluate(RadarOffer(fare: 5, pickupMinutes: 2, tripMinutes: 8,
            pickupKilometers: 1, tripKilometers: 2, rawText: ""), settings: expensive) else { return XCTFail() }
    }
    func testCompletionIsSeparateFromMoneyAndCancellingDoesNotCount() throws {
        var payments = RadarPaymentState()
        func event(_ text: String) -> RadarPaymentEvidence { RadarPaymentParser.parse(text)! }
        payments.observe(event("Viagem em andamento"), at: now)
        payments.observe(event("Viagem concluída"), at: now.addingTimeInterval(300))
        for _ in 0..<10 { payments.observe(event("Viagem concluída"), at: now.addingTimeInterval(301)) }
        XCTAssertEqual(payments.receipts.filter { $0.completedAt != nil }.count, 1)
        XCTAssertNil(payments.receivedToday(.cash, now: now))
        payments.observe(event("Viagem em andamento"), at: now.addingTimeInterval(600))
        payments.observe(event("Viagem cancelada"), at: now.addingTimeInterval(601))
        payments.observe(event("Viagem concluída"), at: now.addingTimeInterval(602))
        let restored = try JSONDecoder().decode(RadarPaymentState.self, from: JSONEncoder().encode(payments))
        XCTAssertEqual(restored.receipts.filter { $0.completedAt != nil && $0.cancelledAt == nil }.count, 1)
    }
    func testOfficialCountReplacesEarlierCaptureAndWeekRollsOver() {
        var finance = RadarFinanceState()
        finance.observe(RadarFinanceReading(screen: "Ganhos", values: [.weeklyTrips: 8],
            weekKey: RadarFinanceParser.weekKey(at: now)), at: now)
        var payments = RadarPaymentState()
        for minute in [1.0, 2.0] {
            var receipt = RadarReceipt(id: String(minute), startedAt: now, updatedAt: now)
            receipt.completedAt = now.addingTimeInterval(minute * 60)
            payments.receipts.append(receipt)
        }
        let later = now.addingTimeInterval(180)
        let progress = RadarTripProgress(finance: finance, payments: payments, now: later)
        XCTAssertEqual(progress.total, 10)
        XCTAssertEqual(progress.remaining, 70)
        finance.observe(RadarFinanceReading(screen: "Ganhos", values: [.weeklyTrips: 10],
            weekKey: RadarFinanceParser.weekKey(at: now)), at: later)
        XCTAssertEqual(RadarTripProgress(finance: finance, payments: payments, now: later).total, 10)
        XCTAssertNil(RadarTripProgress(finance: finance, payments: payments, now: now.addingTimeInterval(7 * 86400)).total)
    }
    func testLegacyVehiclePlanAndOwnedCostsDoNotChargeRental() throws {
        let legacy = try JSONDecoder().decode(RadarWeeklyPlan.self,
            from: Data(#"{"rental":800,"monthlyPersonalGoal":1000,"workDays":5,"hoursPerDay":6}"#.utf8))
        XCTAssertEqual(legacy.weeklyVehicleBudget, 800)
        var plan = RadarWeeklyPlan()
        plan.ownership = .owned
        XCTAssertNil(plan.weeklyVehicleBudget)
        plan.monthlyVehicleBudget = 520
        plan.passBudget = 0
        XCTAssertEqual(plan.weeklyVehicleBudget, 120)
        XCTAssertEqual(plan.plannedHourlyRequirement!, (120 + 1000.0 * 12 / 52) / 42, accuracy: 0.001)
    }
    func testPaymentProductLabelIsNotMistakenForAnOffer() {
        let evidence = RadarPaymentParser.parse("UberX\nRecolher pagamento\nDinheiro\nR$ 18,00")
        XCTAssertEqual(evidence?.method, .cash)
        XCTAssertEqual(evidence?.amount, 18)
        XCTAssertNil(RadarPaymentParser.parse("UberX\nR$ 18,00\nAceitar"))
    }
    func testSelectedChartDayCannotOverwriteWeeklyTripCount() {
        let text = "Uber Conta\n16 de nov. - 23 de nov.\nR$ 200,00\nEstatísticas\nViagens\n12\nGanhos totais\nR$ 200,00"
        let date = ISO8601DateFormatter().date(from: "2026-11-19T15:00:00Z")!
        let reading = RadarFinanceParser.parse(text, now: date)
        XCTAssertNil(reading?.values[.weeklyTrips])
        XCTAssertNil(reading?.values[.weeklyEarnings])
    }

}
