import ConductorCore
import Foundation
import XCTest

final class CoreMLScoringModelTests: XCTestCase {
    func testDiscoversCompiledModelBundles() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let modelsDir = root.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let compiledA = modelsDir.appendingPathComponent("ConfessionalScorer.mlmodelc", isDirectory: true)
        let nested = modelsDir.appendingPathComponent("Nested", isDirectory: true)
        let compiledB = nested.appendingPathComponent("ReleaseArc.mlmodelc", isDirectory: true)

        try FileManager.default.createDirectory(at: compiledA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: compiledB, withIntermediateDirectories: true)

        let discovered = CoreMLModelLocator.discoverCompiledModels(in: [modelsDir])

        XCTAssertEqual(discovered.count, 2)
        XCTAssertEqual(Set(discovered.map(\.name)), Set(["ConfessionalScorer", "ReleaseArc"]))
    }

    func testInvalidBundleExtensionFallsBackWithUnavailableHealth() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let invalidFile = root.appendingPathComponent("not-a-compiled-model.txt")
        guard let data = "test".data(using: .utf8) else {
            XCTFail("Failed to build test payload")
            return
        }
        try data.write(to: invalidFile)

        let adapter = CoreMLScoringModelAdapter(searchDirectories: [root])
        let report = adapter.loadModel(at: invalidFile)

        XCTAssertEqual(report.level, .unavailable)
        XCTAssertTrue(report.usingFallback)
        XCTAssertNil(report.modelPath)
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coreml-health-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
