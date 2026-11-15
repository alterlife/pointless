# Pointless — Improvement Plan

Proposals for cleaner code, more effective UX, and easier maintenance.
Ordered by priority within each section. Top picks overall: **U1 (progressive
overlay), M1 (AX fixture tests)** — they compound: the pass pipeline is what
makes both the progressive merge and the fixtures clean to build.

---

## UX effectiveness

### U1. Progressive overlay (biggest single win)

Badges still wait for the full scan (~200–370 ms typical after the batch-fetch
and pruning work). Showing tree-walk results as soon as that pass finishes and
merging fallback/occlusion results as they land would make activation feel
instant.

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

### M2. Built-in diagnostics command

Promote the debug instrumentation (per-pass element counts and timings,
role counts) into a hidden "diagnostics" action that runs one scan and dumps
a report (frontmost app, pass-by-pass results, roles, timings). Future bug
reports arrive with the data instead of requiring a debug-logging session
over buffered stdout. Could double as the fixture recorder for M1 — serialize
the walked `AXTreeNode` tree to JSON.

**Files:** `Navigation/Discovery/ElementDiscovery.swift`, `App/Logger.swift`

---

## Suggested sequencing

1. **M1** fixture tests on top of the pass pipeline (locks in current behavior
   before changing it)
2. **U1** progressive overlay (incremental pass results → incremental badges)
3. **U2–U4, M2** as independent follow-ups
