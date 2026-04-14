import AVFoundation
import Foundation

private struct BundledPadMap: Decodable {
    struct Slice: Decodable {
        let slot: Int
        let startSec: Double
        let oneShotSec: Double
    }

    let sourceFile: String
    let slices: [Slice]
}

private struct ActivePadPlayback {
    let player: AVAudioPlayer
    let bank: Int
    let slot: Int
    let startSec: Double
}

final class PushPadAuditionEngine {
    private var mapLoaded = false
    private var sourceURLByBank: [Int: URL] = [:]
    private var sliceMapByBank: [Int: [Int: BundledPadMap.Slice]] = [:]
    private var activePlaybackBySlot: [Int: ActivePadPlayback] = [:]

    func padDown(
        slot: Int,
        bank: Int,
        mode: PushDeckModeContext,
        velocity: Double
    ) {
        guard mode != .choir else { return }
        guard prepareAudioSession() else { return }
        guard loadMapsIfNeeded() else { return }

        let clampedSlot = max(0, min(63, slot))
        let clampedBank = max(1, min(2, bank))
        guard let sourceURL = sourceURLByBank[clampedBank],
              let slice = sliceMapByBank[clampedBank]?[clampedSlot] else {
            return
        }

        stopSlot(clampedSlot)

        do {
            let player = try AVAudioPlayer(contentsOf: sourceURL)
            player.currentTime = max(0, min(slice.startSec, max(0, player.duration - 0.01)))
            player.volume = Float(min(1.0, max(0.08, 0.2 + velocity * 0.7)))
            player.prepareToPlay()
            player.play()

            activePlaybackBySlot[clampedSlot] = ActivePadPlayback(
                player: player,
                bank: clampedBank,
                slot: clampedSlot,
                startSec: slice.startSec
            )
        } catch {
            return
        }
    }

    func padUp(slot: Int) {
        let clampedSlot = max(0, min(63, slot))
        stopSlot(clampedSlot)
    }

    private func stopSlot(_ slot: Int) {
        if let active = activePlaybackBySlot.removeValue(forKey: slot) {
            active.player.stop()
        }
    }

    private func prepareAudioSession() -> Bool {
        prepareSharedAudioSession()
    }

    private func loadMapsIfNeeded() -> Bool {
        if mapLoaded { return true }
        let decoder = JSONDecoder()
        var loadedAny = false

        for bank in 1...2 {
            guard let bundleRoot = Bundle.main.resourceURL else { continue }
            let bankFolder = bundleRoot.appendingPathComponent("Samples/main_b\(bank)")
            let mapURL = bankFolder.appendingPathComponent("pad_map.json")

            guard let data = try? Data(contentsOf: mapURL),
                  let map = try? decoder.decode(BundledPadMap.self, from: data) else {
                continue
            }

            let sourceURL = bankFolder.appendingPathComponent(map.sourceFile)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                continue
            }

            var slotMap: [Int: BundledPadMap.Slice] = [:]
            for slice in map.slices where (0..<64).contains(slice.slot) {
                slotMap[slice.slot] = slice
            }
            guard !slotMap.isEmpty else { continue }

            sourceURLByBank[bank] = sourceURL
            sliceMapByBank[bank] = slotMap
            loadedAny = true
        }

        mapLoaded = loadedAny
        return loadedAny
    }
}

struct PushLongStripSnapshot {
    let valueX: Double
    let valueY: Double
    let variantIndex: Int
    let variantCount: Int
    let variantLabel: String
    let isLatched: Bool
}

final class PushLongStripAuditionEngine {
    private var player: AVAudioPlayer?
    private var activeURL: URL?
    private var isActiveGesture = false
    private var isLatched = false
    private var variantURLsByBank: [Int: [URL]] = [:]
    private var activeVariantIndex = 0
    private var activeX: Double = 0.5
    private var activeY: Double = 0.5
    private var activeBank = 1

    func setLatched(_ enabled: Bool) -> PushLongStripSnapshot? {
        isLatched = enabled
        if !enabled, !isActiveGesture {
            stopWithFade()
        }
        return currentSnapshot()
    }

    func begin(bank: Int, x: Double, y: Double) -> PushLongStripSnapshot? {
        guard prepareSharedAudioSession() else { return nil }
        guard let context = resolveLongStripContext(bank: bank, y: y) else { return nil }
        activeBank = context.bank
        activeX = clamp01(x)
        activeY = clamp01(y)

        if activeURL != context.url || player == nil {
            do {
                let next = try AVAudioPlayer(contentsOf: context.url)
                next.numberOfLoops = -1
                next.prepareToPlay()
                player = next
                activeURL = context.url
                activeVariantIndex = context.variantIndex
            } catch {
                return nil
            }
        }

        guard let player else { return nil }
        isActiveGesture = true

        let target = activeX * max(0.001, player.duration)
        player.currentTime = max(0, min(target, max(0, player.duration - 0.01)))

        if !player.isPlaying {
            player.volume = 0
            player.play()
            player.setVolume(0.9, fadeDuration: 0.08)
        }
        return snapshot(
            variantIndex: context.variantIndex,
            variantCount: context.variantCount,
            variantLabel: context.variantLabel
        )
    }

    func scrub(bank: Int, x: Double, y: Double) -> PushLongStripSnapshot? {
        guard isActiveGesture else {
            return begin(bank: bank, x: x, y: y)
        }
        guard let context = resolveLongStripContext(bank: bank, y: y) else { return nil }
        activeBank = context.bank
        activeX = clamp01(x)
        activeY = clamp01(y)

        if activeURL != context.url {
            return begin(bank: context.bank, x: activeX, y: activeY)
        }
        guard let player else { return nil }

        let target = activeX * max(0.001, player.duration)
        let bounded = max(0, min(target, max(0, player.duration - 0.01)))

        // Avoid excessive seek churn while still feeling continuous.
        if abs(player.currentTime - bounded) > 0.08 {
            player.currentTime = bounded
        }
        if !player.isPlaying {
            player.play()
        }
        return snapshot(
            variantIndex: context.variantIndex,
            variantCount: context.variantCount,
            variantLabel: context.variantLabel
        )
    }

    func end() -> PushLongStripSnapshot? {
        isActiveGesture = false
        if !isLatched {
            stopWithFade()
        }
        return currentSnapshot()
    }

    private func stopWithFade() {
        guard let player else { return }
        player.setVolume(0, fadeDuration: 0.12)
        let token = activeURL
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard let self, !self.isActiveGesture else { return }
            guard self.activeURL == token else { return }
            self.player?.stop()
        }
    }

    private func resolveLongStripContext(bank: Int, y: Double) -> (
        bank: Int,
        url: URL,
        variantIndex: Int,
        variantCount: Int,
        variantLabel: String
    )? {
        let clampedBank = max(1, min(2, bank))
        let variants = variantsForBank(clampedBank)
        guard !variants.isEmpty else { return nil }
        let index = variantIndex(for: y, count: variants.count)
        let url = variants[index]
        return (
            bank: clampedBank,
            url: url,
            variantIndex: index,
            variantCount: variants.count,
            variantLabel: variantLabel(for: url)
        )
    }

    private func variantsForBank(_ bank: Int) -> [URL] {
        if let cached = variantURLsByBank[bank] {
            return cached
        }

        guard let bundleRoot = Bundle.main.resourceURL else { return [] }
        let folder = bundleRoot.appendingPathComponent("Samples/main_b\(bank)")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let prefix = "long_paul_b\(bank)"
        let filtered = files
            .filter { url in
                let name = url.lastPathComponent.lowercased()
                return name.hasPrefix(prefix.lowercased()) && name.hasSuffix(".m4a")
            }
            .sorted { lhs, rhs in
                let ln = lhs.lastPathComponent.lowercased()
                let rn = rhs.lastPathComponent.lowercased()
                if ln == "\(prefix).m4a" { return true }
                if rn == "\(prefix).m4a" { return false }
                return ln < rn
            }

        variantURLsByBank[bank] = filtered
        return filtered
    }

    private func variantIndex(for y: Double, count: Int) -> Int {
        let clamped = clamp01(y)
        let mapped = Int(floor((1 - clamped) * Double(count)))
        return min(count - 1, max(0, mapped))
    }

    private func variantLabel(for url: URL) -> String {
        var base = url.deletingPathExtension().lastPathComponent
        if let range = base.range(of: "_v", options: [.backwards]) {
            let suffix = String(base[range.upperBound...])
            base = "v\(suffix)"
        } else {
            base = "base"
        }
        return base.uppercased()
    }

    private func snapshot(
        variantIndex: Int,
        variantCount: Int,
        variantLabel: String
    ) -> PushLongStripSnapshot {
        PushLongStripSnapshot(
            valueX: activeX,
            valueY: activeY,
            variantIndex: variantIndex,
            variantCount: variantCount,
            variantLabel: variantLabel,
            isLatched: isLatched
        )
    }

    private func currentSnapshot() -> PushLongStripSnapshot? {
        guard let context = resolveLongStripContext(bank: activeBank, y: activeY) else {
            return nil
        }
        return snapshot(
            variantIndex: context.variantIndex,
            variantCount: context.variantCount,
            variantLabel: context.variantLabel
        )
    }

    private func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

private func prepareSharedAudioSession() -> Bool {
    #if os(iOS)
    let session = AVAudioSession.sharedInstance()
    do {
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true, options: [])
        return true
    } catch {
        return false
    }
    #else
    true
    #endif
}
