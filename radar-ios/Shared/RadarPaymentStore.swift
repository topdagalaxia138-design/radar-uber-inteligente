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
    var accepted = false
    var inProgress = false
    var paymentChoices = false
    var explicitPaid = false
    var driverEarnings: Double?
    var amountIsFinal = false
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
        result.accepted = lines.contains { ["iniciar viagem", "iniciar uberx", "iniciar comfort", "iniciar uber comfort", "encontre o passageiro", "a caminho do passageiro", "chegando ao passageiro", "aguarde o passageiro"].contains($0) }
        result.inProgress = lines.contains { ["viagem em andamento", "concluir viagem", "encerrar viagem", "concluir uberx", "concluir comfort", "concluir uber comfort", "encerrar uberx", "encerrar comfort"].contains($0) }
        result.newTrip = result.accepted || result.inProgress
        result.explicitPaid = lines.contains { ["pagamento aprovado", "pagamento realizado", "pagamento confirmado", "pago pelo aplicativo", "pagamento feito pelo app"].contains($0) }
        guard result.collection || result.collected || result.finished || result.completionConfirmed || result.unpaid || result.newTrip || result.cancelled || result.explicitPaid else { return nil }
        let cash = lines.contains { $0 == "dinheiro" || $0 == "forma de pagamento: dinheiro" || $0 == "pagamento em dinheiro" }
        let pix = lines.contains { $0 == "pix" || $0 == "forma de pagamento: pix" || $0 == "pix da uber" }
        let app = lines.contains { $0 == "pagamento pelo app" || $0 == "pagamento no app" || $0 == "pago pelo aplicativo" || $0 == "pagamento feito pelo app" }
        result.paymentChoices = [cash, pix, app].filter({ $0 }).count > 1
        // Seeing both choice labels is not evidence of which button was tapped.
        if [cash, pix, app].filter({ $0 }).count == 1 {
            if cash { result.method = .cash }
            if app { result.method = .uberApp }
            if pix && lines.contains(where: { $0.contains("uber") }) { result.method = .uberPix }
        }
        func labeledMoney(_ labels: [String]) -> Double? {
            var values: [Double] = []
            for (index, line) in lines.enumerated() {
                for label in labels {
                    if line == label, index + 1 < lines.count, let value = RadarFinanceParser.currency(lines[index + 1]) { values.append(value) }
                    else if line.hasPrefix(label + ":"), let value = RadarFinanceParser.currency(String(line.dropFirst(label.count + 1))) { values.append(value) }
                }
            }
            let unique = Set(values)
            return unique.count == 1 ? unique.first : nil
        }
        result.driverEarnings = labeledMoney(["seus ganhos", "voce ganhou", "ganhos da viagem", "valor liquido da viagem"])
        let finalAmount = labeledMoney(["valor recebido", "total recebido", "valor pago"])
        let collectionAmount = labeledMoney(["valor a receber", "total a receber", "valor a recolher"])
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
        if let amount = finalAmount, amount > 0 { result.amount = amount; result.amountIsFinal = true }
        else if let amount = collectionAmount, amount > 0 { result.amount = amount }
        else if result.driverEarnings == nil, unique.count == 1, let amount = unique.first, amount > 0 { result.amount = amount }
        // An explicitly named earnings field can differ from cash collected.
        // Neither a fare offer nor an unlabeled second amount supplies this field.
        return result
    }
}

enum RadarTripPhase: String, Codable {
    case accepted, inProgress, collecting, completed, cancelled
    var label: String {
        switch self {
        case .accepted: return "Aceite observado • indo buscar"
        case .inProgress: return "Viagem iniciada"
        case .collecting: return "Cobrança em acompanhamento"
        case .completed: return "Conclusão observada"
        case .cancelled: return "Cancelamento observado"
        }
    }
}

struct RadarTripOfferSnapshot: Codable, Equatable {
    let observedAt: Date
    let fare: Double
    let minutes: Double
    let kilometers: Double
    init?(_ offer: RadarOffer, at date: Date) {
        guard let minutes = offer.totalMinutes, let kilometers = offer.totalKilometers else { return nil }
        self.observedAt = date; self.fare = offer.fare; self.minutes = minutes; self.kilometers = kilometers
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
    var acceptedAt: Date?
    var phase: RadarTripPhase?
    var offer: RadarTripOfferSnapshot?
    var driverEarnings: Double?
    var amountConflict: Bool?
    var missingEvidence: String?
}

struct RadarPaymentState: Codable {
    var receipts: [RadarReceipt] = []
    var currentID: String?
    var nextTripSeen = false
    var candidateOffer: RadarTripOfferSnapshot?
    var lastEvidenceStage: String?
    var message = "Aguardando uma sequência de pagamento legível"

    mutating func observeOffer(_ offer: RadarOffer, at date: Date) {
        candidateOffer = RadarTripOfferSnapshot(offer, at: date)
    }

    mutating func observe(_ evidence: RadarPaymentEvidence, at date: Date) {
        let stage = evidence.cancelled ? "cancelled" : evidence.inProgress ? "inProgress"
            : evidence.accepted ? "accepted" : evidence.collection ? "collection"
            : evidence.completionConfirmed ? "completed" : evidence.collected || evidence.explicitPaid ? "paid"
            : evidence.finished ? "idle" : evidence.unpaid ? "unpaid" : "other"
        defer { lastEvidenceStage = stage }
        var current = receipts.firstIndex { $0.id == currentID }
        let terminal = current.map { receipts[$0].completedAt != nil || receipts[$0].cancelledAt != nil } ?? false
        let nextAccepted = evidence.accepted && lastEvidenceStage != "accepted"
            && current.map { receipts[$0].phase == .inProgress || receipts[$0].phase == .collecting } == true
        let boundary = evidence.newTrip && (current == nil || terminal || nextAccepted)
            && !(lastEvidenceStage == stage && terminal)
        if boundary || (evidence.collection && current == nil) {
            if let i = current, !terminal { receipts[i].missingEvidence = "Fim da viagem anterior não observado; valores continuam pendentes" }
            var receipt = RadarReceipt(id: UUID().uuidString, startedAt: date, updatedAt: date)
            receipt.phase = evidence.inProgress ? .inProgress : evidence.accepted ? .accepted : .collecting
            if evidence.accepted { receipt.acceptedAt = date }
            if evidence.inProgress { receipt.tripStartedAt = date }
            if let candidateOffer, date.timeIntervalSince(candidateOffer.observedAt) >= 0,
               date.timeIntervalSince(candidateOffer.observedAt) <= 90 { receipt.offer = candidateOffer }
            candidateOffer = nil
            receipts.append(receipt); currentID = receipt.id; current = receipts.count - 1
            nextTripSeen = false
        }
        guard let index = current, date >= receipts[index].startedAt else { return }
        let age = date.timeIntervalSince(receipts[index].startedAt)
        guard age < 4 * 60 * 60 else {
            receipts[index].missingEvidence = "Sequência expirada; aguardando uma nova viagem identificada"
            message = receipts[index].missingEvidence!; return
        }
        if receipts[index].status == .received { return }
        if evidence.cancelled {
            receipts[index].cancelledAt = date; receipts[index].phase = .cancelled
            receipts[index].updatedAt = date
            message = "Cancelamento observado; não contado como corrida concluída"
            return
        }
        guard receipts[index].cancelledAt == nil else { return }
        if evidence.inProgress && receipts[index].completedAt == nil {
            receipts[index].phase = .inProgress
            receipts[index].tripStartedAt = receipts[index].tripStartedAt ?? date
        }
        if evidence.collection && receipts[index].completedAt == nil {
            receipts[index].phase = .collecting
            receipts[index].collectionStartedAt = receipts[index].collectionStartedAt ?? date
        }
        // Repeated final screens never rewrite the amount or confirmation timestamp.
        if receipts[index].status == .received { return }
        if evidence.paymentChoices {
            receipts[index].method = nil
            receipts[index].confirmationSeen = false
        }
        if let method = evidence.method {
            if let old = receipts[index].method, old != method { receipts[index].confirmationSeen = false }
            receipts[index].method = method
        }
        if let amount = evidence.amount {
            if let old = receipts[index].amount, abs(old - amount) > 0.005 && !evidence.amountIsFinal {
                receipts[index].amount = nil; receipts[index].amountConflict = true
                receipts[index].confirmationSeen = false
                receipts[index].missingEvidence = "Valores conflitantes; aguardando valor final explícito"
            } else if receipts[index].amountConflict != true || evidence.amountIsFinal {
                receipts[index].amount = amount
                if evidence.amountIsFinal { receipts[index].amountConflict = false }
            }
        }
        if let earnings = evidence.driverEarnings, earnings.isFinite, earnings >= 0 {
            receipts[index].driverEarnings = earnings
        }
        if evidence.unpaid {
            receipts[index].status = .unpaid
            receipts[index].confirmationSeen = false
            receipts[index].missingEvidence = "Passageiro não pagou; não somado aos recebimentos"
        }
        let paymentStart = receipts[index].collectionStartedAt ?? receipts[index].startedAt
        let paymentFresh = date.timeIntervalSince(paymentStart) < (receipts[index].collectionStartedAt == nil && receipts[index].tripStartedAt != nil ? 4 * 3600 : 900)
        if (evidence.collected || evidence.explicitPaid) && paymentFresh,
           receipts[index].status != .unpaid, receipts[index].amountConflict != true {
            receipts[index].confirmationSeen = true
        }
        let closesAfterPayment = evidence.finished && !evidence.collection
            && receipts[index].confirmationSeen
        if evidence.completionConfirmed || closesAfterPayment {
            receipts[index].completedAt = receipts[index].completedAt ?? date
            receipts[index].phase = .completed
        }
        if evidence.finished && !evidence.collection,
           receipts[index].confirmationSeen, receipts[index].status != .unpaid,
           receipts[index].amount != nil, receipts[index].method != nil,
           receipts[index].amountConflict != true, paymentFresh {
            receipts[index].status = .received
            receipts[index].missingEvidence = nil
            message = "Recebimento confirmado e vinculado à corrida encerrada"
        } else {
            if receipts[index].status == .pending && receipts[index].missingEvidence == nil {
                receipts[index].missingEvidence = "Aguardando valor, forma, confirmação ou encerramento"
            }
            message = receipts[index].missingEvidence ?? "Viagem em acompanhamento"
        }
        receipts[index].updatedAt = date
        if receipts.count > 2000 { receipts.removeFirst(receipts.count - 2000) }
    }

    func receivedToday(_ method: RadarReceiptMethod, now: Date) -> Double? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let items = receipts.filter { $0.status == .received && $0.method == method
            && calendar.isDate($0.completedAt ?? $0.updatedAt, inSameDayAs: now) }
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
    @discardableResult func observeOffer(_ offer: RadarOffer, at date: Date) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var state = read(); state.observeOffer(offer, at: date)
        do { try JSONEncoder().encode(state).write(to: url, options: .atomic); return true }
        catch { return false }
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



