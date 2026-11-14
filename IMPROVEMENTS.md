# Pointless — Improvement Plan

Proposals for cleaner code, more effective UX, and easier maintenance.
Ordered by priority within each section. Top picks overall: **U1 (progressive
overlay), M1 (AX fixture tests)** — they compound: the pass pipeline is what
makes both the progressive merge and the fixtures clean to build.

---

## UX effectiveness

### U1. Progressive overlay (biggest single win)

Latency is the entire experience for jump-to-click. The current fallback stack
trades latency for coverage — the Safari Start Page worst case (300 ms
enhanced-UI settle + ~900 hit-test probes) approaches "did it hear me?"
territory.

- Show badges for tree-walk results immediately (~50 ms).
- Stream in fallback/hit-test results as they arrive, merging labels without
  re-lettering already-visible badges.
- Converts the ~1 s worst case into perceived-instant.

**Files:** `Navigation/Discovery/ElementDiscovery.swift` (per-pass incremental
callbacks — `scan` already delivers results via completion),
`Navigation/NavigationSession.swift` (merge instead of replace),
`Navigation/ElementOverlay.swift`

### U2. Cursor warp on activation

A successful `AXPress` leaves the pointer where it was — the user loses the
spatial "I am now here" confirmation, and hover-dependent UI misbehaves.
`warpCursor(to:)` already exists for scroll-target cycling; `activate(_:)`
doesn't use it. Warp the cursor to the element on press, or expose a setting.

**Files:** `Navigation/NavigationSession.swift` (`activate`, `warpCursor`)

### U3. Label stability across activations

Sort/assign labels so the same element tends to get the same letter on repeated
activations of the same screen. Muscle memory is the core value proposition of
this tool category.

**Files:** `Navigation/LabelGenerator.swift`

### U4. Scroll mode polish

- Momentum: accelerate deltas on key repeat.
- A visible "scroll mode" indicator beyond the target outline.
- The `d`/`u` half-page keys are undiscoverable — add them to the esc-hint
  capsule.

**Files:** `Navigation/NavigationSession.swift` (`synthesizeScroll`,
`scrollStep`/`scrollPage`, `handleScrollKey`),
`Navigation/ElementOverlay.swift` (`escHint`)

---

## Maintenance

### M1. AX fixture tests (highest-leverage change)

The highest-risk code — element discovery — is untestable because it is welded
to live AX calls. Every bug fixed recently (opaque providers, lazy WebKit
trees, Terminal tab radio buttons) is currently folklore instead of a
regression test.

- Define an `ElementProvider` protocol abstracting AX reads (role, frame,
  children, actions, hit-test).
- Record real AX trees (Safari Start Page, Firefox, Terminal) as JSON fixtures.
- Replay fixtures through the `DiscoveryPass` pipeline in XCTest
  (`Tests/PointlessTests/`) — XCTest works with the installed Xcode toolchain.

### M2. Per-app quirk table

Replace scattered conditionals with a bundle-ID-keyed table declaring:
"needs enhanced UI," "needs hit-test," "needs focused-element fallback,"
"settle delay." Quirks become data (per the project's declarative-over-
imperative rule); adding Chrome/Electron support becomes a table row.

**Files:** `Navigation/Discovery/` (pass `shouldRun` conditions)

### M3. Built-in diagnostics command

Promote the debug instrumentation (role counts, probe stats) into a hidden
"diagnostics" action that runs one scan and dumps a report (frontmost app,
pass-by-pass results, roles, timings). Future bug reports arrive with the data
instead of requiring a debug-logging session over buffered stdout.

**Files:** `Navigation/Discovery/ElementDiscovery.swift`, `App/Logger.swift`

---

## Suggested sequencing

1. **M1** fixture tests on top of the pass pipeline (locks in current behavior
   before changing it)
2. **U1** progressive overlay (incremental pass results → incremental badges)
3. **U2–U4, M2, M3** as independent follow-ups
