# Antigravity usage first-version implementation plan

**Goal:** Add Antigravity quota data to the existing expanded notch card while preserving the current compact Codex display.

**Source boundary:** Port the minimum local probing and quota-summary parsing needed from CodexBar. Keep CodexBar's MIT attribution in source headers and `THIRD_PARTY_NOTICES.md`. Do not add CodexBarCore as a package dependency and do not read or copy OAuth credentials.

**Data flow:**

1. Probe a running Antigravity app/IDE language-server process.
2. Discover its localhost listening ports with `lsof` and POST to `RetrieveUserQuotaSummary` using its CSRF token.
3. If no app process is usable, reuse a running `agy` CLI or launch one behind `/usr/bin/script` to allocate a pseudo-terminal, then probe its tokenless HTTPS endpoint.
4. Preserve all quota groups and buckets and expose them through a separate observable store.
5. Let the expanded DynamicNotchKit card switch between Codex and Antigravity; keep the compact notch dedicated to Codex in this version.

**Verification:** Unit-test quota parsing and process/port parsing, build and test the macOS app, then exercise the expanded card with live local data when Antigravity is available.

