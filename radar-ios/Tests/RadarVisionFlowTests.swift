#if os(macOS)
import AppKit
import Vision
import XCTest
@testable import RadarCore

// Exercises native OCR with rendered screen fixtures on the build Mac.
// These fixtures validate the pipeline, not iPhone thermal or banner delivery.
final class RadarVisionFlowTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-11-24T15:00:00Z")!
    func recognize(_ rows: [(String, CGFloat, CGFloat)]) throws -> String {
        let image = NSImage(size: NSSize(width: 1000, height: 1000), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black]
            for (text, x, y) in rows { text.draw(at: NSPoint(x: x, y: y), withAttributes: attributes) }
            return true
        }
        let pixels = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["pt-BR", "en-US"]
        try VNImageRequestHandler(cgImage: pixels).perform([request])
        return RadarScreenText.render((request.results ?? []).compactMap { result in
            guard let text = result.topCandidates(1).first?.string else { return nil }
            return RadarTextRegion(text: text, x: Double(result.boundingBox.minX), y: Double(result.boundingBox.minY),
                                   width: Double(result.boundingBox.width), height: Double(result.boundingBox.height))
        })
    }
    func screen(_ lines: [String]) throws -> String {
        try recognize(lines.enumerated().map { ($0.element, CGFloat(40), CGFloat(900 - $0.offset * 65)) })
    }
    func testNativeOCRCashLifecyclePersistsOnlyConfirmedReceipt() throws {
        var state = RadarPaymentState()
        let screens = [["Iniciar Comfort"], ["Concluir Comfort"], ["Recolher pagamento", "Dinheiro", "Valor a receber: R$ 15,00"],
                       ["Pagamento recolhido"], ["Viagem concluída"]]
        for (index, lines) in screens.enumerated() {
            let text = try screen(lines)
            let evidence = try XCTUnwrap(RadarPaymentParser.parse(text), text)
            state.observe(evidence, at: now.addingTimeInterval(Double(index) * 10))
            if index < 4 { XCTAssertNil(state.receivedToday(.cash, now: now)) }
        }
        XCTAssertEqual(state.receivedToday(.cash, now: now), 15)
        XCTAssertEqual(state.receipts.count, 1)
    }
    func testNativeOCRTwoColumnStatisticsKeepsUncertainScope() throws {
        let text = try recognize([("Uber Conta", 40, 900), ("23 de nov. - 30 de nov.", 40, 830),
            ("Estatísticas", 40, 740), ("Online", 40, 660), ("Viagens", 520, 660),
            ("2 h 37 m", 40, 600), ("8", 520, 600), ("Pontos", 40, 500), ("13", 40, 440)])
        let reading = try XCTUnwrap(RadarFinanceParser.parse(text, now: now), text)
        XCTAssertEqual(reading.values[.visibleTrips], 8, text)
        XCTAssertNil(reading.values[.weeklyTrips], text)
    }
}
#endif
