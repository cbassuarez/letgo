import Foundation

public struct ScriptCandidate: Identifiable, Codable, Equatable {
    public enum Arc: String, Codable {
        case arc1
        case arc2
        case arc3
    }

    public let id: String
    public let arc: Arc
    public let tags: [String]
    public let text: String
    public let weight: Double
    public let cooldown: TimeInterval
    public let tone: String

    public init(id: String, arc: Arc, tags: [String], text: String, weight: Double, cooldown: TimeInterval, tone: String) {
        self.id = id
        self.arc = arc
        self.tags = tags
        self.text = text
        self.weight = weight
        self.cooldown = cooldown
        self.tone = tone
    }
}

public struct SelectionDecision: Codable, Equatable {
    public let selectedId: String?
    public let modelScore: Double
    public let rulePass: Bool
    public let reason: String
    public let cueId: String
    public let text: String?
    public let presentation: PresentationDirective?

    public init(
        selectedId: String?,
        modelScore: Double,
        rulePass: Bool,
        reason: String,
        cueId: String,
        text: String?,
        presentation: PresentationDirective? = nil
    ) {
        self.selectedId = selectedId
        self.modelScore = modelScore
        self.rulePass = rulePass
        self.reason = reason
        self.cueId = cueId
        self.text = text
        self.presentation = presentation
    }
}

public struct ScoringResult {
    public let score: Double
    public let presentation: PresentationDirective?

    public init(score: Double, presentation: PresentationDirective? = nil) {
        self.score = score
        self.presentation = presentation
    }
}

public protocol TextScoringModel {
    func score(candidate: ScriptCandidate, cueId: String, vector: ParamVector) -> Double
    func scoreWithPresentation(candidate: ScriptCandidate, cueId: String, vector: ParamVector) -> ScoringResult
}

extension TextScoringModel {
    public func scoreWithPresentation(candidate: ScriptCandidate, cueId: String, vector: ParamVector) -> ScoringResult {
        ScoringResult(score: score(candidate: candidate, cueId: cueId, vector: vector))
    }
}

public struct HeuristicScoringModel: TextScoringModel {
    public init() {}

    public func score(candidate: ScriptCandidate, cueId: String, vector: ParamVector) -> Double {
        var score = candidate.weight
        score += vector.textAmount * 0.25
        score += vector.compositeBias * 0.15
        if cueId.contains("main") {
            score += 0.2
        }
        return score
    }
}

public actor TextSelectionEngine {
    private let model: TextScoringModel
    private var lastSeen: [String: Date] = [:]

    public init(model: TextScoringModel = HeuristicScoringModel()) {
        self.model = model
    }

    public func select(
        from bank: [ScriptCandidate],
        cueId: String,
        arc: ScriptCandidate.Arc,
        vector: ParamVector,
        now: Date = Date(),
        bannedTags: Set<String> = []
    ) -> SelectionDecision {
        let eligible = bank.filter { candidate in
            guard candidate.arc == arc else { return false }
            guard Set(candidate.tags).isDisjoint(with: bannedTags) else { return false }

            if let last = lastSeen[candidate.id] {
                return now.timeIntervalSince(last) >= candidate.cooldown
            }

            return true
        }

        guard !eligible.isEmpty else {
            return SelectionDecision(
                selectedId: nil,
                modelScore: 0,
                rulePass: false,
                reason: "No eligible candidate",
                cueId: cueId,
                text: nil
            )
        }

        let ranked = eligible
            .map { candidate in
                let result = model.scoreWithPresentation(candidate: candidate, cueId: cueId, vector: vector)
                return (candidate, result)
            }
            .sorted { lhs, rhs in lhs.1.score > rhs.1.score }

        guard let best = ranked.first else {
            return SelectionDecision(
                selectedId: nil,
                modelScore: 0,
                rulePass: false,
                reason: "Ranking failure",
                cueId: cueId,
                text: nil
            )
        }

        lastSeen[best.0.id] = now

        return SelectionDecision(
            selectedId: best.0.id,
            modelScore: best.1.score,
            rulePass: true,
            reason: "Selected by hybrid ML+rules",
            cueId: cueId,
            text: best.0.text,
            presentation: best.1.presentation ?? .fallback
        )
    }
}
