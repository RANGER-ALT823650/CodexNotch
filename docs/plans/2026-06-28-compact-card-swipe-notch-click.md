# Compact Card, Swipe, and Notch Click Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the expanded card closer to the iPhone Dynamic Island aspect ratio, switch providers with a two-finger horizontal trackpad gesture, and expand by clicking anywhere in the hovered notch interaction region.

**Architecture:** Keep provider selection as local `@State` in `UsageCardView`, but remove the segmented picker and feed horizontal scroll-wheel events through a small AppKit bridge. Keep haptic feedback in DynamicNotchKit and add compact-state click monitors in `NotchController`, using the physical notch geometry reported by `NSScreen` plus the compact side-content width.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSEvent`, DynamicNotchKit, XCTest.

---

### Task 1: Horizontal trackpad switching

**Files:**
- Create: `CodexNotch/UI/HorizontalSwipeDetector.swift`
- Create: `CodexNotchTests/HorizontalSwipeAccumulatorTests.swift`

1. Add failing tests for horizontal dominance, threshold, one-trigger-per-gesture, and reset.
2. Implement a pure accumulator plus an `NSViewRepresentable` local scroll-wheel monitor.
3. Run the focused tests and confirm they pass.

### Task 2: Compact Dynamic Island layout

**Files:**
- Modify: `CodexNotch/UI/UsageCardView.swift`
- Modify: `CodexNotch/UI/AntigravityUsageView.swift`
- Modify: `CodexNotch/UI/UsageProgressView.swift`

1. Change the content size from `370 × 285` to approximately `440 × 150`.
2. Remove the segmented picker and add small provider page indicators.
3. Place Antigravity's two provider groups side by side, with two compact quota cells per group.
4. Add directional transitions and accessibility actions for provider switching.

### Task 3: Click the whole compact notch

**Files:**
- Modify: `CodexNotch/App/NotchController.swift`
- Test: `CodexNotchTests/NotchInteractionGeometryTests.swift`

1. Extract testable compact notch interaction geometry.
2. Install compact-state local/global click monitors while the notch is collapsed.
3. Expand when a click lands in the same compact region whose hover triggers DynamicNotchKit haptics.
4. Swap monitor sets safely during expand, collapse, and shutdown.

### Task 4: Documentation and verification

**Files:**
- Modify: `README.md`

1. Document horizontal swipe and whole-notch click behavior.
2. Explain that this is a standalone macOS app and document stable installation plus launch-at-login.
3. Regenerate the Xcode project, run all tests, build the app, and verify the real notch UI.

