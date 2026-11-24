import XCTest
@testable import RadarCore

final class RadarEndToEndTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-11-24T15:00:00Z")!
    func event(_ text: String) -> RadarPaymentEvidence { RadarPaymentParser.parse(text)! }
    func run(_ screens: [String], state: inout RadarPaymentState, offset: Double = 0) {
        for (index, screen) in screens.enumerated() { state.observe(event(screen), at: now.addingTimeInterval(offset + Double(index) * 10)) }
    }
    func testOfferIsOnlyReferenceUntilARealTripBoundary() {
        var state = RadarPaymentState()
        let offer = RadarOffer(fare: 20, pickupMinutes: 2, tripMinutes: 8, pickupKilometers: 1, tripKilometers: 3, rawText: "Comfort")
        state.observeOffer(offer, at: now)
        XCTAssertTrue(state.receipts.isEmpty)
        state.observe(event("INICIAR COMFORT"), at: now.addingTimeInterval(1))
        XCTAssertEqual(state.receipts.first?.phase, .accepted)
        XCTAssertNil(state.receipts.first?.tripStartedAt)
        XCTAssertEqual(state.receipts.first?.offer?.fare, 20)
        XCTAssertNil(state.receipts.first?.amount)
        XCTAssertNil(state.receivedToday(.cash, now: now))
    }
    func testAcceptedStartedCashConfirmedCompletedAndRestart() throws {
        var state = RadarPaymentState()
        run(["Iniciar UberX", "Concluir UberX", "Recolher pagamento\nDinheiro\nValor a receber: R$ 18,00", "Pagamento recolhido", "Viagem concluída"], state: &state)
        state = try JSONDecoder().decode(RadarPaymentState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(state.receipts.count, 1)
        XCTAssertEqual(state.receipts.first?.phase, .completed)
        XCTAssertNotNil(state.receipts.first?.acceptedAt)
        XCTAssertNotNil(state.receipts.first?.tripStartedAt)
        XCTAssertNotNil(state.receipts.first?.collectionStartedAt)
        XCTAssertEqual(state.receivedToday(.cash, now: now), 18)
        for _ in 0..<20 { state.observe(event("Viagem concluída"), at: now.addingTimeInterval(50)) }
        XCTAssertEqual(state.receivedToday(.cash, now: now), 18)
    }
    func testAppCardNeedsExplicitPaymentAndNeverCountsAsCash() {
        var state = RadarPaymentState()
        run(["Iniciar Comfort", "Concluir Comfort", "Viagem concluída\nPago pelo aplicativo\nValor pago: R$ 22,00\nSeus ganhos: R$ 19,00"], state: &state)
        XCTAssertEqual(state.receivedToday(.uberApp, now: now), 22)
        XCTAssertNil(state.receivedToday(.cash, now: now))
        XCTAssertEqual(state.receipts.first?.driverEarnings, 19)
    }
    func testUberQRThenCashChoicesNeverProvePayment() {
        var state = RadarPaymentState()
        run(["Iniciar UberX", "Concluir UberX", "Uber\nRecolher pagamento\nPix\nDinheiro\nR$ 16,00", "Pagamento recolhido", "Viagem concluída"], state: &state)
        XCTAssertNil(state.receivedToday(.cash, now: now))
        XCTAssertNil(state.receivedToday(.uberPix, now: now))
        XCTAssertEqual(state.receipts.first?.status, .pending)
    }
    func testCashAndPixSameFareAreDifferentTrips() {
        var state = RadarPaymentState()
        run(["Iniciar UberX", "Concluir UberX", "Recolher pagamento\nDinheiro\nR$ 15,00", "Pagamento recolhido", "Viagem concluída"], state: &state)
        run(["Iniciar Comfort", "Concluir Comfort", "Uber\nRecolher pagamento\nPix\nR$ 15,00", "Pagamento confirmado", "Viagem concluída"], state: &state, offset: 50)
        XCTAssertEqual(state.receipts.count, 2)
        XCTAssertEqual(state.receivedToday(.cash, now: now), 15)
        XCTAssertEqual(state.receivedToday(.uberPix, now: now), 15)
    }
    func testChangedAmountRequiresExplicitFinalValueAndRecovers() {
        var state = RadarPaymentState()
        run(["Iniciar UberX", "Concluir UberX", "Recolher pagamento\nDinheiro\nR$ 18,00", "Recolher pagamento\nDinheiro\nR$ 19,00", "Pagamento recolhido", "Viagem concluída"], state: &state)
        XCTAssertNil(state.receivedToday(.cash, now: now))
        state.observe(event("Viagem concluída\nPagamento recebido\nDinheiro\nValor recebido: R$ 19,00"), at: now.addingTimeInterval(60))
        XCTAssertEqual(state.receivedToday(.cash, now: now), 19)
        XCTAssertEqual(state.receipts.first?.amountConflict, false)
    }
    func testEarningsAloneCannotBecomeGrossCashCollection() {
        let item = event("Recolher pagamento\nDinheiro\nSeus ganhos: R$ 20,00")
        XCTAssertNil(item.amount)
        XCTAssertEqual(item.driverEarnings, 20)
    }
    func testUnpaidCompletedCountsTripButNotReceived() {
        var state = RadarPaymentState()
        run(["Iniciar UberX", "Concluir UberX", "Recolher pagamento\nDinheiro\nR$ 15,00", "Passageiro não pagou", "Viagem concluída"], state: &state)
        XCTAssertNotNil(state.receipts.first?.completedAt)
        XCTAssertEqual(state.receipts.first?.status, .unpaid)
        XCTAssertNil(state.receivedToday(.cash, now: now))
    }
    func testLostCompletionAndCancellationNeverInventMoney() {
        var state = RadarPaymentState()
        run(["Iniciar UberX", "Concluir UberX", "Iniciar Comfort", "Viagem cancelada"], state: &state)
        XCTAssertEqual(state.receipts.count, 2)
        XCTAssertNotNil(state.receipts[0].missingEvidence)
        XCTAssertNil(state.receipts[0].completedAt)
        XCTAssertNil(state.receipts[1].completedAt)
        XCTAssertNotNil(state.receipts[1].cancelledAt)
        XCTAssertNil(state.receivedToday(.cash, now: now))
    }
    func testCaptureMayStartMidTripButNotFromConfirmationAlone() {
        var state = RadarPaymentState()
        run(["Concluir Comfort", "Recolher pagamento\nDinheiro\nR$ 12,00", "Pagamento recolhido", "Viagem concluída"], state: &state)
        XCTAssertEqual(state.receivedToday(.cash, now: now), 12)
        XCTAssertNil(state.receipts.first?.acceptedAt)
        XCTAssertNotNil(state.receipts.first?.tripStartedAt)
        var empty = RadarPaymentState()
        run(["Pagamento recolhido\nDinheiro\nR$ 12,00", "Viagem concluída"], state: &empty)
        XCTAssertTrue(empty.receipts.isEmpty)
    }
    func testExpiredTripRecoversAtNextStartWithoutCreatingPastIncome() {
        var state = RadarPaymentState()
        state.observe(event("Iniciar UberX"), at: now)
        state.observe(event("Iniciar Comfort"), at: now.addingTimeInterval(4 * 3600 + 1))
        XCTAssertEqual(state.receipts.count, 2)
        XCTAssertNil(state.receipts[0].completedAt)
        XCTAssertNotNil(state.receipts[0].missingEvidence)
        XCTAssertEqual(state.receipts[1].phase, .accepted)
    }
    func testLateCancellationCannotRewriteAnAlreadyCompletedTrip() {
        var state = RadarPaymentState()
        run(["Iniciar UberX", "Concluir UberX", "Viagem concluída", "Viagem cancelada"], state: &state)
        XCTAssertNotNil(state.receipts[0].completedAt)
        XCTAssertNil(state.receipts[0].cancelledAt)
    }
    func testOldReceiptAndOldStateStillDecode() throws {
        let old = #"{"receipts":[{"id":"old","startedAt":0,"updatedAt":0,"status":"pending","confirmationSeen":false}],"currentID":"old","nextTripSeen":false,"message":"old"}"#
        let state = try JSONDecoder().decode(RadarPaymentState.self, from: Data(old.utf8))
        XCTAssertEqual(state.receipts.count, 1)
        XCTAssertNil(state.receipts.first?.phase)
    }
    func testSpatialColumnCountDoesNotReadHoursOrPoints() {
        let regions: [RadarTextRegion] = [
            .init(text: "Online", x: 0.04, y: 0.5, width: 0.15, height: 0.02),
            .init(text: "Viagens", x: 0.52, y: 0.5, width: 0.15, height: 0.02),
            .init(text: "2 h 37 m", x: 0.04, y: 0.46, width: 0.16, height: 0.02),
            .init(text: "8", x: 0.52, y: 0.46, width: 0.03, height: 0.02),
            .init(text: "13", x: 0.04, y: 0.3, width: 0.05, height: 0.02)]
        let text = RadarScreenText.render(regions)
        XCTAssertTrue(text.contains("Viagens: 8"))
        let reading = RadarFinanceParser.parse("Uber Conta\n23 de nov. - 30 de nov.\nEstatísticas\n" + text, now: now)
        XCTAssertEqual(reading?.values[.visibleTrips], 8)
        XCTAssertNil(reading?.values[.weeklyTrips])
    }
    func testUnscopedCountIsVisibleButNotUsedAsWeeklyOfficial() {
        var finance = RadarFinanceState()
        finance.observe(.init(screen: "Estatísticas", values: [.visibleTrips: 8], weekKey: RadarFinanceParser.weekKey(at: now)), at: now)
        let progress = RadarTripProgress(finance: finance, payments: .init(), now: now)
        XCTAssertNil(progress.total)
        XCTAssertTrue(progress.label.contains("8 viagens na tela"))
        let nextWeek = RadarTripProgress(finance: finance, payments: .init(), now: now.addingTimeInterval(7 * 86400))
        XCTAssertNil(nextWeek.visibleUnscoped)
        XCTAssertTrue(nextWeek.label.contains("ainda não lida"))
    }
    func testSpatialAmbiguityRemainsUnresolved() {
        let text = RadarScreenText.render([
            .init(text: "Viagens", x: 0.5, y: 0.5, width: 0.15, height: 0.02),
            .init(text: "8", x: 0.5, y: 0.47, width: 0.03, height: 0.02),
            .init(text: "9", x: 0.5, y: 0.44, width: 0.03, height: 0.02)])
        XCTAssertFalse(text.contains("Viagens:"))
    }
    func testCloseoutDistinguishesCashGrossFromIncomeAndDoesNotDoubleRent() {
        var payments = RadarPaymentState()
        run(["Iniciar UberX", "Concluir UberX", "Recolher pagamento\nDinheiro\nR$ 20,00", "Pagamento recolhido", "Viagem concluída"], state: &payments)
        var journey = RadarJourney(startedAt: now, lastHeartbeat: now.addingTimeInterval(120))
        journey.endedAt = now.addingTimeInterval(120); journey.trackedSeconds = 120
        var distance = RadarDistanceReading(id: journey.id)
        distance.firstAt = now; distance.lastAt = journey.endedAt; distance.fuelCost = 3
        var finance = RadarFinanceState()
        finance.movements = [.init(occurredAt: now.addingTimeInterval(10), amount: -4, kind: .cashTripBalance, product: "UberX"),
            .init(occurredAt: now.addingTimeInterval(60), amount: -42, kind: .passDebit, product: nil),
            .init(occurredAt: now.addingTimeInterval(-3600), amount: -832.22, kind: .rentalDebit, product: nil)]
        let report = RadarJourneyReport(journey: journey, payments: payments, distances: .init(readings: [distance]))
        let closeout = RadarShiftCloseout(report: report, payments: payments, finance: finance)
        XCTAssertEqual(closeout.cash, 20)
        XCTAssertNil(closeout.digital)
        XCTAssertEqual(closeout.earnings, 16)
        XCTAssertEqual(closeout.marginAfterFuel, 13)
        XCTAssertEqual(closeout.capturedExpense, 42)
        XCTAssertEqual(closeout.resultAfterCapturedExpenses, -29)
        XCTAssertNil(report.afterFuel) // raw cash is not a history earnings sample
    }
    func testAmbiguousWalletLinksDoNotGuessTripEarnings() {
        var payments = RadarPaymentState()
        for id in ["a", "b"] {
            var receipt = RadarReceipt(id: id, startedAt: now, updatedAt: now)
            receipt.completedAt = now.addingTimeInterval(60); receipt.tripStartedAt = now
            receipt.status = .received; receipt.amount = 20; receipt.method = .uberApp
            payments.receipts.append(receipt)
        }
        var finance = RadarFinanceState()
        finance.movements = [.init(occurredAt: now, amount: 16, kind: .tripBalance, product: "Comfort")]
        XCTAssertTrue(RadarTripReconciler.settlements(payments: payments, finance: finance).allSatisfy { $0.movement == nil && $0.driverEarnings == nil })
    }
    func testNightDistanceUsesEachSavedPriceRatherThanCurrentPrice() {
        var distance = RadarDistanceState()
        distance.record(journeyID: "night", kilometers: 10, at: now, price: 4.5, consumption: 10, gap: false)
        distance.record(journeyID: "night", kilometers: 13.7, at: now.addingTimeInterval(3600), price: 5.88, consumption: 13.7, gap: false)
        XCTAssertEqual(distance.readings[0].fuelCost, 10.38, accuracy: 0.001)
        XCTAssertEqual(distance.readings[0].fuelLiters, 2, accuracy: 0.001)
    }
}
