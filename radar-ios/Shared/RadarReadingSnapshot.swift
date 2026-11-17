import Foundation

struct RadarReadingSnapshot: Codable {
    var phase = "stopped"
    var startedAt: Date?
    var lastFrameAt: Date?
    var processingStartedAt: Date?
    var lastProcessedAt: Date?
    var frames = 0
    var readStatus = "Nenhuma leitura realizada"
    var offerSummary = ""
    var offerAt: Date?
    var notificationStatus = "Nenhuma notificação agendada"
    var processingSeconds: Double = 0

    func activity(at now: Date) -> String {
        if phase == "failed" { return "Leitura interrompida com erro" }
        if phase == "paused" { return "Transmissão pausada" }
        if phase != "running" { return "Transmissão encerrada ou ainda não iniciada" }
        if let start = processingStartedAt,
           lastProcessedAt == nil || lastProcessedAt! < start,
           now.timeIntervalSince(start) > 5 {
            return "OCR sem resposta recente — reinicie Radar Leitura"
        }
        guard let frame = lastFrameAt else { return "Transmissão iniciada; aguardando a primeira imagem" }
        if now.timeIntervalSince(frame) > 5 {
            return "Sem imagens recentes — mude a tela para conferir a transmissão"
        }
        return "Recebendo imagens da tela"
    }
}

// Small atomic file avoids relying on cross-process AppStorage notifications.
// No screenshot, raw OCR text or address is written to this diagnostic file.
final class RadarReadingStore {
    private let url: URL
    private let lock = NSLock()
    init(url: URL) { self.url = url }

    func load() -> RadarReadingSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }
    @discardableResult
    func update(_ change: (inout RadarReadingSnapshot) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var snapshot = read() ?? RadarReadingSnapshot()
        change(&snapshot)
        do {
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            return true
        } catch { return false }
    }
    private func read() -> RadarReadingSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RadarReadingSnapshot.self, from: data)
    }
}
