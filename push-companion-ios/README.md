# Push Companion iOS (iPad Native)

This module contains the native iPad companion app source for the harness Push-deck lane.

## What is included

- `Deck` tab:
  - 8x8 multi-touch pad surface with down/up semantics and pressure-to-velocity.
  - Hybrid timing control: `Immediate` or `Quantized`.
  - Quantized interval modal.
  - Main bank (1/2/3) and choir bank (1/2/3) selectors.
  - 8 macro lanes mapped for dynamic/static/choir/all-mode controls.
  - Status chips + action ticker.
- `Notes` tab:
  - Local editable performance notes/checklist content.
  - Persisted on-device with `UserDefaults`.
- Connectivity:
  - Persistent 32-hex local controller ID (no login/token flow).
  - Default backend host set to `letgo-fe0a.onrender.com` with manual override.
  - WebSocket sends `push_deck_event` envelopes to `/ws/device/{controllerID}`.

## Integration

1. Create a new iPad SwiftUI app target in Xcode.
2. Add all files from `push-companion-ios/Sources/PushCompanionIOS` into that target.
3. Set the app entry point to `PushCompanionIOSApp.swift`.
4. Run on iPadOS (landscape-first).

The harness side already trusts/filters this lane via:
- `Enable Push Control` toggle.
- Trusted controller list in Setup.
- Hard block on commit-class actions from Push lane.
