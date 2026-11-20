import XCTest
@testable import RadarCore

final class RadarPaymentTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func evidence(_ text: String) -> RadarPaymentEvidence { RadarPaymentParser.parse(text)! }
    func testChoicesDoNotProveSelection() {
        let item = evidence("Uber\nRecolher pagamento\nR$ 15,00\nDinheiro\nPix")
        XCTAssertNil(item.method)
        XCTAssertEqual(item.amount, 15)
    }
    func testCashNeedsCollectionConfirmationAndCompletion() {
        var state = RadarPaymentState()
        state.observe(evidence("Recolher pagamento\nDinheiro\nR$ 15,00"), at: now)
        XCTAssertNil(state.receivedToday(.cash, now: now))
        state.observe(evidence("Pagamento recolhido"), at: now.addingTimeInterval(1))
        XCTAssertNil(state.receivedToday(.cash, now: now))
        state.observe(evidence("Viagem concluída"), at: now.addingTimeInterval(2))
        XCTAssertEqual(state.receivedToday(.cash, now: now), 15)
    }
    func testRepeatedFramesAndRestartNeverDuplicateReceipt() throws {
        var state = RadarPaymentState()
        state.observe(evidence("Recolher pagamento\nDinheiro\nR$ 15,00"), at: now)
        state.observe(evidence("Pagamento recolhido"), at: now)
        state.observe(evidence("Procurando viagens"), at: now)
        state = try JSONDecoder().decode(RadarPaymentState.self, from: JSONEncoder().encode(state))
        for _ in 0..<30 {
            state.observe(evidence("Recolher pagamento\nDinheiro\nR$ 15,00"), at: now)
            state.observe(evidence("Pagamento recolhido"), at: now)
            state.observe(evidence("Procurando viagens"), at: now)
        }
        XCTAssertEqual(state.receipts.count, 1)
        XCTAssertEqual(state.receivedToday(.cash, now: now), 15)
    }
    func testNonPaymentNeverCountsAsCash() {
        var state = RadarPaymentState()
        state.observe(evidence("Recolher pagamento\nDinheiro\nR$ 15,00"), at: now)
        state.observe(evidence("Passageiro não pagou"), at: now)
        state.observe(evidence("Pagamento recolhido"), at: now)
        state.observe(evidence("Viagem concluída"), at: now)
        XCTAssertNil(state.receivedToday(.cash, now: now))
        XCTAssertEqual(state.receipts.first?.status, .unpaid)
    }
    func testPixUberIsSeparateFromCash() {
        var state = RadarPaymentState()
        state.observe(evidence("Uber\nRecolher pagamento\nPix\nR$ 15,00"), at: now)
        state.observe(evidence("Pagamento confirmado"), at: now)
        state.observe(evidence("Viagem concluída"), at: now)
        XCTAssertEqual(state.receivedToday(.uberPix, now: now), 15)
        XCTAssertNil(state.receivedToday(.cash, now: now))
    }
    func testMissingMethodOrAmountRemainsPending() {
        var state = RadarPaymentState()
        state.observe(evidence("Recolher pagamento\nDinheiro\nPix\nR$ 15,00\nR$ 2,00"), at: now)
        state.observe(evidence("Pagamento recolhido"), at: now)
        state.observe(evidence("Viagem concluída"), at: now)
        XCTAssertNil(state.receivedToday(.cash, now: now))
        XCTAssertEqual(state.receipts.first?.status, .pending)
    }
    func testNewRideBoundaryAllowsEqualFareAgain() {
        var state = RadarPaymentState()
        let collect = evidence("Recolher pagamento\nDinheiro\nR$ 15,00")
        state.observe(collect, at: now)
        state.observe(evidence("Pagamento recolhido"), at: now)
        state.observe(evidence("Viagem concluída"), at: now)
        let later = now.addingTimeInterval(120)
        state.observe(evidence("Viagem em andamento"), at: later)
        state.observe(collect, at: later)
        state.observe(evidence("Pagamento recolhido"), at: later)
        state.observe(evidence("Viagem concluída"), at: later)
        XCTAssertEqual(state.receivedToday(.cash, now: later), 30)
    }
    func testConfirmationWithoutCollectionCannotCreateMoney() {
        var state = RadarPaymentState()
        state.observe(evidence("Pagamento recolhido\nDinheiro\nR$ 15,00"), at: now)
        state.observe(evidence("Viagem concluída"), at: now)
        XCTAssertTrue(state.receipts.isEmpty)
    }
    func testOfferAndWalletCannotBecomeReceipts() {
        XCTAssertNil(RadarPaymentParser.parse("RADAR\nPagamento recolhido\nR$15,00"))
        XCTAssertNil(RadarPaymentParser.parse("Saldo\nUberX\nPagamento recebido\nR$15,00"))
        XCTAssertNil(RadarPaymentParser.parse("UberX\nR$15,00\nAceitar"))
    }
    func testExpiredFlowAndPreviousDayCannotCount() {
        var state = RadarPaymentState()
        state.observe(evidence("Recolher pagamento\nDinheiro\nR$ 15,00"), at: now)
        state.observe(evidence("Pagamento recolhido"), at: now.addingTimeInterval(901))
        state.observe(evidence("Viagem concluída"), at: now.addingTimeInterval(902))
        XCTAssertNil(state.receivedToday(.cash, now: now))
    }
}
