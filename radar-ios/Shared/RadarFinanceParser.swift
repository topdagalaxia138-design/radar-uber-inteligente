import Foundation

enum RadarFinanceMetric: String, Codable, CaseIterable {
    case visibleTrips, weeklyEarnings, weeklyTrips, walletBalance, rentalPending, rentalRetained, cashReceived, digitalEarnings, passPrice

    var label: String {
        switch self {
        case .visibleTrips: return "Viagens lidas — período a confirmar"
        case .weeklyEarnings: return "Ganhos da semana exibidos"
        case .weeklyTrips: return "Viagens da semana exibidas"
        case .walletBalance: return "Saldo da Uber exibido"
        case .rentalPending: return "Aluguel pendente exibido"
        case .rentalRetained: return "Retenção do aluguel exibida"
        case .cashReceived: return "Dinheiro recebido exibido"
        case .digitalEarnings: return "Ganhos digitais exibidos"
        case .passPrice: return "Preço do Passe exibido"
        }
    }
    var isWeekly: Bool {
        [.visibleTrips, .weeklyEarnings, .weeklyTrips, .rentalRetained, .cashReceived, .digitalEarnings].contains(self)
    }
}

struct RadarFinanceReading: Equatable {
    let screen: String
    let values: [RadarFinanceMetric: Double]
    let weekKey: String?
    var movements: [RadarWalletMovement] = []
}

enum RadarFinanceParser {
    static func weekKey(at date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start)
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "−", with: "-")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")) }
            .filter { !$0.isEmpty }
    }

    static func mightContainFinancialScreen(_ text: String) -> Bool {
        let lines = normalizedLines(text)
        // Never read the Radar's own dashboard, a notification, or an offer as finances.
        if lines.contains(where: {
            $0.contains("radar") || $0 == "minha semana" || $0.contains("planejamento")
            || $0 == "aceitar" || $0 == "tenho interesse"
        }) { return false }
        let headings = ["ganhos", "resumo dos ganhos", "detalhes dos ganhos", "carteira",
                        "saldo", "aluguel", "retencao de aluguel", "passe", "passe uber", "detalhamento", "estatisticas"]
        return lines.contains(where: { headings.contains($0) || $0.hasPrefix("saldo •") || $0.hasPrefix("saldo ·") })
    }

    static func parse(_ text: String, now: Date) -> RadarFinanceReading? {
        guard mightContainFinancialScreen(text) else { return nil }
        let lines = normalizedLines(text)
        // ReplayKit supplies pixels, not the foreground app's identity.
        // Require a visible Uber marker before persisting financial values.
        let hasUberMarker = lines.contains(where: { $0.range(of: #"\buber(?:x| driver| pro)?\b"#, options: .regularExpression) != nil })
        let comfortWallet = lines.contains(where: { $0.hasPrefix("saldo •") || $0.hasPrefix("saldo ·") })
            && RadarWalletParser.parse(lines, now: now).contains(where: { $0.product == "Comfort" })
        guard hasUberMarker || comfortWallet else { return nil }
        let isWallet = lines.contains("carteira")
            || lines.contains(where: { $0 == "saldo" || $0.hasPrefix("saldo •") || $0.hasPrefix("saldo ·") })
        let isRental = lines.contains("aluguel") || lines.contains("retencao de aluguel")
        let isPass = lines.contains("passe") || lines.contains("passe uber")
        let earningsPage = lines.contains("ganhos") || lines.contains("resumo dos ganhos") || lines.contains("detalhes dos ganhos")
            || lines.contains("detalhamento") || lines.contains("estatisticas")
        let currentWeek = showsCurrentWeek(lines, now: now)
        var values: [RadarFinanceMetric: Double] = [:]

        // A selected chart day keeps the weekly date header. Statistics alone
        // cannot establish that the amount and trip count belong to the week.
        let explicitWeeklyScope = lines.contains("esta semana") || lines.contains("semana atual")
            || lines.contains("mais informacoes")
        let selectedDayAmbiguity = lines.contains("estatisticas") && !explicitWeeklyScope
        if earningsPage && currentWeek && selectedDayAmbiguity {
            values[.visibleTrips] = tripCount(in: lines)
        }
        if earningsPage && currentWeek && !selectedDayAmbiguity {
            values[.weeklyEarnings] = money(after: ["ganhos liquidos", "total de ganhos", "ganhos totais", "ganhos"], in: lines)
            values[.weeklyTrips] = tripCount(in: lines)
            if values[.weeklyEarnings] == nil, lines.contains("estatisticas"),
               values[.weeklyTrips] != nil {
                let datePattern = #"\d{1,2}\s+de\s+(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)"#
                if let index = lines.firstIndex(where: { $0.range(of: datePattern, options: .regularExpression) != nil
                    && ($0.contains("-") || $0.contains("–")) }),
                   index + 1 < lines.count {
                    values[.weeklyEarnings] = currency(lines[index + 1])
                }
            }
            // Overview is weekly; a selected day on the chart is not.
            if values[.weeklyEarnings] == nil, lines.contains("mais informacoes"),
               values[.weeklyTrips] != nil {
                for (index, line) in lines.enumerated() where line.range(of: #"\d{1,2}\s+de\s+"#, options: .regularExpression) != nil
                    && (line.contains("-") || line.contains("–")) {
                    let next = Array(lines.dropFirst(index + 1).prefix(3))
                    for candidate in next {
                        if let value = currency(candidate) { values[.weeklyEarnings] = value; break }
                    }
                    if values[.weeklyEarnings] != nil { break }
                }
            }
            values[.cashReceived] = money(after: ["dinheiro recebido", "recebido em dinheiro"], in: lines)
            values[.digitalEarnings] = money(after: ["ganhos em pagamentos digitais", "ganhos digitais"], in: lines)
            values[.rentalRetained] = money(after: ["valor retido para aluguel", "aluguel retido"], in: lines)
        }
        if isWallet {
            values[.walletBalance] = money(after: ["saldo atual", "saldo disponivel", "saldo pendente de", "saldo"], in: lines)
            let headerAmounts = lines.filter { $0.hasPrefix("saldo •") || $0.hasPrefix("saldo ·") }
                .compactMap { line -> Double? in
                    guard let separator = line.firstIndex(where: { $0 == "•" || $0 == "·" }) else { return nil }
                    return currency(String(line[line.index(after: separator)...]))
                }
            if headerAmounts.count == 1 && values[.walletBalance] == nil {
                values[.walletBalance] = headerAmounts[0]
            }
        }
        if isRental || isWallet {
            values[.rentalPending] = money(after: ["saldo devedor do aluguel", "aluguel pendente"], in: lines)
        }
        if isPass {
            // A displayed price is not proof of a purchase; do not book it as an expense.
            values[.passPrice] = money(after: ["preco do passe", "valor do passe"], in: lines)
        }

        // Negative values are valid for wallet balances, not for received income or counts.
        values = values.filter { $0.value.isFinite && ($0.key == .walletBalance || $0.key == .rentalPending || $0.key == .weeklyEarnings || $0.value >= 0) }
        let movements = isWallet ? RadarWalletParser.parse(lines, now: now) : []
        guard !values.isEmpty || !movements.isEmpty else { return nil }
        return RadarFinanceReading(screen: isWallet ? "Carteira" : isRental ? "Aluguel" : isPass ? "Passe" : "Ganhos",
            values: values, weekKey: currentWeek ? weekKey(at: now) : nil, movements: movements)
    }

    private static func showsCurrentWeek(_ lines: [String], now: Date) -> Bool {
        if lines.contains(where: { $0 == "semana passada" || $0 == "ultima semana" }) { return false }
        let relativeCurrentWeek = lines.contains("esta semana") || lines.contains("semana atual")
        var hasDateRange = false
        // Accept only the date range of this calendar week (Monday -> Sunday/Monday).
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        calendar.firstWeekday = 2
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let expression = try! NSRegularExpression(pattern: #"(\d{1,2})\s*(?:de\s+)?(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)\.?"#)
        let months = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]
        let candidates = lines + zip(lines, lines.dropFirst()).map { $0 + " " + $1 }
        for line in candidates where line.contains("-") || line.contains("–") || line.contains(" a ") {
            let source = line as NSString
            let matches = expression.matches(in: line, range: NSRange(location: 0, length: source.length))
            guard matches.count == 2 else { continue }
            hasDateRange = true
            let yearExpression = try! NSRegularExpression(pattern: #"\b20\d{2}\b"#)
            let years = yearExpression.matches(in: line, range: NSRange(location: 0, length: source.length))
            let currentYear = calendar.component(.year, from: now)
            if years.contains(where: { Int(source.substring(with: $0.range)) != currentYear }) { continue }
            let dates = matches.compactMap { match -> (Int, Int)? in
                guard let day = Int(source.substring(with: match.range(at: 1))),
                      let month = months.firstIndex(of: source.substring(with: match.range(at: 2))) else { return nil }
                return (day, month + 1)
            }
            guard dates.count == 2 else { continue }
            let first = calendar.dateComponents([.day, .month], from: monday)
            for delta in [6, 7] {
                let end = calendar.dateComponents([.day, .month], from: calendar.date(byAdding: .day, value: delta, to: monday)!)
                if dates[0].0 == first.day && dates[0].1 == first.month
                    && dates[1].0 == end.day && dates[1].1 == end.month { return true }
            }
        }
        return relativeCurrentWeek && !hasDateRange
    }

    private static func fieldTexts(after labels: [String], in lines: [String]) -> [String] {
        var results: [String] = []
        for (index, line) in lines.enumerated() {
            for label in labels {
                if line == label || line == label + ":" {
                    if index + 1 < lines.count { results.append(lines[index + 1]) }
                } else if line.hasPrefix(label + ":") || line.hasPrefix(label + " r$") || line.hasPrefix(label + " -r$") {
                    results.append(String(line.dropFirst(label.count)).trimmingCharacters(in: CharacterSet(charactersIn: ": ")))
                }
            }
        }
        return results
    }

    private static func money(after labels: [String], in lines: [String]) -> Double? {
        let values = fieldTexts(after: labels, in: lines).compactMap(currency)
        // Repeated or conflicting labels are not summed or selected arbitrarily.
        guard values.count == 1 else { return nil }
        return values.first
    }

    static func currency(_ text: String) -> Double? {
        let pattern = #"^\s*(-?)\s*r\$\s*(-?)\s*((?:\d{1,3}(?:\.\d{3})+,\d{2})|(?:\d+[,\.]\d{2}))\s*$"#
        let expression = try! NSRegularExpression(pattern: pattern)
        let source = text as NSString
        guard let match = expression.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) else { return nil }
        let firstSign = source.substring(with: match.range(at: 1))
        let secondSign = source.substring(with: match.range(at: 2))
        guard firstSign.isEmpty || secondSign.isEmpty else { return nil }
        var amount = source.substring(with: match.range(at: 3))
        if amount.contains(",") { amount = amount.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        guard let value = Double(amount), value.isFinite else { return nil }
        return firstSign == "-" || secondSign == "-" ? -value : value
    }

    private static func tripCount(in lines: [String]) -> Double? {
        var values: [Double] = []
        if let labeled = count(after: ["viagens", "viagens concluidas", "corridas concluidas"], in: lines) {
            values.append(labeled)
        }
        let expression = try! NSRegularExpression(pattern: #"^(\d{1,4})\s+viagens$"#)
        for line in lines {
            let source = line as NSString
            if let match = expression.firstMatch(in: line, range: NSRange(location: 0, length: source.length)),
               let value = Double(source.substring(with: match.range(at: 1))) { values.append(value) }
        }
        let unique = Set(values)
        return unique.count == 1 ? unique.first : nil
    }

    private static func count(after labels: [String], in lines: [String]) -> Double? {
        let values = fieldTexts(after: labels, in: lines).compactMap { text -> Double? in
            guard text.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil,
                  let value = Double(text) else { return nil }
            return value
        }
        return values.count == 1 ? values.first : nil
    }
}


