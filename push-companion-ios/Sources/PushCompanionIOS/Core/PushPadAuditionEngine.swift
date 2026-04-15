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
    let oneShotSec: Double
    let pressedAt: TimeInterval
    let oneShotBoundaryWorkItem: DispatchWorkItem
    var isPressed: Bool
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

            let oneShotSec = max(0.03, slice.oneShotSec)
            let pressedAt = Date().timeIntervalSinceReferenceDate
            let boundaryWorkItem = DispatchWorkItem { [weak self] in
                self?.handleOneShotBoundary(slot: clampedSlot, pressedAt: pressedAt)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + oneShotSec, execute: boundaryWorkItem)

            activePlaybackBySlot[clampedSlot] = ActivePadPlayback(
                player: player,
                bank: clampedBank,
                slot: clampedSlot,
                startSec: slice.startSec,
                oneShotSec: oneShotSec,
                pressedAt: pressedAt,
                oneShotBoundaryWorkItem: boundaryWorkItem,
                isPressed: true
            )
        } catch {
            return
        }
    }

    func padUp(slot: Int) {
        let clampedSlot = max(0, min(63, slot))
        guard var active = activePlaybackBySlot[clampedSlot] else { return }

        let elapsed = max(0, Date().timeIntervalSinceReferenceDate - active.pressedAt)
        if elapsed >= active.oneShotSec {
            // Hold mode: once past one-shot boundary, release stops immediately.
            stopSlot(clampedSlot)
            return
        }

        // Tap mode: let the one-shot continue until its natural one-shot boundary.
        active.isPressed = false
        activePlaybackBySlot[clampedSlot] = active
    }

    private func stopSlot(_ slot: Int) {
        if let active = activePlaybackBySlot.removeValue(forKey: slot) {
            active.oneShotBoundaryWorkItem.cancel()
            active.player.stop()
        }
    }

    private func handleOneShotBoundary(slot: Int, pressedAt: TimeInterval) {
        guard let active = activePlaybackBySlot[slot] else { return }
        guard abs(active.pressedAt - pressedAt) < 0.000_5 else { return }
        if active.isPressed {
            // Finger is still down at one-shot boundary: switch to hold/sustain behavior.
            return
        }
        stopSlot(slot)
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
    let subWetness: Double
}

final class PushLongStripAuditionEngine {
    private var player: AVAudioPlayer?
    private var activeURL: URL?
    private var subPlayer: AVAudioPlayer?
    private var activeSubURL: URL?
    private var isActiveGesture = false
    private var isLatched = false
    private var variantURLsByBank: [Int: [URL]] = [:]
    private var activeVariantIndex = 0
    private var activeX: Double = 0.5
    private var activeY: Double = 0.5
    private var activeBank = 1
    private var subWetness: Double = 0
    private var latchFadeInSeconds: TimeInterval = 0.12
    private var latchFadeOutSeconds: TimeInterval = 0.18
    private let seekThresholdSeconds = 0.015
    private let variantHysteresis = 0.11

    func setLatched(_ enabled: Bool) -> PushLongStripSnapshot? {
        isLatched = enabled
        if !enabled, !isActiveGesture {
            stopWithFade()
        }
        return currentSnapshot()
    }

    func setWetness(_ value: Double) -> PushLongStripSnapshot? {
        subWetness = clamp01(value)
        if player != nil {
            applyDensityShaping(immediate: false)
        }
        return currentSnapshot()
    }

    func setLatchFadeDurations(fadeIn: Double, fadeOut: Double) -> PushLongStripSnapshot? {
        latchFadeInSeconds = clampFadeDuration(fadeIn)
        latchFadeOutSeconds = clampFadeDuration(fadeOut)
        return currentSnapshot()
    }

    func begin(bank: Int, x: Double, y: Double) -> PushLongStripSnapshot? {
        guard prepareSharedAudioSession() else { return nil }
        guard let context = resolveLongStripContext(
            bank: bank,
            y: y,
            preferredIndex: activeVariantIndex
        ) else { return nil }
        activeBank = context.bank
        activeX = clamp01(x)
        activeY = clamp01(y)
        activeVariantIndex = context.variantIndex

        if activeURL != context.url || player == nil {
            do {
                let next = try AVAudioPlayer(contentsOf: context.url)
                next.numberOfLoops = -1
                next.enableRate = true
                next.prepareToPlay()
                player = next
                activeURL = context.url
                activeVariantIndex = context.variantIndex
            } catch {
                return nil
            }
        }
        prepareSubPlayer(for: context.url)

        guard let player else { return nil }
        isActiveGesture = true

        let target = activeX * max(0.001, player.duration)
        player.currentTime = max(0, min(target, max(0, player.duration - 0.01)))
        alignSubToPrimary()
        applyDensityShaping(immediate: true)

        if !player.isPlaying {
            player.volume = 0
            subPlayer?.volume = 0
            player.play()
            if subWetness > 0.0005, let sub = subPlayer, !sub.isPlaying {
                sub.play()
            }
            applyDensityShaping(immediate: false, fadeDuration: latchFadeInSeconds)
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
        guard let context = resolveLongStripContext(
            bank: bank,
            y: y,
            preferredIndex: activeVariantIndex
        ) else { return nil }
        activeBank = context.bank
        activeX = clamp01(x)
        activeY = clamp01(y)

        if activeURL != context.url {
            return begin(bank: context.bank, x: activeX, y: activeY)
        }
        guard let player else { return nil }

        let target = activeX * max(0.001, player.duration)
        let bounded = max(0, min(target, max(0, player.duration - 0.01)))

        // Keep scrub very responsive without over-seeking.
        if abs(player.currentTime - bounded) > seekThresholdSeconds {
            player.currentTime = bounded
        }
        alignSubToPrimary()
        applyDensityShaping(immediate: true)
        if !player.isPlaying {
            player.volume = 0
            subPlayer?.volume = 0
            player.play()
            if subWetness > 0.0005, let sub = subPlayer, !sub.isPlaying {
                sub.play()
            }
            applyDensityShaping(immediate: false, fadeDuration: latchFadeInSeconds)
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
        guard player != nil || subPlayer != nil else { return }
        let fadeOut = clampFadeDuration(latchFadeOutSeconds)
        player?.setVolume(0, fadeDuration: fadeOut)
        subPlayer?.setVolume(0, fadeDuration: fadeOut)
        let token = activeURL
        let subToken = activeSubURL
        let stopDelay = max(fadeOut + 0.04, 0.08)
        DispatchQueue.main.asyncAfter(deadline: .now() + stopDelay) { [weak self] in
            guard let self, !self.isActiveGesture else { return }
            if self.activeURL == token {
                self.player?.stop()
            }
            if self.activeSubURL == subToken {
                self.subPlayer?.stop()
            }
        }
    }

    private func resolveLongStripContext(bank: Int, y: Double, preferredIndex: Int) -> (
        bank: Int,
        url: URL,
        variantIndex: Int,
        variantCount: Int,
        variantLabel: String
    )? {
        let clampedBank = max(1, min(2, bank))
        let variants = variantsForBank(clampedBank)
        guard !variants.isEmpty else { return nil }
        let index = variantIndex(for: y, count: variants.count, current: preferredIndex)
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
                return name.hasPrefix(prefix.lowercased())
                    && name.hasSuffix(".m4a")
                    && !name.contains("_sub.")
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

    private func variantIndex(for y: Double, count: Int, current: Int) -> Int {
        guard count > 1 else { return 0 }
        let clamped = clamp01(y)
        let candidate = min(count - 1, max(0, Int(round(clamped * Double(count - 1)))))
        let currentClamped = min(count - 1, max(0, current))
        if candidate == currentClamped {
            return currentClamped
        }
        let currentNorm = Double(currentClamped) / Double(count - 1)
        if abs(clamped - currentNorm) < variantHysteresis {
            return currentClamped
        }
        return candidate
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
            isLatched: isLatched,
            subWetness: subWetness
        )
    }

    private func currentSnapshot() -> PushLongStripSnapshot? {
        guard let context = resolveLongStripContext(
            bank: activeBank,
            y: activeY,
            preferredIndex: activeVariantIndex
        ) else {
            return nil
        }
        return snapshot(
            variantIndex: context.variantIndex,
            variantCount: context.variantCount,
            variantLabel: context.variantLabel
        )
    }

    private func prepareSubPlayer(for mainURL: URL) {
        guard let subURL = octaveSubURL(for: mainURL) else {
            subPlayer = nil
            activeSubURL = nil
            return
        }
        if activeSubURL == subURL, subPlayer != nil {
            return
        }
        do {
            let sub = try AVAudioPlayer(contentsOf: subURL)
            sub.numberOfLoops = -1
            sub.enableRate = true
            sub.prepareToPlay()
            subPlayer = sub
            activeSubURL = subURL
        } catch {
            subPlayer = nil
            activeSubURL = nil
        }
    }

    private func alignSubToPrimary() {
        guard let main = player, let sub = subPlayer else { return }
        if abs(sub.currentTime - main.currentTime) > seekThresholdSeconds {
            sub.currentTime = main.currentTime
        }
    }

    private func applyDensityShaping(immediate: Bool, fadeDuration: TimeInterval? = nil) {
        guard let main = player else { return }
        let d = clamp01(activeY)
        let wet = clamp01(subWetness)
        let mainBase = 0.28 + (d * 0.72)
        let mainVolume = Float(mainBase * (1 - (wet * 0.12)))
        let subVolume = Float(mainBase * wet * 0.85)
        let targetRate = Float(0.88 + (d * 0.62))

        main.rate = targetRate
        if immediate {
            main.volume = mainVolume
        } else {
            main.setVolume(mainVolume, fadeDuration: fadeDuration ?? 0.06)
        }

        guard let sub = subPlayer else { return }
        sub.rate = targetRate
        if wet > 0.0005, !sub.isPlaying {
            sub.currentTime = main.currentTime
            sub.play()
        }
        if immediate {
            sub.volume = subVolume
        } else {
            sub.setVolume(subVolume, fadeDuration: fadeDuration ?? 0.08)
        }
    }

    private func octaveSubURL(for mainURL: URL) -> URL? {
        let base = mainURL.deletingPathExtension().lastPathComponent
        let subURL = mainURL.deletingLastPathComponent().appendingPathComponent("\(base)_sub.m4a")
        return FileManager.default.fileExists(atPath: subURL.path) ? subURL : nil
    }

    private func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private func clampFadeDuration(_ value: Double) -> Double {
        min(4.0, max(0.02, value))
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
