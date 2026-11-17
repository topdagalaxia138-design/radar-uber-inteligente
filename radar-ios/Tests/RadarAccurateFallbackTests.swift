import XCTest
@testable import RadarCore

final class RadarAccurateFallbackTests: XCTestCase {
    let priority = """
    Priority
    R$ 29,78
    Est. de R$2,05/km
    +R$ 4,01 incluída para retirada prioritária
    6 min • 3.1 km
    Rua de teste
    16 minutos • 11.4 km
    Avenida de teste
    Aceitar
    """
    func testFastFailureStillReachesBothAccurateReads() throws {
        let fast = priority.replacingOccurrences(of: "incluída para retirada prioritária", with: "")
        if case .incomplete = RadarOfferParser.parse(fast) {} else { XCTFail() }
        var calls = 0
        let result = try RadarOfferReader.read(initialText: fast, accurateFull: {
            calls += 1; return priority
        }, accurateCard: { calls += 1; return priority })
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(result.offer?.fare, 29.78)
    }
    func testFastCanMissAllMeasurementsWhenActionIsVisible() throws {
        let result = try RadarOfferReader.read(initialText: "Priority\nAceitar", accurateFull: { priority }, accurateCard: { priority })
        XCTAssertEqual(result.offer?.totalMinutes, 22)
    }
    func testUnrelatedScreenDoesNotRunAccurateOCR() throws {
        let result = try RadarOfferReader.read(initialText: "Radar Uber Inteligente\nR$ 87.43 • 52 min • 51.6 km\nCategoria: Priority; valores monetários: 29.78", accurateFull: {
            XCTFail("Must not OCR this again"); return ""
        }, accurateCard: { XCTFail(); return "" })
        XCTAssertFalse(result.attempted)
        XCTAssertNil(result.offer)
    }
    func testIncompleteAccurateReadNeverFallsBackToFastApproval() throws {
        let result = try RadarOfferReader.read(initialText: priority, accurateFull: {
            "Priority\nR$ 29,78\nAceitar"
        }, accurateCard: { XCTFail(); return "" })
        XCTAssertTrue(result.attempted)
        XCTAssertNil(result.offer)
        XCTAssertTrue(result.reason.contains("Leitura precisa da tela"))
    }
    func testDisagreementNeverGeneratesApprovedOffer() throws {
        let changed = priority.replacingOccurrences(of: "29,78", with: "29,73")
        let result = try RadarOfferReader.read(initialText: priority, accurateFull: { priority }, accurateCard: { changed })
        XCTAssertNil(result.offer)
        XCTAssertTrue(result.reason.contains("discordaram"))
    }
    func testNumericDiagnosticDoesNotExposeAddresses() {
        let diagnostic = RadarOfferReader.summary(priority)
        XCTAssertFalse(diagnostic.contains("Rua"))
        XCTAssertFalse(diagnostic.contains("Avenida"))
        XCTAssertTrue(diagnostic.contains("29.78"))
        XCTAssertTrue(diagnostic.contains("4.01"))
    }
    func testSpaceInUberXProductNameIsSupported() {
        let text = "Uber X\nR$ 87,43\n18 min • 15.6 km\n34 min • 36 km\nTenho interesse"
        guard case .complete(let offer) = RadarOfferParser.parse(text) else { return XCTFail() }
        XCTAssertEqual(offer.fare, 87.43)
    }
    func testVersionFourDiagnosticsRemainReadable() throws {
        let state = RadarReadingSnapshot()
        var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        for key in ["attemptAt", "attemptStatus", "fullReadSummary", "cardReadSummary"] { data.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(RadarReadingSnapshot.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertNil(decoded.attemptStatus)
        XCTAssertEqual(decoded.phase, "stopped")
    }
}
