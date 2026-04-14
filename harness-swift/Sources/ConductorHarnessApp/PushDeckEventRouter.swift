import ConductorCore
import Foundation

struct PushDeckPadIntent: Equatable, Sendable {
    enum Phase: String, Sendable {
        case down
        case up
    }

    var mode: PushDeckModeContext
    var phase: Phase
    var row: Int
    var column: Int
    var slot: Int
    var velocity: Double
    var pressure: Double
    var timingMode: PushDeckTimingMode
    var quantIntervalMs: Int?
}

enum PushDeckResolvedIntent: Equatable, Sendable {
    case controlAction(ControlAction)
    case pad(PushDeckPadIntent)
    case mlParam(PushDeckMLParamControl)
}

struct PushDeckRouteResult: Equatable, Sendable {
    var intents: [PushDeckResolvedIntent]
    var ignoredReason: String?

    static func ignored(_ reason: String) -> PushDeckRouteResult {
        PushDeckRouteResult(intents: [], ignoredReason: reason)
    }
}

struct PushDeckEventRouter {
    func resolve(
        event: PushDeckEventPayload,
        fallbackMode: PushDeckModeContext
    ) -> PushDeckRouteResult {
        let mode = event.modeContext == .auto ? fallbackMode : event.modeContext

        switch event.controlKind {
        case .mlParam:
            guard let mlParam = event.mlParam else {
                return .ignored("ml_param payload missing")
            }
            return PushDeckRouteResult(intents: [.mlParam(mlParam)], ignoredReason: nil)

        case .macro:
            guard let macro = event.macro else {
                return .ignored("macro payload missing")
            }
            guard let action = mapMacroLane(macro.lane, value: macro.value, mode: mode) else {
                return .ignored("unsupported macro lane \(macro.lane)")
            }
            return PushDeckRouteResult(intents: [.controlAction(action)], ignoredReason: nil)

        case .longStrip:
            guard let longStrip = event.longStrip else {
                return .ignored("long_strip payload missing")
            }
            return PushDeckRouteResult(
                intents: [.controlAction(.setStaticTextureSend(longStrip.value))],
                ignoredReason: nil
            )

        case .bankSelect:
            guard let bank = event.bank else {
                return .ignored("bank payload missing")
            }
            let domain: SampleBankDomain = bank.domain == .choir ? .choir : .main
            return PushDeckRouteResult(
                intents: [.controlAction(.setSampleBank(bank.bank, domain: domain))],
                ignoredReason: nil
            )

        case .padDown, .padUp:
            guard let pad = event.pad else {
                return .ignored("pad payload missing")
            }
            let phase: PushDeckPadIntent.Phase = event.controlKind == .padDown ? .down : .up
            let padIntent = PushDeckPadIntent(
                mode: mode,
                phase: phase,
                row: pad.row,
                column: pad.column,
                slot: pad.slot,
                velocity: pad.velocity,
                pressure: pad.pressure,
                timingMode: event.timingMode,
                quantIntervalMs: event.quantIntervalMs
            )
            return PushDeckRouteResult(intents: [.pad(padIntent)], ignoredReason: nil)
        }
    }

    private func mapMacroLane(
        _ lane: Int,
        value: Double,
        mode: PushDeckModeContext
    ) -> ControlAction? {
        let clamped = min(1, max(0, value))
        switch lane {
        case 1:
            switch mode {
            case .dynamic:
                return .setDynamicBinSelection(clamped)
            case .static:
                return .setStaticSampleMorph(clamped)
            case .choir:
                return .setChoirFieldSpread(clamped)
            case .auto:
                return .setDynamicBinSelection(clamped)
            }
        case 2:
            switch mode {
            case .dynamic:
                return .setCutCadence(clamped)
            case .static:
                return .setStaticArticulation(clamped)
            case .choir:
                return .setChoirFieldDepth(clamped)
            case .auto:
                return .setCutCadence(clamped)
            }
        case 3:
            switch mode {
            case .dynamic:
                return .setCompositorBlend(clamped)
            case .static:
                return .setStaticTimbre(clamped)
            case .choir:
                return .setChoirFieldDetune(clamped)
            case .auto:
                return .setCompositorBlend(clamped)
            }
        case 4:
            return .setTextProbability(clamped)
        case 5:
            return .setStrictLooseBlend(clamped)
        case 6:
            return .setVisualVariance(clamped)
        case 7:
            return .setEffectsChain(chain: .a, active: clamped > 0.01, intensity: clamped)
        case 8:
            return .setEffectsChain(chain: .b, active: clamped > 0.01, intensity: clamped)
        default:
            return nil
        }
    }
}
