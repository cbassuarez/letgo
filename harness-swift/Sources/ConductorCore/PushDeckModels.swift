import Foundation

public enum PushDeckControlKind: String, Codable, CaseIterable, Sendable {
    case padDown = "pad_down"
    case padUp = "pad_up"
    case macro
    case longStrip = "long_strip"
    case bankSelect = "bank_select"
    case mlParam = "ml_param"
}

public enum PushDeckModeContext: String, Codable, CaseIterable, Sendable {
    case auto
    case dynamic
    case `static`
    case choir
}

public enum PushDeckTimingMode: String, Codable, CaseIterable, Sendable {
    case immediate
    case quantized
}

public enum PushDeckBankDomain: String, Codable, CaseIterable, Sendable {
    case main
    case choir
}

public enum PushDeckMLParamKey: String, Codable, CaseIterable, Sendable {
    case phonePadEchoProbability = "phone_pad_echo_probability"
}

public struct PushDeckPadControl: Codable, Equatable, Sendable {
    public var row: Int
    public var column: Int
    public var slot: Int
    public var pressure: Double
    public var velocity: Double

    public init(row: Int, column: Int, slot: Int, pressure: Double, velocity: Double) {
        self.row = min(7, max(0, row))
        self.column = min(7, max(0, column))
        self.slot = min(63, max(0, slot))
        self.pressure = min(1, max(0, pressure))
        self.velocity = min(1, max(0, velocity))
    }
}

public struct PushDeckMacroControl: Codable, Equatable, Sendable {
    public var lane: Int
    public var value: Double

    public init(lane: Int, value: Double) {
        self.lane = min(8, max(1, lane))
        self.value = min(1, max(0, value))
    }
}

public struct PushDeckLongStripControl: Codable, Equatable, Sendable {
    public var value: Double

    public init(value: Double) {
        self.value = min(1, max(0, value))
    }
}

public struct PushDeckBankControl: Codable, Equatable, Sendable {
    public var domain: PushDeckBankDomain
    public var bank: Int

    public init(domain: PushDeckBankDomain, bank: Int) {
        self.domain = domain
        self.bank = min(3, max(1, bank))
    }
}

public struct PushDeckMLParamControl: Codable, Equatable, Sendable {
    public var key: PushDeckMLParamKey
    public var value: Double

    public init(key: PushDeckMLParamKey, value: Double) {
        self.key = key
        switch key {
        case .phonePadEchoProbability:
            self.value = min(0.2, max(0, value))
        }
    }
}

public struct PushDeckEventPayload: Codable, Equatable, Sendable {
    public var eventId: String
    public var sourceId: String
    public var controlKind: PushDeckControlKind
    public var modeContext: PushDeckModeContext
    public var timingMode: PushDeckTimingMode
    public var quantIntervalMs: Int?
    public var pad: PushDeckPadControl?
    public var macro: PushDeckMacroControl?
    public var longStrip: PushDeckLongStripControl?
    public var bank: PushDeckBankControl?
    public var mlParam: PushDeckMLParamControl?
    public var issuedAt: TimeInterval

    public init(
        eventId: String,
        sourceId: String,
        controlKind: PushDeckControlKind,
        modeContext: PushDeckModeContext,
        timingMode: PushDeckTimingMode,
        quantIntervalMs: Int? = nil,
        pad: PushDeckPadControl? = nil,
        macro: PushDeckMacroControl? = nil,
        longStrip: PushDeckLongStripControl? = nil,
        bank: PushDeckBankControl? = nil,
        mlParam: PushDeckMLParamControl? = nil,
        issuedAt: TimeInterval
    ) {
        self.eventId = eventId
        self.sourceId = sourceId
        self.controlKind = controlKind
        self.modeContext = modeContext
        self.timingMode = timingMode
        if let quantIntervalMs {
            self.quantIntervalMs = min(500, max(20, quantIntervalMs))
        } else {
            self.quantIntervalMs = nil
        }
        self.pad = pad
        self.macro = macro
        self.longStrip = longStrip
        self.bank = bank
        self.mlParam = mlParam
        self.issuedAt = issuedAt
    }
}
