# Codex Notch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS utility that shows Codex five-hour and weekly remaining usage around the MacBook notch and expands into a card on click.

**Architecture:** A `CodexUsageProvider` launches `codex app-server --stdio`, performs the JSON-RPC initialization and rate-limit read, and maps the response into a small `UsageSnapshot` model. A main-actor store owns refresh/error state, while DynamicNotchKit provides the compact and expanded window states. AppKit event monitoring collapses the card after an outside click.

**Tech Stack:** Swift 6, SwiftUI, AppKit, DynamicNotchKit, XCTest, XcodeGen.

---

### Task 1: Scaffold and model

**Files:**
- Create: `project.yml`
- Create: `CodexNotch/Models/UsageSnapshot.swift`
- Test: `CodexNotchTests/UsageSnapshotTests.swift`

1. Define primary and secondary quota-window models.
2. Test remaining-percentage clamping and duration-based labels.
3. Generate the Xcode project and run the tests.

### Task 2: Codex app-server provider

**Files:**
- Create: `CodexNotch/Services/CodexUsageProviding.swift`
- Create: `CodexNotch/Services/CodexAppServerUsageProvider.swift`
- Test: `CodexNotchTests/CodexAppServerProtocolTests.swift`

1. Test decoding the documented `account/rateLimits/read` response.
2. Launch `codex app-server --stdio` with `Process` and communicate using JSONL.
3. Handle initialization, request IDs, stderr isolation, timeout, and process cleanup.
4. Run unit tests.

### Task 3: Observable usage state

**Files:**
- Create: `CodexNotch/State/UsageStore.swift`

1. Keep loading, snapshot, last-updated, and error state in one `@Observable` main-actor type.
2. Add manual refresh and a conservative periodic refresh loop.
3. Preserve the last successful snapshot when a refresh fails.

### Task 4: Notch interface and interaction

**Files:**
- Create: `CodexNotch/UI/UsageCompactView.swift`
- Create: `CodexNotch/UI/UsageCardView.swift`
- Create: `CodexNotch/UI/UsageProgressView.swift`
- Create: `CodexNotch/App/NotchController.swift`
- Create: `CodexNotch/App/CodexNotchApp.swift`

1. Render five-hour and weekly usage as compact leading/trailing views.
2. Render reset times, remaining percentages, refresh state, and errors in the expanded card.
3. Configure DynamicNotchKit hover/click behavior.
4. Collapse on outside click and clean up event monitors.
5. Provide a small menu-bar fallback with refresh and quit actions.

### Task 5: Packaging, attribution, and verification

**Files:**
- Create: `CodexNotch/Resources/Info.plist`
- Create: `README.md`
- Create: `THIRD_PARTY_NOTICES.md`

1. Configure the app as an agent application without a Dock icon.
2. Preserve CodexBar and DynamicNotchKit MIT notices.
3. Generate the project, resolve packages, run tests, and build the app.
4. Document setup, behavior, known failure states, and the exact verification commands.
