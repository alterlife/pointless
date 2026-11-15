# Pointless — Improvement Plan

Proposals for cleaner code, more effective UX, and easier maintenance.
Ordered by priority within each section.

---

## UX effectiveness

### U1. Cursor warp on activation

A successful `AXPress` leaves the pointer where it was — the user loses the
spatial "I am now here" confirmation, and hover-dependent UI misbehaves.
`warpCursor(to:)` already exists for scroll-target cycling; `activate(_:)`
doesn't use it. Warp the cursor to the element on press, or expose a setting.

**Files:** `Navigation/NavigationSession.swift` (`activate`, `warpCursor`)

### U2. Label stability across activations

Sort/assign labels so the same element tends to get the same letter on repeated
activations of the same screen. Muscle memory is the core value proposition of
this tool category.

**Files:** `Navigation/LabelGenerator.swift`

### U3. Scroll mode leftovers

- The `d`/`u` half-page keys are undiscoverable — add them to the hint capsule.
- A persistent "scroll mode" indicator beyond the target outline may still help
  in windows where the outline is suppressed or ambiguous.

**Files:** `Navigation/NavigationSession+Scrolling.swift`,
`Navigation/ElementOverlay.swift` (`escHint`)

---

## Maintenance

### M1. Built-in diagnostics command

Promote the debug instrumentation (per-pass element counts and timings,
role counts) into a hidden "diagnostics" action that runs one scan and dumps
a report (frontmost app, pass-by-pass results, roles, timings). Future bug
reports arrive with the data instead of requiring a debug-logging session
over buffered stdout. Could double as a fixture recorder — serialize the
walked `AXTreeNode` tree to JSON for `DiscoveryFixtureTests`.

**Files:** `Navigation/Discovery/ElementDiscovery.swift`, `App/Logger.swift`

---

## Known limitations

- **Electron/Chromium inner scrollers**: apps like Devin expose only a
  whole-window `AXWebArea` — inner panes have no AX scroll representation, so
  scroll mode can't outline them. Scroll events still land on whatever is
  under the cursor.

## Suggested sequencing

1. **U1** cursor warp (small, self-contained)
2. **U2** label stability (bigger, core to the product)
3. **U3, M1** as independent follow-ups
