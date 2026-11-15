import XCTest
@testable import PointlessCore
import CoreGraphics

/// Replays synthetic AX trees through the real DiscoveryPass pipeline.
final class DiscoveryFixtureTests: XCTestCase {
  private let windowFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)

  private func context(
    app: FixtureAXNode, window: FixtureAXNode,
    mode: ScanMode = .interactive,
    roles: Set<String>? = nil
  ) -> DiscoveryContext {
    DiscoveryContext(
      app: app, window: window,
      windowFrame: windowFrame,
      primaryScreenHeight: NSScreen.screens[0].frame.height,
      screens: NSScreen.screens,
      mode: mode,
      roles: roles ?? (mode == .interactive
        ? ElementDiscovery.interactiveRoles : ElementDiscovery.scrollableRoles),
      isCancelled: { false }
    )
  }

  private func scan(
    window: FixtureAXNode, app: FixtureAXNode? = nil,
    mode: ScanMode = .interactive
  ) -> (DiscoveryState, DiscoveryContext) {
    let appNode = app ?? FixtureAXNode(role: "AXApplication")
    let ctx = context(app: appNode, window: window, mode: mode)
    let state = DiscoveryState()
    TreeWalkPass().run(state: state, context: ctx)
    PressFallbackPass().run(state: state, context: ctx)
    return (state, ctx)
  }

  private func button(_ frame: CGRect = CGRect(x: 10, y: 10, width: 80, height: 30)) -> FixtureAXNode {
    FixtureAXNode(role: "AXButton", frame: frame)
  }

  // MARK: tree walk

  func testRoleMatchedElementBecomesResult() {
    let window = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    window.add(button())
    let (state, _) = scan(window: window)
    XCTAssertEqual(state.results.count, 1)
    XCTAssertEqual(state.results[0].role, "AXButton")
  }

  func testHiddenAndDisabledElementsAreSkipped() {
    let window = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    let hidden = button()
    hidden.isHidden = true
    let disabled = button(CGRect(x: 10, y: 60, width: 80, height: 30))
    disabled.isEnabled = false
    let visible = button(CGRect(x: 10, y: 110, width: 80, height: 30))
    window.add(hidden)
    window.add(disabled)
    window.add(visible)
    let (state, _) = scan(window: window)
    XCTAssertEqual(state.results.count, 1)
    XCTAssertTrue(state.results[0].element.isSameElement(as: visible))
  }

  func testOffscreenSubtreeIsNotVisited() {
    let window = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    // Group entirely below the window — its button must never be reached.
    let offscreen = FixtureAXNode(
      role: "AXGroup",
      frame: CGRect(x: 0, y: -2000, width: 500, height: 500)
    )
    offscreen.add(button())
    window.add(offscreen)
    window.add(button(CGRect(x: 10, y: 400, width: 80, height: 30)))
    let (state, _) = scan(window: window)
    XCTAssertEqual(state.results.count, 1)
    XCTAssertEqual(state.visitedCount, 2) // window + visible button
  }

  func testMissingFrameStillDescends() {
    let window = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    let noFrame = FixtureAXNode(role: "AXGroup", frame: nil)
    noFrame.add(button())
    window.add(noFrame)
    let (state, _) = scan(window: window)
    XCTAssertEqual(state.results.count, 1)
  }

  // MARK: press fallback

  func testSparsePressableGroupIsAdopted() {
    let window = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    // A few real targets keep the eligible set small and mostly non-pressable.
    for i in 0..<5 { window.add(button(CGRect(x: 10, y: 10 + i * 40, width: 80, height: 30))) }
    let clickable = FixtureAXNode(
      role: "AXGroup", frame: CGRect(x: 300, y: 10, width: 80, height: 30)
    )
    clickable.supportsPress = true
    window.add(clickable)
    let (state, _) = scan(window: window)
    XCTAssertEqual(state.results.count, 6)
    XCTAssertTrue(state.results.contains { $0.element.isSameElement(as: clickable) })
  }

  func testPressEverythingTreeDropsFallbackCandidates() {
    let window = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    // Gecko-style: dozens of non-matched nodes, nearly all pressable.
    for i in 0..<40 {
      let group = FixtureAXNode(
        role: "AXGroup",
        frame: CGRect(x: 10, y: 10 + i * 20, width: 100, height: 16)
      )
      group.supportsPress = i % 10 != 0 // 90% pressable
      window.add(group)
    }
    window.add(button(CGRect(x: 500, y: 10, width: 80, height: 30)))
    let (state, _) = scan(window: window)
    // Only the real button survives — 36 pressable groups are noise.
    XCTAssertEqual(state.results.count, 1)
    XCTAssertEqual(state.results[0].role, "AXButton")
  }

  func testMatchedRoleSkipsPressCheck() {
    let window = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    let matched = button()
    window.add(matched)
    let (state, _) = scan(window: window)
    // The window root is fallback-eligible; the matched button is never probed.
    XCTAssertEqual(window.pressCheckCount, 1)
    XCTAssertEqual(matched.pressCheckCount, 0)
    XCTAssertEqual(state.fallbackEligibleCount, 1)
  }

  // MARK: occlusion

  func testOcclusionDropsUnreachableElement() {
    let window = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    let target = button()
    window.add(target)
    let app = FixtureAXNode(role: "AXApplication")
    // Hit-test resolves to an unrelated node — nothing of the target is painted.
    let other = FixtureAXNode(role: "AXGroup")
    app.hitTest = { _, _ in other }
    let ctx = context(app: app, window: window)
    let state = DiscoveryState()
    TreeWalkPass().run(state: state, context: ctx)
    PressFallbackPass().run(state: state, context: ctx)
    OcclusionPass().run(state: state, context: ctx)
    XCTAssertTrue(state.results.isEmpty)
  }

  func testOcclusionKeepsSelfAndDescendantHits() {
    let window = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    let target = button()
    let label = FixtureAXNode(role: "AXStaticText")
    target.add(label)
    window.add(target)
    let app = FixtureAXNode(role: "AXApplication")
    app.hitTest = { _, _ in label } // deepest hit is a child of the target
    let ctx = context(app: app, window: window)
    let state = DiscoveryState()
    TreeWalkPass().run(state: state, context: ctx)
    PressFallbackPass().run(state: state, context: ctx)
    OcclusionPass().run(state: state, context: ctx)
    XCTAssertEqual(state.results.count, 1)
  }

  func testOcclusionSkipsLargeElements() {
    let window = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    let big = button(CGRect(x: 0, y: 0, width: 900, height: 700))
    window.add(big)
    let app = FixtureAXNode(role: "AXApplication")
    app.hitTest = { _, _ in nil } // would fail if probed
    let ctx = context(app: app, window: window)
    let state = DiscoveryState()
    TreeWalkPass().run(state: state, context: ctx)
    PressFallbackPass().run(state: state, context: ctx)
    OcclusionPass().run(state: state, context: ctx)
    XCTAssertEqual(state.results.count, 1)
  }

  // MARK: focused-element fallback

  func testFocusedElementFallbackWalksContentRoot() {
    // Broken window: AXWindow exposes no children (Firefox/Mullvad shape).
    let brokenWindow = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    let scrollArea = FixtureAXNode(role: "AXScrollArea", frame: windowFrame)
    let group = FixtureAXNode(role: "AXGroup", frame: windowFrame)
    scrollArea.add(group)
    let focused = button()
    group.add(focused)
    group.add(button(CGRect(x: 10, y: 300, width: 80, height: 30)))
    let app = FixtureAXNode(role: "AXApplication")
    app.focusedUIElement = focused

    let ctx = context(app: app, window: brokenWindow)
    let state = DiscoveryState()
    TreeWalkPass().run(state: state, context: ctx)
    let fallback = FocusedElementFallbackPass()
    XCTAssertTrue(fallback.shouldRun(state: state, context: ctx))
    fallback.run(state: state, context: ctx)

    XCTAssertEqual(state.results.count, 2)
    XCTAssertTrue(state.results.allSatisfy { $0.role == "AXButton" })
  }

  func testFocusedElementFallbackSkipsWhenWindowIsHealthy() {
    let window = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    for i in 0..<6 { window.add(button(CGRect(x: 10, y: 10 + i * 40, width: 80, height: 30))) }
    let app = FixtureAXNode(role: "AXApplication")
    app.focusedUIElement = window
    let ctx = context(app: app, window: window)
    let state = DiscoveryState()
    TreeWalkPass().run(state: state, context: ctx)
    XCTAssertFalse(FocusedElementFallbackPass().shouldRun(state: state, context: ctx))
  }

  // MARK: scroll mode

  func testScrollModeDiscoversScrollArea() {
    let window = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    let scrollArea = FixtureAXNode(role: "AXScrollArea", frame: windowFrame)
    scrollArea.add(FixtureAXNode(role: "AXStaticText", frame: windowFrame))
    window.add(scrollArea)
    let app = FixtureAXNode(role: "AXApplication")
    let ctx = context(app: app, window: window, mode: .scrollable)
    let state = DiscoveryState()
    TreeWalkPass().run(state: state, context: ctx)
    XCTAssertEqual(state.results.count, 1)
    XCTAssertEqual(state.results[0].role, "AXScrollArea")
  }

  // MARK: hit-test pass

  func testHitTestPassGroupsByClimbedAncestor() {
    let window = FixtureAXNode(role: "AXWindow", frame: windowFrame)
    // Opaque provider present, no web area — Safari Start Page shape.
    let opaque = FixtureAXNode(
      role: "AXOpaqueProviderGroup",
      frame: CGRect(x: 0, y: 0, width: 1000, height: 800)
    )
    window.add(opaque)
    let app = FixtureAXNode(role: "AXApplication")
    let tile = FixtureAXNode(role: "AXButton", frame: CGRect(x: 40, y: 40, width: 100, height: 100))
    let icon = FixtureAXNode(role: "AXImage")
    tile.add(icon)
    app.hitTest = { _, _ in icon }
    let ctx = context(app: app, window: window)
    let state = DiscoveryState()
    TreeWalkPass().run(state: state, context: ctx)
    PressFallbackPass().run(state: state, context: ctx)
    HitTestPass().run(state: state, context: ctx)
    XCTAssertEqual(state.results.count, 1)
    XCTAssertEqual(state.results[0].role, "AXButton")
    XCTAssertEqual(state.results[0].groupingAncestor, .hitTestParent(tile.axIdentity))
  }
}
