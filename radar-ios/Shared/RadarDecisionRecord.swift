import Foundation

enum RadarNoticeState: String, Codable {
    case awaiting, scheduled, failed
}

struct RadarDecisionRecord: Codable, Identifiable {
    let id: String
    let offerKey: String
    let summary: String
    let title: String
    let detail: String
    let accepted: Bool
    let firstConfirmedAt: Date
    var lastSeenAt: Date
    var noticeState: RadarNoticeState = .awaiting
    var noticeMessage: String?
    var scheduledAt: Date?

    func isRecent(at date: Date) -> Bool {
        date >= firstConfirmedAt && date.timeIntervalSince(firstConfirmedAt) < 7
    }
}

extension RadarReadingSnapshot {
    mutating func beginDecision(_ record: RadarDecisionRecord) {
        decisionRecord = record
        decisionAccepted = record.accepted
        decisionTitle = record.title
        decisionDetail = record.detail
        decisionAt = record.firstConfirmedAt
        offerSummary = record.summary
        offerAt = record.firstConfirmedAt
        notificationStatus = "Preparando aviso desta oferta"
    }

    mutating func markNotice(recordID: String, error: String?, at date: Date) {
        // A late callback for offer A must not overwrite offer B's status.
        guard var record = decisionRecord, record.id == recordID else { return }
        record.noticeState = error == nil ? .scheduled : .failed
        record.noticeMessage = error ?? "Enviado ao iOS; apresentação na tela não confirmada"
        record.scheduledAt = error == nil ? date : nil
        decisionRecord = record
        notificationStatus = record.noticeMessage ?? ""
    }
}
