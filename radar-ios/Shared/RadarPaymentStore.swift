import Foundation

enum RadarReceiptMethod: String, Codable { case cash, uberPix, uberApp }
enum RadarReceiptStatus: String, Codable { case pending, received, unpaid }

struct RadarPaymentEvidence: Equatable {
    var collection = false
    var collected = false
    var finished = false
    var unpaid = false
    var newTrip = false
    var completionConfirmed = false
    var cancelled = false
    var amount: Double?
    var method: RadarReceiptMethod?
}

enum RadarPaymentParser {
    static func parse(_ text: String) -> RadarPaymentEvidence? {
        let lines = text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .newlines).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            }.filter { !$0.isEmpty }
        // No payment inference from an offer, wallet, Radar screen or history.
        guard !lines.contains(where: { $0.contains("radar") || $0 == "saldo" || $0 == "carteira"
            || $0.hasPrefix("saldo •") || $0 == "tenho interesse" || $0 == "aceitar" }) else { return nil }
        var result = RadarPaymentEvidence()
        result.collection = lines.contains { $0 == "recolher pagamento" || $0 == "receber pagamento" }
        result.collected = lines.contains { $0 == "pagamento recolhido" || $0 == "pagamento recebido" || $0 == "pagamento confirmado" }
        result.finished = lines.contains { $0 == "viagem concluida" || $0 == "corrida concluida" || $0 == "procurando viagens" }
        result.unpaid = lines.contains { $0 == "passageiro nao pagou" || $0 == "nao recebi o pagamento"
            || $0 == "pagamento pendente" || $0 == "valor nao recebido" }
        result.completionConfirmed = lines.contains { $0 == "viagem concluida" || $0 == "corrida concluida" }
        result.cancelled = lines.contains { $0 == "viagem cancelada" || $0 == "corrida cancelada" }
        result.newTrip = lines.contains { $0 == "iniciar viagem" || $0 == "viagem em andamento" }
        guard result.collection || result.collected || result.finished || result.completionConfirmed || result.unpaid || result.newTrip || result.cancelled else { return nil }
        let cash = lines.contains { $0 == "dinheiro" || $0 == "forma de pagamento: dinheiro" || $0 == "pagamento em dinheiro" }
        let pix = lines.contains { $0 == "pix" || $0 == "forma de pagamento: pix" || $0 == "pix da uber" }
        let app = lines.contains { $0 == "pagamento pelo app" || $0 == "pagamento no app" }
        // Seeing both choice labels is not evidence of which button was tapped.
        if [cash, pix, app].filter({ $0 }).count == 1 {
            if cash { result.method = .cash }
            if app { result.method = .uberApp }
            if pix && lines.contains(where: { $0.contains("uber") }) { result.method = .uberPix }
        }
        var amounts: [Double] = []
        for (index, line) in lines.enumerated() {
            if let amount = RadarFinanceParser.currency(line) { amounts.append(amount) }
            for label in ["valor a receber", "valor recebido", "total a receber", "valor a recolher"] {
                if line == label, index + 1 < lines.count, let amount = RadarFinanceParser.currency(lines[index + 1]) {
                    // The next line is already counted by the currency pass.
                    if !amounts.contains(amount) { amounts.append(amount) }
                } else if line.hasPrefix(label + ":"),
                          let amount = RadarFinanceParser.currency(String(line.dropFirst(label.count + 1))) { amounts.append(amount) }
            }
        }
        let unique = Set(amounts)
        if unique.count == 1, let amount = unique.first, amount > 0 { result.amount = amount }
        return result
    }
}

struct RadarReceipt: Codable, Identifiable {
    var id: String
    var startedAt: Date
    var updatedAt: Date
    var method: RadarReceiptMethod?
    var amount: Double?
    var status: RadarReceiptStatus = .pending
    var confirmationSeen = false
    var completedAt: Date?
    var tripStartedAt: Date?
    var collectionStartedAt: Date?
    var cancelledAt: Date?
}

struct RadarPaymentState: Codable {
    var receipts: [RadarReceipt] = []
    var currentID: String?
    var nextTripSeen = false
    var message = "Aguardando uma sequência de pagamento legível"

    mutating func observe(_ evidence: RadarPaymentEvidence, at date: Date) {
        if evidence.newTrip {
            let current = receipts.first { $0.id == currentID }
            // A new in-progress screen opens a lifecycle, never books offered money.
            if current == nil || ((current?.completedAt != nil || current?.cancelledAt != nil)
                && date.timeIntervalSince(current!.updatedAt) >= 60) {
                var receipt = RadarReceipt(id: UUID().uuidString, startedAt: date, updatedAt: date)
                receipt.tripStartedAt = date
                receipts.append(receipt)
                currentID = receipt.id
                nextTripSeen = false
                message = "Viagem em acompanhamento; recebimento ainda não confirmado"
            }
            return
        }
        if evidence.collection, currentID == nil || nextTripSeen {
            receipts.append(RadarReceipt(id: UUID().uuidString, startedAt: date, updatedAt: date))
            currentID = receipts.last?.id
            nextTripSeen = false
        }
        guard let index = receipts.firstIndex(where: { $0.id == currentID }),
              date >= receipts[index].startedAt else { return }
        if evidence.cancelled {
            receipts[index].cancelledAt = date
            receipts[index].updatedAt = date
            message = "Cancelamento identificado; não contado como corrida concluída"
            return
        }
        guard receipts[index].cancelledAt == nil else { return }
        if evidence.completionConfirmed,
           date.timeIntervalSince(receipts[index].startedAt) < 2 * 60 * 60,
           receipts[index].completedAt == nil {
            receipts[index].completedAt = date
            receipts[index].updatedAt = date
        }
        if evidence.collection && receipts[index].collectionStartedAt == nil {
            receipts[index].collectionStartedAt = date
        }
        let paymentStart = receipts[index].collectionStartedAt ?? receipts[index].startedAt
        guard receipts[index].status == .pending,
              date.timeIntervalSince(paymentStart) < (receipts[index].tripStartedAt == nil ? 15 * 60 : 2 * 60 * 60) else { return }
        // Preserve ambiguity as pending rather than inventing money received.
        if let amount = evidence.amount {
            if let old = receipts[index].amount, abs(old - amount) > 0.005 {
                message = "Valor mudou durante o pagamento; recebimento pendente de confirmação"
                receipts[index].confirmationSeen = false
                return
            }
            receipts[index].amount = amount
        }
        if let method = evidence.method {
            if let old = receipts[index].method, old != method {
                receipts[index].method = nil
                receipts[index].confirmationSeen = false
                message = "Forma de pagamento mudou; aguardando nova confirmação"
                return
            }
            receipts[index].method = method
        }
        if evidence.unpaid {
            receipts[index].status = .unpaid
            receipts[index].updatedAt = date
            message = "Não pagamento identificado; não somado ao dinheiro recebido"
            return
        }
        if evidence.collected { receipts[index].confirmationSeen = true }
        // Collected may be an action button: require a later completion screen.
        if evidence.finished && !evidence.collection && !evidence.collected,
           receipts[index].confirmationSeen, receipts[index].amount != nil, receipts[index].method != nil {
            if receipts[index].completedAt == nil { receipts[index].completedAt = date }
            receipts[index].status = .received
            receipts[index].updatedAt = date
            message = "Recebimento registrado após confirmação e encerramento"
        } else {
            if evidence.collection || evidence.collected { receipts[index].updatedAt = date }
            message = "Pagamento observado; aguardando valor, forma e encerramento confirmados"
        }
        if receipts.count > 500 { receipts.removeFirst(receipts.count - 500) }
    }

    func receivedToday(_ method: RadarReceiptMethod, now: Date) -> Double? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let items = receipts.filter { $0.status == .received && $0.method == method
            && calendar.isDate($0.updatedAt, inSameDayAs: now) }
        return items.isEmpty ? nil : items.reduce(0) { $0 + ($1.amount ?? 0) }
    }
}

final class RadarPaymentStore {
    private let url: URL
    private let lock = NSLock()
    init(url: URL) { self.url = url }
    func load() -> RadarPaymentState {
        lock.lock(); defer { lock.unlock() }
        return read()
    }
    @discardableResult func observe(_ evidence: RadarPaymentEvidence, at date: Date) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var state = read()
        state.observe(evidence, at: date)
        do {
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
            return true
        } catch { return false }
    }
    private func read() -> RadarPaymentState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(RadarPaymentState.self, from: data) else { return RadarPaymentState() }
        return state
    }
}


