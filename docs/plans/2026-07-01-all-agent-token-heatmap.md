# All-Agent Token Heatmap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a native SwiftUI GitHub-style 365-day heatmap for token usage across all locally detected AI agents, using only `mm7894215/TokenTracker`'s one-shot collector.

**Architecture:** `CodexNotch` invokes the pinned TokenTracker CLI with `sync --auto`, so no Dashboard server, menu bar process, WKWebView, or daemon remains resident. The app reads TokenTracker's local `queue.jsonl`, de-duplicates 30-minute buckets by `(source, model, hour_start)`, aggregates them into a compact 365-day snapshot, and renders the snapshot as a third swipeable native card.

**Tech Stack:** Swift 6, SwiftUI, Observation, Foundation `Process`, TokenTracker CLI 0.64.2, XCTest.

---

### Task 1: Define the heatmap data model and parser contract

**Files:**
- Create: `CodexNotch/Models/AgentUsageSnapshot.swift`
- Create: `CodexNotch/Services/AgentUsageProviding.swift`
- Create: `CodexNotchTests/AgentUsageTests.swift`

**Step 1: Write failing parser tests**

Add tests covering duplicate bucket replacement, local-day aggregation, malformed-line tolerance, zero-filled 365-day output, token totals, source counts, and four heat levels.

**Step 2: Run tests to verify failure**

Run: `xcodebuild test -project CodexNotch.xcodeproj -scheme CodexNotch -destination 'platform=macOS'`

Expected: FAIL because the agent usage model and provider do not exist.

**Step 3: Implement the model and protocol**

Create value types with stable day identifiers, `Int64` token totals, precomputed heat levels, source summaries, and a fetched timestamp. Define an async provider protocol matching the existing Codex and Antigravity store boundaries.

**Step 4: Implement the minimal parser**

Decode TokenTracker JSONL rows, skip malformed lines, keep the latest row for each `source|model|hour_start` key, aggregate in the user's calendar, and emit exactly the last 365 calendar days.

**Step 5: Run tests**

Expected: parser tests PASS.

### Task 2: Add the one-shot TokenTracker collector service

**Files:**
- Create: `CodexNotch/Services/AgentTokenTrackerUsageProvider.swift`
- Modify: `CodexNotchTests/AgentUsageTests.swift`
- Modify: `README.md`
- Modify: `THIRD_PARTY_NOTICES.md`

**Step 1: Write failing command-resolution tests**

Verify that `TOKENTRACKER_PATH` and installed binaries take priority, while the fallback is a pinned `npx --yes tokentracker-cli@0.64.2 sync --auto` command. Assert that no `serve`, Dashboard, native TokenTracker app, or WebView command is used.

**Step 2: Run tests to verify failure**

Expected: FAIL because the collector service does not exist.

**Step 3: Implement the collector**

Run the resolved command at utility priority, capture bounded diagnostic output, reject non-zero exits, and then memory-map `~/.tokentracker/tracker/queue.jsonl`. Keep the process one-shot and terminate it when its task is cancelled.

**Step 4: Document prerequisites and licensing**

Document Node.js 20+ / `npx` fallback, `TOKENTRACKER_PATH`, local data path, the pinned collector version, and the fact that no TokenTracker UI/server remains running.

**Step 5: Run tests**

Expected: collector command tests PASS.

### Task 3: Add observable state and app wiring

**Files:**
- Create: `CodexNotch/State/AgentUsageStore.swift`
- Modify: `CodexNotch/App/AppRuntime.swift`
- Modify: `CodexNotch/App/NotchController.swift`
- Modify: `CodexNotch/App/CodexNotchApp.swift`

**Step 1: Add the store**

Mirror the existing stores with explicit loading, snapshot, error, and cancellation states. Do not add a background timer: collection runs only when the heatmap is selected or explicitly refreshed.

**Step 2: Wire root ownership**

Create one `AgentUsageStore` in `AppRuntime`, inject it through `NotchController`, and include it in menu-bar refresh/error state.

**Step 3: Build**

Run: `xcodebuild build -project CodexNotch.xcodeproj -scheme CodexNotch -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED.

### Task 4: Build the native SwiftUI heatmap card

**Files:**
- Create: `CodexNotch/UI/AgentUsageHeatmapView.swift`
- Modify: `CodexNotch/UI/UsageCardView.swift`
- Modify: `CodexNotchTests/HorizontalSwipeAccumulatorTests.swift`

**Step 1: Write failing provider-cycle tests**

Cover left and right cycling across Codex, Antigravity, and All Agents.

**Step 2: Implement the heatmap view**

Use small stable `ForEach` cells arranged into week columns, month labels, weekday hints, accessible token descriptions, loading/error/empty states, and no embedded web content.

**Step 3: Extend the card carousel**

Add the third provider, icon, title, indicator, refresh action, footer metadata, accessibility actions, and cyclic swipe selection. Trigger the one-shot collector only when the All Agents page is selected.

**Step 4: Run tests and build**

Expected: all tests PASS and BUILD SUCCEEDED.

### Task 5: Verify runtime behavior and resource constraints

**Files:**
- Modify if needed: implementation files above

**Step 1: Run the full test suite**

Run: `xcodebuild test -project CodexNotch.xcodeproj -scheme CodexNotch -destination 'platform=macOS'`

Expected: TEST SUCCEEDED.

**Step 2: Build Release**

Run: `xcodebuild build -project CodexNotch.xcodeproj -scheme CodexNotch -configuration Release -destination 'platform=macOS' -derivedDataPath .build/DerivedData`

Expected: BUILD SUCCEEDED.

**Step 3: Verify process behavior**

Launch the app, select the All Agents card, wait for collection, and confirm that `tokentracker`/`node` exits after `sync --auto`. Confirm no process is listening on TokenTracker's Dashboard ports and no WKWebView dependency was added.

**Step 4: Verify the rendered card**

Confirm a 365-day contribution grid appears, tooltips expose date/token counts, manual refresh works, and swiping cycles through all three cards.
