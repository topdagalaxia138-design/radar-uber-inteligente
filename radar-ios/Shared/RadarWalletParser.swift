import Foundation

enum RadarWalletMovementKind: String, Codable {
    case tripBalance, cashTripBalance, rentalDebit, rentalCredit, passDebit, passCredit, passAdjustment

    var label: String {
        switch self {
        case .tripBalance: return "Lançamento de viagem"
        case .cashTripBalance: return "Lançamento de viagem em dinheiro"
        case .rentalDebit: return "Débito de retenção Localiza"
        case .rentalCredit: return "Crédito de retenção Localiza"
        case .passDebit: return "Cobrança do Passe"
        case .passCredit: return "Crédito do Passe"
        case .passAdjustment: return "Ajuste de ganhos do Passe"
        }
    }
}

struct RadarWalletMovement: Codable, Equatable, Identifiable {
    let occurredAt: Date
    let amount: Double
    let kind: RadarWalletMovementKind
    let product: String?
    var id: String {
        // A fuller view can add the cash marker to the same transaction.
        let family = kind == .cashTripBalance ? RadarWalletMovementKind.tripBalance.rawValue : kind.rawValue
        return "\(occurredAt.timeIntervalSince1970)|\(amount)|\(family)|\(product ?? "")"
    }
}

enum RadarWalletParser {
    static func parse(_ lines: [String], now: Date) -> [RadarWalletMovement] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        var day: Date?
        var results: [RadarWalletMovement] = []
        var index = 0
        while index < lines.count {
            if let date = dateHeader(lines[index], now: now, calendar: calendar) {
                day = date; index += 1; continue
            }
            guard isStart(lines[index]) else { index += 1; continue }
            var end = index + 1
            while end < lines.count && !isStart(lines[end])
                && dateHeader(lines[end], now: now, calendar: calendar) == nil { end += 1 }
            let block = Array(lines[index..<end])
            if let day, let movement = movement(block, day: day, calendar: calendar) {
                results.append(movement)
            }
            index = end
        }
        return results
    }

    private static func isStart(_ line: String) -> Bool {
        line == "uberx" || line.hasPrefix("uberx ")
        || line == "comfort" || line.hasPrefix("comfort ") || line == "uber comfort" || line.hasPrefix("uber comfort ")
        || line == "priority" || line.hasPrefix("priority ")
        || line == "wait & save" || line.hasPrefix("wait & save ")
        || line.hasPrefix("taxa relativa a veiculos")
        || line.hasPrefix("cobranca por assinatura")
        || line.hasPrefix("passe para motoristas")
    }

    private static func dateHeader(_ line: String, now: Date, calendar: Calendar) -> Date? {
        let pattern = #"^(\d{1,2})\s+de\s+(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)\.?(?:\s+de\s+(\d{4}))?$"#
        let expression = try! NSRegularExpression(pattern: pattern)
        let source = line as NSString
        guard let match = expression.firstMatch(in: line, range: NSRange(location: 0, length: source.length)),
              let day = Int(source.substring(with: match.range(at: 1))) else { return nil }
        let months = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]
        guard let monthIndex = months.firstIndex(of: source.substring(with: match.range(at: 2))) else { return nil }
        let year = match.range(at: 3).location == NSNotFound
            ? calendar.component(.year, from: now)
            : Int(source.substring(with: match.range(at: 3))) ?? 0
        guard let date = calendar.date(from: DateComponents(year: year, month: monthIndex + 1, day: day)),
              calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == monthIndex + 1,
              date <= now else { return nil }
        return date
    }

    private static func movement(_ block: [String], day: Date, calendar: Calendar) -> RadarWalletMovement? {
        let joined = block.joined(separator: " ")
        let amountPattern = #"-?\s*r\$\s*-?\s*(?:\d{1,3}(?:\.\d{3})+,\d{2}|\d+[,\.]\d{2})"#
        let amountExpression = try! NSRegularExpression(pattern: amountPattern)
        let amounts = block.flatMap { line -> [Double] in
            let source = line as NSString
            return amountExpression.matches(in: line, range: NSRange(location: 0, length: source.length))
                .compactMap { RadarFinanceParser.currency(source.substring(with: $0.range).trimmingCharacters(in: .whitespaces)) }
        }
        guard amounts.count == 1, let amount = amounts.first else { return nil }
        let timeExpression = try! NSRegularExpression(pattern: #"^(\d{1,2}):(\d{2})(?:\s*[–-].*)?$"#)
        let times = block.compactMap { line -> (Int, Int)? in
            let source = line as NSString
            guard let match = timeExpression.firstMatch(in: line, range: NSRange(location: 0, length: source.length)),
                  let hour = Int(source.substring(with: match.range(at: 1))),
                  let minute = Int(source.substring(with: match.range(at: 2))),
                  hour < 24, minute < 60 else { return nil }
            return (hour, minute)
        }
        guard times.count == 1, let time = times.first,
              let date = calendar.date(bySettingHour: time.0, minute: time.1, second: 0, of: day) else { return nil }
        let kind: RadarWalletMovementKind
        let product: String?
        if joined.contains("taxa relativa a veiculos") && joined.contains("retencao localiza") {
            kind = amount < 0 ? .rentalDebit : .rentalCredit
            product = nil
        } else if joined.contains("cobranca por assinatura") && joined.contains("pagamento do passe para motoristas") {
            kind = amount < 0 ? .passDebit : .passCredit
            product = nil
        } else if joined.contains("passe para motoristas") && joined.contains("ajuste de ganhos") {
            kind = .passAdjustment; product = nil
        } else if let first = block.first, first.hasPrefix("uberx") || first.hasPrefix("priority") || first.hasPrefix("wait & save") || first.hasPrefix("comfort") || first.hasPrefix("uber comfort") {
            kind = joined.contains("viagem com pagamento em dinheiro") ? .cashTripBalance : .tripBalance
            product = first.hasPrefix("uberx") ? "UberX" : first.hasPrefix("priority") ? "Priority" : first.contains("comfort") ? "Comfort" : "Wait & Save"
        } else { return nil }
        return RadarWalletMovement(occurredAt: date, amount: amount, kind: kind, product: product)
    }
}

