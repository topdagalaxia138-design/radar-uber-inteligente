import XCTest
@testable import RadarCore

// Synthetic fixtures: layout and labels only, no user's financial records.
final class RadarFinanceParserTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-11-18T22:00:00Z")!

    func testWeeklyEarningsAndTripsRequireExplicitCurrentWeek() {
        let text = "Uber Driver\nGanhos\nEsta semana\nGanhos líquidos\nR$ 1.234,56\nViagens\n17"
        let reading = RadarFinanceParser.parse(text, now: now)
        XCTAssertEqual(reading?.values[.weeklyEarnings], 1234.56)
        XCTAssertEqual(reading?.values[.weeklyTrips], 17)
        XCTAssertEqual(reading?.weekKey, "2026-11-16")
        XCTAssertNil(RadarFinanceParser.parse(text.replacingOccurrences(of: "Esta semana", with: "Hoje"), now: now))
    }
    func testPastWeekDoesNotBecomeCurrentIncome() {
        let text = "Uber\nGanhos\nSemana passada\nTotal de ganhos\nR$ 600,00\nViagens\n10"
        XCTAssertNil(RadarFinanceParser.parse(text, now: now))
    }
    func testCurrentDateRangeIsSupported() {
        let reading = RadarFinanceParser.parse("Uber\nGanhos\n16 de nov. - 22 de nov.\nTotal de ganhos\nR$ 600,00\nViagens\n10", now: now)
        XCTAssertEqual(reading?.values[.weeklyEarnings], 600)
    }
    func testConflictingDateRangeRejectsRelativeWeekLabel() {
        XCTAssertNil(RadarFinanceParser.parse("Uber\nGanhos\nEsta semana\n9 de nov. - 15 de nov.\nGanhos líquidos\nR$ 600,00", now: now))
    }
    func testWrongYearIsNotCurrentWeek() {
        XCTAssertNil(RadarFinanceParser.parse("Uber\nGanhos\n16 de nov. de 2025 - 22 de nov. de 2025\nGanhos líquidos\nR$ 600,00", now: now))
    }
    func testWalletBalanceCanBeNegativeWithoutBeingRental() {
        let reading = RadarFinanceParser.parse("Uber\nCarteira\nSaldo\n-R$ 512,34", now: now)
        XCTAssertEqual(reading?.values[.walletBalance], -512.34)
        XCTAssertNil(reading?.values[.rentalPending])
        XCTAssertNil(reading?.values[.weeklyEarnings])
    }
    func testCompactSaldoHeaderDoesNotSelectTripRowValue() {
        let reading = RadarFinanceParser.parse("Saldo • -R$512,34\nUberX\nR$18,00\n12:10", now: now)
        XCTAssertEqual(reading?.values[.walletBalance], -512.34)
        XCTAssertEqual(reading?.movements.count, 0) // no visible day
    }
    func testSaldoPageWithLiquidationMessage() {
        let reading = RadarFinanceParser.parse("Saldo\n-R$512,34\nUsaremos os ganhos das suas próximas viagens\npara liquidar esse saldo\nPagar\nResumo\n18 de nov.\nUberX\nR$18,00\n12:10", now: now)
        XCTAssertEqual(reading?.values[.walletBalance], -512.34)
        XCTAssertEqual(reading?.movements.count, 1)
    }
    func testOtherBankWalletWithoutUberMarkerIsNotImported() {
        XCTAssertNil(RadarFinanceParser.parse("Carteira\nSaldo\n-R$512,34\nTransferir", now: now))
    }
    func testAmbiguousBalancesAreNotChosenArbitrarily() {
        XCTAssertNil(RadarFinanceParser.parse("Uber\nCarteira\nSaldo\nR$10,00\nSaldo\nR$20,00", now: now))
    }
    func testRadarScreenAndNotificationDoNotReadTheirOwnFigures() {
        for text in [
            "Radar\nUber\nGanhos\nEsta semana\nTotal de ganhos\nR$100,00",
            "Minha semana\nUber\nGanhos\nEsta semana\nTotal de ganhos\nR$100,00",
            "RADAR • PEGAR\nUber\nCarteira\nSaldo\nR$100,00"
        ] {
            XCTAssertFalse(RadarFinanceParser.mightContainFinancialScreen(text))
            XCTAssertNil(RadarFinanceParser.parse(text, now: now))
        }
    }
    func testOfferIsNotFinancialSource() {
        XCTAssertFalse(RadarFinanceParser.mightContainFinancialScreen("UberX\nR$29,00\nGanhos\nAceitar"))
    }
    func testNegativeEarningsAndFractionalTripsAreRejected() {
        let reading = RadarFinanceParser.parse("Uber\nGanhos\nEsta semana\nGanhos líquidos\n-R$10,00\nViagens\n1,5", now: now)
        XCTAssertNil(reading)
    }
    func testBothAccurateReadsMustAgree() {
        let first = RadarFinanceParser.parse("Uber\nCarteira\nSaldo\nR$10,00", now: now)
        let second = RadarFinanceParser.parse("Uber\nCarteira\nSaldo\nR$11,00", now: now)
        XCTAssertNil(RadarFinanceState.confirmedReading(first, second))
        XCTAssertNil(RadarFinanceState.confirmedReading(first, nil))
        XCTAssertNotNil(RadarFinanceState.confirmedReading(first, first))
    }
    func testRepeatedScreenReplacesInsteadOfSummingIncome() {
        let reading = RadarFinanceParser.parse("Uber\nGanhos\nEsta semana\nTotal de ganhos\nR$100,00\nViagens\n5", now: now)!
        var state = RadarFinanceState()
        for second in 0..<50 { state.observe(reading, at: now.addingTimeInterval(Double(second))) }
        XCTAssertEqual(state.observations.count, 2)
        XCTAssertEqual(state.latest(.weeklyEarnings, now: now)?.value, 100)
        XCTAssertEqual(state.latest(.weeklyTrips, now: now)?.value, 5)
    }
    func testWeeklyCountDoesNotCarryOverToNextWeek() {
        var state = RadarFinanceState()
        state.observe(RadarFinanceParser.parse("Uber\nGanhos\nEsta semana\nViagens\n5", now: now)!, at: now)
        XCTAssertNil(state.latest(.weeklyTrips, now: now.addingTimeInterval(7 * 86400)))
    }
    func testStorePersistsOnlyStructuredValues() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = RadarFinanceStore(url: url)
        let reading = RadarFinanceParser.parse("Uber\nCarteira\nSaldo\n-R$12,00\nPrivate passenger address", now: now)!
        XCTAssertTrue(store.observe(reading, at: now))
        XCTAssertEqual(store.load().latest(.walletBalance, now: now)?.value, -12)
        let saved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(saved.contains("Private"))
    }
    func testWalletMovementsDoNotBecomeReceivedCashOrTripCount() {
        let text = "Saldo • -R$512,34\n18 de nov.\nUberX\n-R$5,50\n12:10 – Viagem com pagamento\nem dinheiro"
        let reading = RadarFinanceParser.parse(text, now: now)!
        XCTAssertEqual(reading.movements.first?.kind, .cashTripBalance)
        XCTAssertEqual(reading.movements.first?.amount, -5.50)
        XCTAssertNil(reading.values[.cashReceived])
        XCTAssertNil(reading.values[.weeklyTrips])
    }
    func testRentalDebitAndCreditRemainDistinct() {
        let text = "Saldo • -R$512,34\n18 de nov.\nTaxa relativa a veículos -\nR$24,00\nRetencao Localiza\n14:20\nTaxa relativa a veículos -\n-R$875,00\nRetencao Localiza\n13:20\nUberX\nR$10,00\n12:10"
        let reading = RadarFinanceParser.parse(text, now: now)!
        XCTAssertEqual(reading.movements.filter { $0.kind == .rentalDebit }.first?.amount, -875)
        XCTAssertEqual(reading.movements.filter { $0.kind == .rentalCredit }.first?.amount, 24)
        XCTAssertNil(reading.values[.rentalPending])
    }
    func testPassChargeAndAdjustmentAreNotBothExpenses() {
        let text = "Saldo • -R$512,34\n18 de nov.\nUberX\nR$10,00\n15:10\nPasse para Motoristas – Ajuste de\nganhos para que sua taxa\nsemanal seja 0%\nR$9,00\n14:20\nCobrança por assinatura do\nmotorista parceiro - Pagamento\ndo Passe para Motoristas\n-R$35,00\n13:20"
        let reading = RadarFinanceParser.parse(text, now: now)!
        XCTAssertEqual(reading.movements.filter { $0.kind == .passDebit }.count, 1)
        XCTAssertEqual(reading.movements.filter { $0.kind == .passAdjustment }.first?.amount, 9)
        XCTAssertNil(reading.values[.passPrice])
    }
    func testScrollingDoesNotDuplicateKnownMovement() {
        let reading = RadarFinanceParser.parse("Saldo • -R$512,34\n18 de nov.\nUberX\nR$10,00\n15:10", now: now)!
        var state = RadarFinanceState()
        for _ in 0..<30 { state.observe(reading, at: now) }
        XCTAssertEqual(state.movements?.count, 1)
        XCTAssertNil(state.latest(.weeklyEarnings, now: now))
        XCTAssertNil(state.latest(.weeklyTrips, now: now))
    }
    func testPartialRowWithoutDateIsNotAssignedToToday() {
        let reading = RadarFinanceParser.parse("Saldo • -R$512,34\nUberX\nR$10,00\n15:10\n17 de nov.\nUberX\nR$11,00\n14:10", now: now)!
        XCTAssertEqual(reading.movements.count, 1)
        XCTAssertEqual(reading.movements.first?.amount, 11)
    }
    func testLegacyFinancialStateWithoutMovementsStillDecodes() throws {
        let state = try JSONDecoder().decode(RadarFinanceState.self, from: Data(#"{"observations":[]}"#.utf8))
        XCTAssertNil(state.movements)
    }
}
