import Foundation

// Local completions complement a dated official observation; they never rewrite it.
// Uber may lag: this is explicitly a provisional count until another official read.
struct RadarTripProgress {
    let official: Int?
    let additionalCaptured: Int
    let visibleUnscoped: Int?
    var total: Int? { official.map { $0 + additionalCaptured } }
    var remaining: Int? { total.map { max(0, 80 - $0) } }
    var label: String {
        if let total { return "\(total)/80" + (additionalCaptured > 0 ? " • provisório" : " • Uber") }
        if let visibleUnscoped { return "\(visibleUnscoped) viagens na tela • período a confirmar" }
        return additionalCaptured == 0 ? "Contagem semanal ainda não lida" : "\(additionalCaptured) conclusões acompanhadas • base semanal não lida"
    }
    init(finance: RadarFinanceState, payments: RadarPaymentState, now: Date) {
        let reading = finance.latest(.weeklyTrips, now: now)
        official = reading.map { Int($0.value) }
        let candidate = finance.latest(.visibleTrips, now: now)
        visibleUnscoped = candidate.flatMap { item in
            item.weekKey == RadarFinanceParser.weekKey(at: now) ? Int(item.value) : nil
        }
        let week = RadarFinanceParser.weekKey(at: now)
        additionalCaptured = payments.receipts.filter {
            guard let completed = $0.completedAt, $0.cancelledAt == nil,
                  RadarFinanceParser.weekKey(at: completed) == week else { return false }
            return completed <= now && (reading == nil || completed > reading!.observedAt)
        }.count
    }
}

