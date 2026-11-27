import XCTest
@testable import RadarCore

final class RadarWeeklyOverviewRegressionTests: XCTestCase {
    func testWrappedWeeklyOverview() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-26T22:18:00-03:00"))
        let reading = try XCTUnwrap(RadarFinanceParser.parse("""
        Ganhos
        Seus repasses de ganhos recentes do Passe para Motoristas de R$ 126,00
        23 de nov. - 30
        de nov.
        -R$ 324,42
        14 h 7 m online 33 viagens 42 pontos
        Mais informações
        Carteira
        Uber Conta
        Saldo pendente de -R$ 600,22
        """, now: now))
        XCTAssertEqual(reading.values[.weeklyTrips], 33)
        XCTAssertEqual(reading.values[.weeklyEarnings], -324.42)
        XCTAssertEqual(reading.values[.walletBalance], -600.22)
        XCTAssertNil(reading.values[.passPrice])
    }
}
