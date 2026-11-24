import Foundation

// A wallet entry is linked only when both sides have exactly one temporal match.
// No offer price, wallet residual or unmatched adjustment becomes cash received.
struct RadarTripSettlement {
    let receipt: RadarReceipt
    let movement: RadarWalletMovement?
    var driverEarnings: Double? {
        if let value = receipt.driverEarnings { return value }
        guard receipt.status == .received, let movement else { return nil }
        if receipt.method == .cash, movement.kind == .cashTripBalance, let cash = receipt.amount {
            return cash + movement.amount
        }
        if receipt.method != .cash, movement.kind == .tripBalance, movement.amount >= 0 {
            return movement.amount
        }
        return nil
    }
    var source: String {
        if receipt.driverEarnings != nil { return "Ganhos da viagem exibidos" }
        return movement == nil ? "Ganhos da viagem ainda não conferidos" : "Associação por horário com a carteira • estimativa a conferir"
    }
}

enum RadarTripReconciler {
    static func settlements(payments: RadarPaymentState, finance: RadarFinanceState) -> [RadarTripSettlement] {
        let receipts = payments.receipts.filter { $0.completedAt != nil && $0.cancelledAt == nil }
        let movements = (finance.movements ?? []).filter { $0.kind == .tripBalance || $0.kind == .cashTripBalance }
        func matches(_ receipt: RadarReceipt, _ movement: RadarWalletMovement) -> Bool {
            guard receipt.status == .received, let end = receipt.completedAt else { return false }
            if receipt.method == .cash && movement.kind != .cashTripBalance { return false }
            if receipt.method != .cash && movement.kind != .tripBalance { return false }
            let times = [receipt.tripStartedAt, Optional(end)].compactMap { $0 }
            return times.contains { abs(movement.occurredAt.timeIntervalSince($0)) <= 90 }
        }
        return receipts.map { receipt in
            let candidates = movements.filter { matches(receipt, $0) }
            let unique = candidates.count == 1 && receipts.filter { matches($0, candidates[0]) }.count == 1
            return RadarTripSettlement(receipt: receipt, movement: unique ? candidates[0] : nil)
        }
    }
}

struct RadarShiftCloseout {
    let report: RadarJourneyReport
    let settlements: [RadarTripSettlement]
    let expenses: [RadarWalletMovement]
    var cash: Double? { total(methods: [.cash]) }
    var digital: Double? { total(methods: [.uberPix, .uberApp]) }
    var earnings: Double? {
        guard !report.completed.isEmpty, report.pending == 0,
              settlements.count == report.completed.count,
              settlements.allSatisfy({ $0.driverEarnings != nil }) else { return nil }
        return settlements.reduce(0) { $0 + ($1.driverEarnings ?? 0) }
    }
    var capturedExpense: Double? { expenses.isEmpty ? nil : -expenses.reduce(0) { $0 + $1.amount } }
    var marginAfterFuel: Double? {
        guard let earnings, report.gpsComplete, let fuel = report.fuelCost else { return nil }
        return earnings - fuel
    }
    // Partial operating result, never called net profit: uncaptured expenses remain unknown.
    var resultAfterCapturedExpenses: Double? {
        guard let marginAfterFuel, let capturedExpense else { return nil }
        return marginAfterFuel - capturedExpense
    }
    var status: String {
        if report.journey.interrupted { return "Jornada parcial: houve interrupção de captura" }
        if report.journey.endedAt == nil { return "Jornada em andamento" }
        if report.pending > 0 { return "Encerrada com recebimentos pendentes" }
        if earnings == nil { return "Encerrada; faltam ganhos individuais para conferir o resultado" }
        if !report.gpsComplete { return "Encerrada; combustível com cobertura parcial" }
        return "Jornada encerrada • resultado dos dados acompanhados"
    }
    init(report: RadarJourneyReport, payments: RadarPaymentState, finance: RadarFinanceState) {
        self.report = report
        let ids = Set(report.completed.map { $0.id })
        settlements = RadarTripReconciler.settlements(payments: payments, finance: finance).filter { ids.contains($0.receipt.id) }
        let end = report.journey.endedAt ?? report.journey.lastHeartbeat
        expenses = (finance.movements ?? []).filter {
            $0.occurredAt >= report.journey.startedAt && $0.occurredAt < end
                && [.rentalDebit, .rentalCredit, .passDebit, .passCredit, .passAdjustment].contains($0.kind)
        }
    }
    private func total(methods: [RadarReceiptMethod]) -> Double? {
        let items = report.confirmed.filter { item in item.method.map { methods.contains($0) } == true }
        return items.isEmpty ? nil : items.reduce(0) { $0 + ($1.amount ?? 0) }
    }
}
