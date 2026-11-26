import Foundation

enum RadarRuntimePolicy {
    static func frameInterval(thermalLevel: Int) -> Double {
        switch thermalLevel {
        case 1: return 1.2
        case 2: return 1.2
        case 3: return .infinity
        default: return 0.6
        }
    }
    static func shouldStopForHeat(thermalLevel: Int) -> Bool { thermalLevel >= 3 }

    static func needsAccurateRead(offer: Bool, payment: Bool, finance: Bool,
                                  secondsSinceFallback: Double, thermalLevel: Int = 0) -> Bool {
        offer || payment || finance || (thermalLevel < 3 && secondsSinceFallback >= 3)
    }
    static func canRetryFailedNotice(age: Double, secondsSinceFailure: Double, alreadyRetried: Bool) -> Bool {
        !alreadyRetried && age >= 0 && age < 6 && secondsSinceFailure >= 1
    }
}

struct RadarRuntimeEvent: Codable {
    let date: Date
    let stage: String
    let message: String
}

struct RadarRuntimeDiagnostics: Codable {
    var thermal = "Não informado"
    var skippedFrames = 0
    var fastReads = 0
    var accurateReads = 0
    var events: [RadarRuntimeEvent] = []
}

extension RadarReadingSnapshot {
    mutating func runtimeEvent(_ stage: String, _ message: String, at date: Date = Date()) {
        if runtime == nil { runtime = RadarRuntimeDiagnostics() }
        runtime?.events.append(.init(date: date, stage: stage, message: message))
        if let count = runtime?.events.count, count > 24 { runtime?.events.removeFirst(count - 24) }
    }
}
