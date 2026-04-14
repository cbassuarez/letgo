import Foundation

enum PushDeckControlKind: String, Codable, CaseIterable {
    case padDown = "pad_down"
    case padUp = "pad_up"
    case macro
    case longStrip = "long_strip"
    case bankSelect = "bank_select"
    case mlParam = "ml_param"
}

enum PushDeckModeContext: String, Codable, CaseIterable, Identifiable {
    case auto
    case dynamic
    case `static`
    case choir

    var id: String { rawValue }
}

enum PushDeckTimingMode: String, Codable, CaseIterable, Identifiable {
    case immediate
    case quantized

    var id: String { rawValue }
}

enum PushDeckBankDomain: String, Codable, CaseIterable {
    case main
    case choir
}

enum PushDeckMLParamKey: String, Codable, CaseIterable {
    case phonePadEchoProbability = "phone_pad_echo_probability"
}

struct PushDeckPadControl: Codable, Equatable {
    var row: Int
    var column: Int
    var slot: Int
    var pressure: Double
    var velocity: Double
}

struct PushDeckMacroControl: Codable, Equatable {
    var lane: Int
    var value: Double
}

struct PushDeckLongStripControl: Codable, Equatable {
    var value: Double
}

struct PushDeckBankControl: Codable, Equatable {
    var domain: PushDeckBankDomain
    var bank: Int
}

struct PushDeckMLParamControl: Codable, Equatable {
    var key: PushDeckMLParamKey
    var value: Double
}

struct PushDeckEventPayload: Codable, Equatable {
    var eventId: String
    var sourceId: String
    var controlKind: PushDeckControlKind
    var modeContext: PushDeckModeContext
    var timingMode: PushDeckTimingMode
    var quantIntervalMs: Int?
    var pad: PushDeckPadControl?
    var macro: PushDeckMacroControl?
    var longStrip: PushDeckLongStripControl?
    var bank: PushDeckBankControl?
    var mlParam: PushDeckMLParamControl?
    var issuedAt: TimeInterval
}

struct PushWireEnvelope<T: Codable>: Codable {
    let kind: String
    let data: T
    let sentAt: TimeInterval
}
