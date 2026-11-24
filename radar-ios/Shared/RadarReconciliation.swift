import Foundation

struct RadarWalletCheckpoint: Codable, Equatable, Identifiable {
    let observedAt: Date
    let balance: Double
    var id: Date { observedAt }
}

struct RadarWalletReconciliation {
    let opening: RadarWalletCheckpoint?
    let closing: RadarWalletCheckpoint?
    let movementTotal: Double
    let movementCount: Int
    let pendingReceipts: Int
    var change: Double? {
        guard let opening, let closing else { return nil }
        return closing.balance - opening.balance
    }
    var unexplained: Double? { change.map { $0 - movementTotal } }
    var message: String {
        guard let difference = unexplained else { return "Aguardando dois saldos observados em momentos diferentes" }
        return abs(difference) < 0.005
            ? "Lançamentos capturados conferem com a variação; não comprova que o extrato está completo"
            : "Há diferença não explicada pelos lançamentos capturados; não é classificada como dinheiro ou aluguel"
    }
    init(finance: RadarFinanceState, payments: RadarPaymentState, now: Date) {
        let checkpoints = (finance.walletCheckpoints ?? []).filter { $0.observedAt <= now }
            .sorted { $0.observedAt < $1.observedAt }
        closing = checkpoints.last
        opening = checkpoints.dropLast().last
        let start = opening?.observedAt ?? now
        let end = closing?.observedAt ?? now
        let movements = (finance.movements ?? []).filter { $0.occurredAt > start && $0.occurredAt <= end }
        movementCount = movements.count
        movementTotal = movements.reduce(0) { $0 + $1.amount }
        pendingReceipts = payments.receipts.filter { $0.status == .pending && $0.cancelledAt == nil }.count
    }
}
