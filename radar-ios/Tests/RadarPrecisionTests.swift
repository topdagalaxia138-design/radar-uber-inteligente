import XCTest
@testable import RadarCore

final class RadarPrecisionTests: XCTestCase {
    // Real Priority layout transcribed with street/address details removed.
    let priority = """
    Priority
    Exclusivo
    R$ 29,78
    Est. de R$2,05/km
    ☆ +R$ 4,01 incluída para retirada prioritária
    6 min • 3.1 km
    Rua de teste, Içara
    4,20 (17)
    Verificado
    16 minutos • 11.4 km
    Avenida de teste, Criciúma
    Aceitar
    """

    func parsed(_ text: String) throws -> RadarOffer {
        guard case .complete(let offer) = RadarOfferParser.parse(text) else {
            XCTFail("Expected a complete offer")
            throw NSError(domain: "test", code: 1)
        }
        return offer
    }
    func testPriorityIncludedSupplementIsNeverAddedTwice() throws {
        let offer = try parsed(priority)
        XCTAssertEqual(offer.fare, 29.78)
        XCTAssertEqual(offer.totalMinutes, 22)
        XCTAssertEqual(offer.totalKilometers!, 14.5, accuracy: 0.001)
        let settings = RadarDecisionSettings(fuelCostPerKilometer: 0.28, targetNetPerHour: 40, preferredMinimumFare: 25)
        guard case .accept(_, let net, let perHour) = RadarDecisionEngine.evaluate(offer, settings: settings) else { return XCTFail() }
        XCTAssertEqual(net, 25.72, accuracy: 0.001)
        XCTAssertEqual(perHour, 70.14545, accuracy: 0.001)
    }
    func testPrioritySupplementSplitByOCR() throws {
        let changed = priority.replacingOccurrences(of: "+R$ 4,01 incluída", with: "+R$ 4,01\nincluída")
        XCTAssertEqual(try parsed(changed).fare, 29.78)
    }
    func testUnknownSecondPriceIsStillRejected() {
        let changed = priority.replacingOccurrences(of: "incluída para retirada prioritária", with: "valor adicional")
        if case .incomplete = RadarOfferParser.parse(changed) {} else { XCTFail() }
    }
    func testIncludedAmountLargerThanTotalIsRejected() {
        let changed = priority.replacingOccurrences(of: "+R$ 4,01", with: "+R$ 40,01")
        if case .incomplete = RadarOfferParser.parse(changed) {} else { XCTFail() }
    }
    func testTwoIncludedAmountsAreRejected() {
        if case .incomplete = RadarOfferParser.parse(priority + "\n+R$ 1,00 incluída para retirada prioritária") {} else { XCTFail() }
    }
    func testBothReadsMustAgreeOnEveryLeg() throws {
        let offer = try parsed(priority)
        let different = RadarOffer(fare: 29.78, pickupMinutes: 7, tripMinutes: 15,
            pickupKilometers: 3.1, tripKilometers: 11.4, rawText: "")
        XCTAssertFalse(offer.hasSameMeasurements(as: different))
        XCTAssertTrue(offer.hasSameMeasurements(as: try parsed(priority)))
    }
    func testDifferentFareNeverPassesConfirmation() throws {
        let a = try parsed(priority)
        let b = try parsed(priority.replacingOccurrences(of: "29,78", with: "29,73"))
        XCTAssertFalse(a.hasSameMeasurements(as: b))
    }
}

final class RadarReadingHealthTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testStoppedCannotLookActive() {
        var state = RadarReadingSnapshot()
        state.lastFrameAt = now
        XCTAssertTrue(state.activity(at: now).contains("encerrada"))
    }
    func testRunningWithoutFramesIsExplicit() {
        var state = RadarReadingSnapshot()
        state.phase = "running"
        XCTAssertTrue(state.activity(at: now).contains("primeira imagem"))
    }
    func testRecentFrameIsActive() {
        var state = RadarReadingSnapshot()
        state.phase = "running"
        state.lastFrameAt = now
        XCTAssertEqual(state.activity(at: now), "Recebendo imagens da tela")
    }
    func testStaleFrameDoesNotPretendToBeCurrent() {
        var state = RadarReadingSnapshot()
        state.phase = "running"
        state.lastFrameAt = now.addingTimeInterval(-20)
        XCTAssertTrue(state.activity(at: now).contains("Sem imagens recentes"))
    }
    func testUnfinishedOCRIsDetected() {
        var state = RadarReadingSnapshot()
        state.phase = "running"
        state.lastFrameAt = now
        state.processingStartedAt = now.addingTimeInterval(-10)
        XCTAssertTrue(state.activity(at: now).contains("OCR sem resposta"))
        state.lastProcessedAt = now
        XCTAssertEqual(state.activity(at: now), "Recebendo imagens da tela")
    }
    func testPauseIsNotReportedAsRunning() {
        var state = RadarReadingSnapshot()
        state.phase = "paused"
        state.lastFrameAt = now
        XCTAssertEqual(state.activity(at: now), "Transmissão pausada")
    }
    func testDiagnosticFileSurvivesReaderRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let writer = RadarReadingStore(url: url)
        XCTAssertTrue(writer.update { $0.phase = "running"; $0.frames = 5; $0.lastFrameAt = now })
        let reader = RadarReadingStore(url: url)
        XCTAssertEqual(reader.load()?.frames, 5)
        XCTAssertEqual(reader.load()?.lastFrameAt, now)
        XCTAssertTrue(writer.update { $0.frames += 1 })
        XCTAssertEqual(reader.load()?.frames, 6)
    }
}
