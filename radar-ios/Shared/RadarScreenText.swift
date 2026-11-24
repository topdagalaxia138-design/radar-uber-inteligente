import Foundation

// Spatial evidence is used only in memory; no image or coordinates are saved.
struct RadarTextRegion {
    let text: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

enum RadarScreenText {
    static func render(_ regions: [RadarTextRegion]) -> String {
        let valid = regions.filter { !$0.text.isEmpty && $0.x.isFinite && $0.y.isFinite }
        let sorted = valid.sorted {
            if $0.y == $1.y { return $0.x < $1.x }
            return $0.y > $1.y
        }
        let countLabels = ["viagens", "viagens concluidas", "corridas concluidas"]
        var suppressed = Set<Int>()
        var added: [String] = []
        for (index, region) in sorted.enumerated() {
            let label = region.text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            guard countLabels.contains(label) else { continue }
            let center = region.x + region.width / 2
            let candidates = sorted.enumerated().filter { candidate in
                let value = candidate.element
                return value.text.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil
                    && value.y < region.y && region.y - value.y <= 0.09
                    && abs(value.x + value.width / 2 - center) <= max(0.06, region.width / 2)
            }
            // Several numbers in the column stay ambiguous; never pick a chart day.
            if candidates.count == 1, let candidate = candidates.first {
                suppressed.insert(index); suppressed.insert(candidate.offset)
                added.append(region.text + ": " + candidate.element.text)
            }
        }
        return (sorted.enumerated().filter { !suppressed.contains($0.offset) }.map { $0.element.text } + added)
            .joined(separator: "\n")
    }
}
