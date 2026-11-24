import XCTest
@testable import RadarCore

final class RadarReconciliationJourneyTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-11-24T15:00:00Z")!
    func testWalletReconcilesMovementsWithoutAddingCashOrDigitalTwice() {
        var finance = RadarFinanceState()
        func reading(_ value: Double) -> RadarFinanceReading { .init(screen: "Carteira", values: [.walletBalance: value], weekKey: nil) }
        finance.observe(reading(-100), at: now)
        for n in 1...5 { finance.observe(reading(-100), at: now.addingTimeInterval(Double(n))) }
        XCTAssertEqual(finance.walletCheckpoints?.count, 1)
        finance.observe(.init(screen: "Carteira", values: [.walletBalance: -70], weekKey: nil,
            movements: [.init(occurredAt: now.addingTimeInterval(60), amount: 40, kind: .tripBalance, product: "Comfort"),
                        .init(occurredAt: now.addingTimeInterval(120), amount: -10, kind: .passDebit, product: nil)]),
            at: now.addingTimeInterval(180))
        var payments = RadarPaymentState()
        var cash = RadarReceipt(id: "cash", startedAt: now, updatedAt: now)
        cash.status = .received; cash.method = .cash; cash.amount = 30
        var digital = cash; digital.id = "digital"; digital.method = .uberApp; digital.amount = 40
        payments.receipts = [cash, digital]
        let check = RadarWalletReconciliation(finance: finance, payments: payments, now: now.addingTimeInterval(200))
        XCTAssertEqual(check.change, 30)
        XCTAssertEqual(check.movementTotal, 30)
        XCTAssertEqual(check.unexplained, 0)
        XCTAssertTrue(check.message.contains("não comprova"))
    }
    func testUnknownDifferenceStaysUnexplainedAndLegacyStateDecodes() throws {
        var finance = try JSONDecoder().decode(RadarFinanceState.self, from: Data(#"{"observations":[]}"#.utf8))
        XCTAssertNil(finance.walletCheckpoints)
        XCTAssertNil(RadarWalletReconciliation(finance: finance, payments: .init(), now: now).unexplained)
        finance.walletCheckpoints = [.init(observedAt: now.addingTimeInterval(-60), balance: -100), .init(observedAt: now, balance: -20)]
        let check = RadarWalletReconciliation(finance: finance, payments: .init(), now: now)
        XCTAssertEqual(check.unexplained, 80)
        XCTAssertTrue(check.message.contains("não é classificada"))
    }
    func testJourneyDoesNotInventTimeAcrossMissingHeartbeats() throws {
        var state = RadarJourneyState()
        state.start(at: now)
        state.heartbeat(at: now.addingTimeInterval(10))
        state.heartbeat(at: now.addingTimeInterval(300))
        XCTAssertEqual(state.journeys.first?.trackedSeconds, 10)
        XCTAssertEqual(state.journeys.first?.interrupted, true)
        XCTAssertNil(state.active(at: now.addingTimeInterval(400)))
        state = try JSONDecoder().decode(RadarJourneyState.self, from: JSONEncoder().encode(state))
        state.start(at: now.addingTimeInterval(500))
        XCTAssertNotNil(state.journeys.first?.endedAt)
        XCTAssertEqual(state.journeys.count, 2)
    }
    func testDistanceKeepsFuelConfigurationAtEachSegmentAndRejectsJumps() {
        var distances = RadarDistanceState()
        distances.record(journeyID: "a", kilometers: 10, at: now, price: 5, consumption: 10, gap: false)
        distances.record(journeyID: "a", kilometers: 10, at: now, price: 6, consumption: 20, gap: true)
        let value = distances.readings.first!
        XCTAssertEqual(value.kilometers, 20)
        XCTAssertEqual(value.fuelLiters, 1.5)
        XCTAssertEqual(value.fuelCost, 8)
        XCTAssertTrue(value.hasGap)
        XCTAssertFalse(RadarDistancePolicy.accepts(meters: 5000, seconds: 1, accuracy: 5))
        XCTAssertFalse(RadarDistancePolicy.accepts(meters: 100, seconds: 120, accuracy: 5))
        XCTAssertFalse(RadarDistancePolicy.accepts(meters: 100, seconds: 10, accuracy: 80))
        XCTAssertTrue(RadarDistancePolicy.accepts(meters: 100, seconds: 10, accuracy: 5))
        distances.record(journeyID: "a", kilometers: 1, at: now, price: 0, consumption: 0, gap: false)
        XCTAssertEqual(distances.readings.first?.unpricedKilometers, 1)
    }
    func report(at date: Date, id: String, revenue: Double, pending: Bool = false) -> RadarJourneyReport {
        var journey = RadarJourney(startedAt: date, lastHeartbeat: date.addingTimeInterval(3600))
        journey.id = id; journey.endedAt = date.addingTimeInterval(3600); journey.trackedSeconds = 3600
        var payments = RadarPaymentState()
        for n in 1...2 {
            var receipt = RadarReceipt(id: "\(id)-\(n)", startedAt: date, updatedAt: date)
            receipt.completedAt = date.addingTimeInterval(Double(n) * 100)
            receipt.status = pending ? .pending : .received; receipt.method = .cash; receipt.amount = revenue / 2; receipt.driverEarnings = revenue / 2
            payments.receipts.append(receipt)
        }
        var distance = RadarDistanceReading(id: id)
        distance.firstAt = date; distance.lastAt = journey.endedAt; distance.fuelCost = 10
        return .init(journey: journey, payments: payments, distances: .init(readings: [distance]))
    }
    func testPlanningNeedsThreeIndependentDaysAndUsesMedianNotBestTrip() {
        let reports = [report(at: now.addingTimeInterval(-21 * 86400), id: "a", revenue: 40),
                       report(at: now.addingTimeInterval(-14 * 86400), id: "b", revenue: 50),
                       report(at: now.addingTimeInterval(-7 * 86400), id: "c", revenue: 500)]
        XCTAssertTrue(RadarHistoryPlanner.windows(reports: Array(reports.prefix(2)), now: now).isEmpty)
        let windows = RadarHistoryPlanner.windows(reports: reports, now: now)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.medianHourlyAfterFuel, 40)
        XCTAssertEqual(windows.first?.samples, 3)
        XCTAssertTrue(RadarHistoryPlanner.windows(reports: [reports[0], reports[0], reports[0]], now: now).isEmpty)
        XCTAssertFalse(report(at: now, id: "pending", revenue: 50, pending: true).eligibleForPlanning)
    }
    func testComfortLedgerAndCancellationDoNotCreateReceivedCash() {
        let reading = RadarFinanceParser.parse("Saldo • -R$100,00\n24 de nov.\nComfort\nR$20,00\n11:00", now: now)
        XCTAssertEqual(reading?.movements.first?.product, "Comfort")
        var payments = RadarPaymentState()
        payments.observe(RadarPaymentParser.parse("Viagem em andamento")!, at: now)
        payments.observe(RadarPaymentParser.parse("Corrida concluída")!, at: now.addingTimeInterval(30))
        XCTAssertNotNil(payments.receipts.first?.completedAt)
        XCTAssertNil(payments.receivedToday(.cash, now: now))
    }
}

