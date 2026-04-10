import Foundation

#if canImport(CoreML)
import CoreML
#endif

public struct CompiledModelCandidate: Identifiable, Hashable, Sendable {
    public let name: String
    public let url: URL

    public var id: String { url.path }

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

public enum ModelHealthLevel: String, Codable, Sendable {
    case healthy
    case degraded
    case unavailable
}

public struct ModelHealthCheck: Identifiable, Codable, Hashable, Sendable {
    public let name: String
    public let passed: Bool
    public let details: String

    public var id: String { name }

    public init(name: String, passed: Bool, details: String) {
        self.name = name
        self.passed = passed
        self.details = details
    }
}

public struct ModelHealthReport: Codable, Sendable {
    public let level: ModelHealthLevel
    public let usingFallback: Bool
    public let summary: String
    public let modelName: String?
    public let modelPath: String?
    public let outputFeatureName: String?
    public let runtimeFailureCount: Int
    public let checks: [ModelHealthCheck]
    public let checkedAt: Date

    public init(
        level: ModelHealthLevel,
        usingFallback: Bool,
        summary: String,
        modelName: String?,
        modelPath: String?,
        outputFeatureName: String?,
        runtimeFailureCount: Int,
        checks: [ModelHealthCheck],
        checkedAt: Date = Date()
    ) {
        self.level = level
        self.usingFallback = usingFallback
        self.summary = summary
        self.modelName = modelName
        self.modelPath = modelPath
        self.outputFeatureName = outputFeatureName
        self.runtimeFailureCount = runtimeFailureCount
        self.checks = checks
        self.checkedAt = checkedAt
    }

    public static func unavailable(summary: String, checks: [ModelHealthCheck] = []) -> ModelHealthReport {
        ModelHealthReport(
            level: .unavailable,
            usingFallback: true,
            summary: summary,
            modelName: nil,
            modelPath: nil,
            outputFeatureName: nil,
            runtimeFailureCount: 0,
            checks: checks
        )
    }
}

public enum CoreMLModelLocator {
    public static func defaultSearchDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [URL] {
        var urls: [URL] = []

        if let explicitPath = environment["CONDUCTOR_COREML_MODEL_PATH"], !explicitPath.isEmpty {
            let explicitURL = URL(fileURLWithPath: explicitPath)
            if explicitURL.pathExtension == "mlmodelc" {
                urls.append(explicitURL)
                urls.append(explicitURL.deletingLastPathComponent())
            } else {
                urls.append(explicitURL)
            }
        }

        if let explicitDir = environment["CONDUCTOR_COREML_MODEL_DIR"], !explicitDir.isEmpty {
            urls.append(URL(fileURLWithPath: explicitDir))
        }

        let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        urls.append(workingDirectory.appendingPathComponent("Models", isDirectory: true))
        urls.append(workingDirectory)

        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("Models", isDirectory: true))
            urls.append(resourceURL)
        }

        var seen = Set<String>()
        return urls.filter { url in
            let key = url.standardizedFileURL.path
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    public static func discoverCompiledModels(
        in searchDirectories: [URL],
        fileManager: FileManager = .default
    ) -> [CompiledModelCandidate] {
        var discovered: [CompiledModelCandidate] = []

        for root in searchDirectories {
            if root.pathExtension == "mlmodelc" {
                let isDirectory = (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    discovered.append(candidate(from: root))
                }
                continue
            }

            guard fileManager.fileExists(atPath: root.path) else {
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "mlmodelc" else {
                    continue
                }
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    discovered.append(candidate(from: url))
                }
                enumerator.skipDescendants()
            }
        }

        var seen = Set<String>()
        return discovered
            .filter { candidate in
                if seen.contains(candidate.id) {
                    return false
                }
                seen.insert(candidate.id)
                return true
            }
            .sorted { lhs, rhs in lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
    }

    private static func candidate(from url: URL) -> CompiledModelCandidate {
        let folderName = url.deletingPathExtension().lastPathComponent
        return CompiledModelCandidate(name: folderName, url: url)
    }
}

public final class CoreMLScoringModelAdapter: TextScoringModel {
    #if canImport(CoreML)
    private struct LoadedModel {
        let model: MLModel
        let candidate: CompiledModelCandidate
        let outputFeatureName: String
    }

    private var loadedModel: LoadedModel?
    #endif

    private let fallback = HeuristicScoringModel()
    private let lock = NSLock()

    private var searchDirectories: [URL]
    private var healthReport: ModelHealthReport
    private var runtimeFailureCount = 0

    public init(
        modelURL: URL? = nil,
        preferredModelName: String? = nil,
        searchDirectories: [URL] = CoreMLModelLocator.defaultSearchDirectories()
    ) {
        self.searchDirectories = searchDirectories
        self.healthReport = .unavailable(
            summary: "No CoreML model loaded; using heuristic scorer.",
            checks: [
                ModelHealthCheck(
                    name: "initialization",
                    passed: false,
                    details: "Model not loaded yet"
                )
            ]
        )

        if let modelURL {
            _ = loadModel(at: modelURL)
        } else {
            _ = reload(preferredModelName: preferredModelName)
        }
    }

    public func availableModelCandidates() -> [CompiledModelCandidate] {
        CoreMLModelLocator.discoverCompiledModels(in: lock.withLock { searchDirectories })
    }

    @discardableResult
    public func reload(preferredModelName: String? = nil) -> ModelHealthReport {
        let candidates = availableModelCandidates()
        guard !candidates.isEmpty else {
            return publishUnavailable(
                summary: "No .mlmodelc bundle found in search paths.",
                checks: [
                    ModelHealthCheck(
                        name: "bundle_discovery",
                        passed: false,
                        details: "Searched \(lock.withLock { searchDirectories.count }) directories"
                    )
                ]
            )
        }

        if let explicitPath = ProcessInfo.processInfo.environment["CONDUCTOR_COREML_MODEL_PATH"], !explicitPath.isEmpty {
            return loadModel(at: URL(fileURLWithPath: explicitPath))
        }

        let selected = chooseCandidate(preferredModelName: preferredModelName, candidates: candidates)
        return loadModel(at: selected.url)
    }

    @discardableResult
    public func loadModel(at modelURL: URL) -> ModelHealthReport {
        var checks: [ModelHealthCheck] = []

        let exists = FileManager.default.fileExists(atPath: modelURL.path)
        checks.append(
            ModelHealthCheck(
                name: "bundle_exists",
                passed: exists,
                details: exists ? modelURL.path : "Missing path: \(modelURL.path)"
            )
        )

        guard exists else {
            return publishUnavailable(
                summary: "CoreML bundle path is missing.",
                checks: checks
            )
        }

        guard modelURL.pathExtension == "mlmodelc" else {
            checks.append(
                ModelHealthCheck(
                    name: "compiled_bundle_extension",
                    passed: false,
                    details: "Expected .mlmodelc, got .\(modelURL.pathExtension)"
                )
            )
            return publishUnavailable(
                summary: "Selected model is not a compiled .mlmodelc bundle.",
                checks: checks
            )
        }

        #if canImport(CoreML)
        do {
            let configuration = MLModelConfiguration()
            let model = try MLModel(contentsOf: modelURL, configuration: configuration)
            checks.append(
                ModelHealthCheck(
                    name: "model_deserialization",
                    passed: true,
                    details: "Model loaded into memory"
                )
            )

            guard let outputFeatureName = chooseOutputFeatureName(from: model) else {
                checks.append(
                    ModelHealthCheck(
                        name: "output_feature",
                        passed: false,
                        details: "Model has no numeric output feature"
                    )
                )
                return publishUnavailable(
                    summary: "Model loaded, but no numeric output feature was found.",
                    checks: checks
                )
            }

            checks.append(
                ModelHealthCheck(
                    name: "output_feature",
                    passed: true,
                    details: "Using output '\(outputFeatureName)'"
                )
            )

            let probeCheck = runProbePrediction(with: model, outputFeatureName: outputFeatureName)
            checks.append(probeCheck)

            guard probeCheck.passed else {
                return publishUnavailable(
                    summary: "Model failed runtime probe and was not activated.",
                    checks: checks
                )
            }

            let candidate = CompiledModelCandidate(
                name: modelURL.deletingPathExtension().lastPathComponent,
                url: modelURL
            )

            let report = lock.withLock { () -> ModelHealthReport in
                runtimeFailureCount = 0
                loadedModel = LoadedModel(
                    model: model,
                    candidate: candidate,
                    outputFeatureName: outputFeatureName
                )

                let report = ModelHealthReport(
                    level: .healthy,
                    usingFallback: false,
                    summary: "CoreML model active and probe-validated.",
                    modelName: candidate.name,
                    modelPath: candidate.url.path,
                    outputFeatureName: outputFeatureName,
                    runtimeFailureCount: runtimeFailureCount,
                    checks: checks
                )
                healthReport = report
                return report
            }

            return report
        } catch {
            checks.append(
                ModelHealthCheck(
                    name: "model_deserialization",
                    passed: false,
                    details: error.localizedDescription
                )
            )
            return publishUnavailable(
                summary: "Failed to deserialize CoreML model.",
                checks: checks
            )
        }
        #else
        checks.append(
            ModelHealthCheck(
                name: "coreml_framework",
                passed: false,
                details: "CoreML is unavailable on this runtime"
            )
        )
        return publishUnavailable(
            summary: "CoreML framework unavailable; fallback scorer active.",
            checks: checks
        )
        #endif
    }

    public func currentHealth() -> ModelHealthReport {
        lock.withLock { healthReport }
    }

    public func score(candidate: ScriptCandidate, cueId: String, vector: ParamVector) -> Double {
        scoreWithPresentation(candidate: candidate, cueId: cueId, vector: vector).score
    }

    public func scoreWithPresentation(candidate: ScriptCandidate, cueId: String, vector: ParamVector) -> ScoringResult {
        let base = fallback.score(candidate: candidate, cueId: cueId, vector: vector)

        #if canImport(CoreML)
        let loaded = lock.withLock { loadedModel }
        guard let loaded else {
            return ScoringResult(score: base)
        }

        do {
            let provider = try makeFeatureProvider(
                for: loaded.model,
                candidate: candidate,
                cueId: cueId,
                vector: vector
            )
            let prediction = try loaded.model.prediction(from: provider)
            guard let rawScore = extractScore(from: prediction, outputFeatureName: loaded.outputFeatureName) else {
                registerRuntimeFailure("Could not parse output feature '\(loaded.outputFeatureName)'.")
                return ScoringResult(score: base)
            }
            let blendedScore = (rawScore * 0.6) + (base * 0.4)
            let presentation = extractPresentation(from: prediction)
            return ScoringResult(score: blendedScore, presentation: presentation)
        } catch {
            registerRuntimeFailure(error.localizedDescription)
            return ScoringResult(score: base)
        }
        #else
        return ScoringResult(score: base)
        #endif
    }

    private func chooseCandidate(
        preferredModelName: String?,
        candidates: [CompiledModelCandidate]
    ) -> CompiledModelCandidate {
        guard let preferredModelName, !preferredModelName.isEmpty else {
            return candidates[0]
        }

        let preferred = normalizeModelName(preferredModelName)
        if let exact = candidates.first(where: { normalizeModelName($0.name) == preferred }) {
            return exact
        }

        if let fuzzy = candidates.first(where: { normalizeModelName($0.name).contains(preferred) }) {
            return fuzzy
        }

        return candidates[0]
    }

    private func normalizeModelName(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: ".mlmodelc", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func publishUnavailable(summary: String, checks: [ModelHealthCheck]) -> ModelHealthReport {
        lock.withLock {
            #if canImport(CoreML)
            loadedModel = nil
            #endif
            runtimeFailureCount = 0
            let report = ModelHealthReport(
                level: .unavailable,
                usingFallback: true,
                summary: summary,
                modelName: nil,
                modelPath: nil,
                outputFeatureName: nil,
                runtimeFailureCount: runtimeFailureCount,
                checks: checks
            )
            healthReport = report
            return report
        }
    }

    private func registerRuntimeFailure(_ details: String) {
        lock.withLock {
            runtimeFailureCount += 1

            let priorChecks = healthReport.checks.filter { $0.name != "runtime_prediction" }
            let runtimeCheck = ModelHealthCheck(
                name: "runtime_prediction",
                passed: false,
                details: details
            )
            let mergedChecks = priorChecks + [runtimeCheck]

            let nextLevel: ModelHealthLevel = healthReport.level == .healthy ? .degraded : healthReport.level

            healthReport = ModelHealthReport(
                level: nextLevel,
                usingFallback: true,
                summary: "Runtime prediction failed; fallback scorer engaged.",
                modelName: healthReport.modelName,
                modelPath: healthReport.modelPath,
                outputFeatureName: healthReport.outputFeatureName,
                runtimeFailureCount: runtimeFailureCount,
                checks: mergedChecks
            )
        }
    }

    #if canImport(CoreML)
    private func chooseOutputFeatureName(from model: MLModel) -> String? {
        let outputs = model.modelDescription.outputDescriptionsByName
        if outputs["score"] != nil {
            return "score"
        }

        if let numeric = outputs.first(where: { item in
            item.value.type == .double || item.value.type == .int64 || item.value.type == .multiArray
        }) {
            return numeric.key
        }

        return outputs.keys.sorted().first
    }

    private func runProbePrediction(
        with model: MLModel,
        outputFeatureName: String
    ) -> ModelHealthCheck {
        let probeCandidate = ScriptCandidate(
            id: "probe",
            arc: .arc2,
            tags: ["health"],
            text: "health probe",
            weight: 0.5,
            cooldown: 0,
            tone: "confessional"
        )

        do {
            let provider = try makeFeatureProvider(
                for: model,
                candidate: probeCandidate,
                cueId: "main:probe",
                vector: .neutral
            )
            let prediction = try model.prediction(from: provider)
            let score = extractScore(from: prediction, outputFeatureName: outputFeatureName)
            if let score {
                return ModelHealthCheck(
                    name: "probe_prediction",
                    passed: true,
                    details: "Probe score \(String(format: "%.4f", score))"
                )
            }

            return ModelHealthCheck(
                name: "probe_prediction",
                passed: false,
                details: "Prediction output did not contain numeric score"
            )
        } catch {
            return ModelHealthCheck(
                name: "probe_prediction",
                passed: false,
                details: error.localizedDescription
            )
        }
    }

    private func makeFeatureProvider(
        for model: MLModel,
        candidate: ScriptCandidate,
        cueId: String,
        vector: ParamVector
    ) throws -> MLFeatureProvider {
        var dictionary: [String: Any] = [:]

        for (name, description) in model.modelDescription.inputDescriptionsByName {
            dictionary[name] = try featureValue(
                forInputNamed: name,
                description: description,
                candidate: candidate,
                cueId: cueId,
                vector: vector
            )
        }

        return try MLDictionaryFeatureProvider(dictionary: dictionary)
    }

    private func featureValue(
        forInputNamed name: String,
        description: MLFeatureDescription,
        candidate: ScriptCandidate,
        cueId: String,
        vector: ParamVector
    ) throws -> Any {
        let loweredName = name.lowercased()

        switch description.type {
        case .double:
            return mappedDouble(for: loweredName, candidate: candidate, cueId: cueId, vector: vector)
        case .int64:
            return Int64(mappedDouble(for: loweredName, candidate: candidate, cueId: cueId, vector: vector).rounded())
        case .string:
            if loweredName.contains("cue") {
                return cueId
            }
            if loweredName.contains("tone") {
                return candidate.tone
            }
            if loweredName.contains("text") {
                return candidate.text
            }
            return candidate.id
        case .multiArray:
            guard let constraint = description.multiArrayConstraint else {
                throw NSError(
                    domain: "CoreMLScoringModelAdapter",
                    code: 101,
                    userInfo: [NSLocalizedDescriptionKey: "Missing multi-array constraint for input '\(name)'"]
                )
            }

            let array = try MLMultiArray(shape: constraint.shape, dataType: constraint.dataType)
            let mapped = mappedDouble(for: loweredName, candidate: candidate, cueId: cueId, vector: vector)
            if array.count == 1 {
                array[0] = NSNumber(value: mapped)
            } else {
                for idx in 0 ..< array.count {
                    array[idx] = NSNumber(value: 0.0)
                }
            }
            return array
        default:
            throw NSError(
                domain: "CoreMLScoringModelAdapter",
                code: 102,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported CoreML input type for '\(name)'"]
            )
        }
    }

    private func mappedDouble(
        for loweredName: String,
        candidate: ScriptCandidate,
        cueId: String,
        vector: ParamVector
    ) -> Double {
        if loweredName.contains("weight") {
            return candidate.weight
        }
        if loweredName.contains("textamount") || loweredName.contains("text_amount") {
            return vector.textAmount
        }
        if loweredName.contains("composite") {
            return vector.compositeBias
        }
        if loweredName.contains("audiogain") || loweredName.contains("audio_gain") {
            return vector.audioGain
        }
        if loweredName.contains("spatialx") || loweredName.contains("spatial_x") {
            return vector.spatialX
        }
        if loweredName.contains("spatialy") || loweredName.contains("spatial_y") {
            return vector.spatialY
        }
        if loweredName.contains("spatialz") || loweredName.contains("spatial_z") {
            return vector.spatialZ
        }
        if loweredName.contains("textlength") || loweredName.contains("text_length") {
            return min(1.0, Double(candidate.text.count) / 200.0)
        }
        if loweredName.contains("audiorms") || loweredName.contains("audio_rms") {
            return vector.audioGain // placeholder: proxy from audioGain until live extraction
        }
        if loweredName.contains("audiospectral") || loweredName.contains("audio_spectral") {
            return 0.5 // placeholder: spectral centroid not yet extracted
        }
        if loweredName.contains("videoluminance") || loweredName.contains("video_luminance") {
            return 0.5 // placeholder: frame luminance not yet extracted
        }
        if loweredName.contains("videomotion") || loweredName.contains("video_motion") {
            return 0.5 // placeholder: inter-frame motion not yet extracted
        }
        if loweredName.contains("ismain") || loweredName.contains("is_main") {
            return cueId.contains("main") ? 1 : 0
        }
        if loweredName.contains("arc") {
            switch candidate.arc {
            case .arc1:
                return 1
            case .arc2:
                return 2
            case .arc3:
                return 3
            }
        }
        return 0
    }

    private func extractScore(from prediction: MLFeatureProvider, outputFeatureName: String) -> Double? {
        extractDouble(from: prediction, named: outputFeatureName)
    }

    private func extractDouble(from prediction: MLFeatureProvider, named name: String) -> Double? {
        guard let feature = prediction.featureValue(for: name) else { return nil }
        switch feature.type {
        case .double:
            return feature.doubleValue
        case .int64:
            return Double(feature.int64Value)
        case .multiArray:
            guard let array = feature.multiArrayValue, array.count > 0 else { return nil }
            return array[0].doubleValue
        default:
            return nil
        }
    }

    private func extractPresentation(from prediction: MLFeatureProvider) -> PresentationDirective? {
        let names = prediction.featureNames

        guard names.contains("displayDuration") || names.contains("compositeAlpha")
                || names.contains("fontSize") || names.contains("fontWeight") else {
            return nil
        }

        return PresentationDirective(
            displayDuration: max(1.0, min(15.0, extractDouble(from: prediction, named: "displayDuration") ?? 5.0)),
            compositeAlpha: max(0.0, min(1.0, extractDouble(from: prediction, named: "compositeAlpha") ?? 0.85)),
            fontSize: max(0.0, min(1.0, extractDouble(from: prediction, named: "fontSize") ?? 0.5)),
            fontWeight: max(0.0, min(1.0, extractDouble(from: prediction, named: "fontWeight") ?? 0.5))
        )
    }
    #endif
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
