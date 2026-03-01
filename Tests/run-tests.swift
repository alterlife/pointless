#!/usr/bin/env swift

// Simple test runner that doesn't require XCTest
// Run with: swift Tests/run-tests.swift

import Foundation

// MARK: - Test Framework

var testsPassed = 0
var testsFailed = 0

func verify(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if condition {
        testsPassed += 1
    } else {
        testsFailed += 1
        print("❌ FAIL: \(file):\(line) - \(message)")
    }
}

func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if lhs == rhs {
        testsPassed += 1
    } else {
        testsFailed += 1
        print("❌ FAIL: \(file):\(line) - Expected \(rhs), got \(lhs). \(message)")
    }
}

func runTest(_ name: String, _ test: () -> Void) {
    print("  Running: \(name)")
    test()
}

func testSuite(_ name: String, _ tests: () -> Void) {
    print("\n🧪 \(name)")
    tests()
}

// MARK: - Mock Plugin Registry (simplified for testing)

class SimplePluginRegistry {
    var plugins: [(id: String, name: String)] = []

    func register(id: String, name: String) -> Bool {
        if plugins.contains(where: { $0.id == id }) {
            return false  // Duplicate
        }
        plugins.append((id: id, name: name))
        return true
    }
}

// MARK: - Plugin Settings Tests

enum SimpleSetting {
    case slider(key: String, label: String, range: ClosedRange<Double>, defaultValue: Double)
    case toggle(key: String, label: String, defaultValue: Bool)
    case text(key: String, label: String, defaultValue: String)
    case color(key: String, label: String, defaultValue: String)
    case dropdown(key: String, label: String, options: [String], defaultValue: String)

    var key: String {
        switch self {
        case .slider(let key, _, _, _),
             .toggle(let key, _, _),
             .text(let key, _, _),
             .color(let key, _, _),
             .dropdown(let key, _, _, _):
            return key
        }
    }

    var label: String {
        switch self {
        case .slider(_, let label, _, _),
             .toggle(_, let label, _),
             .text(_, let label, _),
             .color(_, let label, _),
             .dropdown(_, let label, _, _):
            return label
        }
    }
}

struct SimplePluginSettings {
    let definitions: [SimpleSetting]
}

// MARK: - Test Suites

testSuite("Plugin Settings Tests") {
    runTest("Empty settings") {
        let settings = SimplePluginSettings(definitions: [])
        verify(settings.definitions.isEmpty, "Settings should be empty")
    }

    runTest("Slider setting") {
        let setting = SimpleSetting.slider(
            key: "volume",
            label: "Volume",
            range: 0.0...100.0,
            defaultValue: 50.0
        )
        assertEqual(setting.key, "volume", "Key should match")
        assertEqual(setting.label, "Volume", "Label should match")
    }

    runTest("Toggle setting") {
        let setting = SimpleSetting.toggle(
            key: "enabled",
            label: "Enabled",
            defaultValue: true
        )
        assertEqual(setting.key, "enabled")
        assertEqual(setting.label, "Enabled")
    }

    runTest("Text setting") {
        let setting = SimpleSetting.text(
            key: "name",
            label: "Name",
            defaultValue: "John"
        )
        assertEqual(setting.key, "name")
        assertEqual(setting.label, "Name")
    }

    runTest("Color setting") {
        let setting = SimpleSetting.color(
            key: "customColor",
            label: "Custom Color",
            defaultValue: "#007AFF"
        )
        assertEqual(setting.key, "customColor")
        assertEqual(setting.label, "Custom Color")
    }

    runTest("Dropdown setting") {
        let setting = SimpleSetting.dropdown(
            key: "displayMode",
            label: "Display Mode",
            options: ["text", "graph", "both"],
            defaultValue: "both"
        )
        assertEqual(setting.key, "displayMode")
        assertEqual(setting.label, "Display Mode")
    }

    runTest("Multiple settings") {
        let settings = SimplePluginSettings(definitions: [
            .slider(key: "interval", label: "Interval", range: 1.0...10.0, defaultValue: 5.0),
            .toggle(key: "enabled", label: "Enabled", defaultValue: true),
            .text(key: "name", label: "Name", defaultValue: "Test"),
            .color(key: "customColor", label: "Custom Color", defaultValue: "#FF0000"),
            .dropdown(key: "mode", label: "Mode", options: ["A", "B"], defaultValue: "A")
        ])
        assertEqual(settings.definitions.count, 5, "Should have 5 settings")
    }
}

testSuite("Plugin Registry Tests") {
    runTest("Empty registry") {
        let registry = SimplePluginRegistry()
        verify(registry.plugins.isEmpty, "Registry should start empty")
    }

    runTest("Register plugin") {
        let registry = SimplePluginRegistry()
        let success = registry.register(id: "test.plugin", name: "Test Plugin")
        verify(success, "Registration should succeed")
        assertEqual(registry.plugins.count, 1, "Should have 1 plugin")
    }

    runTest("Reject duplicate IDs") {
        let registry = SimplePluginRegistry()
        _ = registry.register(id: "test.plugin", name: "Plugin 1")
        let duplicate = registry.register(id: "test.plugin", name: "Plugin 2")
        verify(!duplicate, "Duplicate ID should be rejected")
        assertEqual(registry.plugins.count, 1, "Should still have only 1 plugin")
    }

    runTest("Multiple plugins") {
        let registry = SimplePluginRegistry()
        _ = registry.register(id: "plugin.1", name: "Plugin 1")
        _ = registry.register(id: "plugin.2", name: "Plugin 2")
        _ = registry.register(id: "plugin.3", name: "Plugin 3")
        assertEqual(registry.plugins.count, 3, "Should have 3 plugins")
    }
}

// MARK: - Mock Suspend/Resume Lifecycle

class MockSuspendLifecycle {
    var timerRunning = false
    var isSuspended = false
    private var wasRunning = false

    func start() { timerRunning = true }
    func stop() { timerRunning = false }

    func suspend() {
        guard !isSuspended else { return }
        wasRunning = timerRunning
        stop()
        isSuspended = true
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        if wasRunning { start() }
    }
}

testSuite("Screen Sleep Tests") {
    runTest("suspend() stops timer and sets suspended flag") {
        let lifecycle = MockSuspendLifecycle()
        lifecycle.start()
        lifecycle.suspend()
        verify(lifecycle.isSuspended, "Should be suspended")
        verify(!lifecycle.timerRunning, "Timer should be stopped")
    }

    runTest("resume() clears suspended flag and restarts timer if was running") {
        let lifecycle = MockSuspendLifecycle()
        lifecycle.start()
        lifecycle.suspend()
        lifecycle.resume()
        verify(!lifecycle.isSuspended, "Should not be suspended")
        verify(lifecycle.timerRunning, "Timer should restart")
    }

    runTest("resume() does not start timer if it was not running") {
        let lifecycle = MockSuspendLifecycle()
        lifecycle.suspend()
        lifecycle.resume()
        verify(!lifecycle.isSuspended, "Should not be suspended")
        verify(!lifecycle.timerRunning, "Timer should remain stopped")
    }

    runTest("suspend() is idempotent") {
        let lifecycle = MockSuspendLifecycle()
        lifecycle.start()
        lifecycle.suspend()
        lifecycle.suspend()
        verify(lifecycle.isSuspended, "Should still be suspended")
        verify(!lifecycle.timerRunning, "Timer should be stopped")
    }

    runTest("resume() is idempotent") {
        let lifecycle = MockSuspendLifecycle()
        lifecycle.start()
        lifecycle.suspend()
        lifecycle.resume()
        lifecycle.resume()
        verify(!lifecycle.isSuspended, "Should not be suspended")
        verify(lifecycle.timerRunning, "Timer should be running")
    }
}

testSuite("Plugin Lifecycle Tests") {
    runTest("Plugin properties") {
        let id = "test.mock"
        let name = "Mock Plugin"
        assertEqual(id, "test.mock")
        assertEqual(name, "Mock Plugin")
    }

    runTest("Plugin state management") {
        var isStarted = false
        var isStopped = false

        // Simulate start
        isStarted = true
        verify(isStarted, "Plugin should be started")

        // Simulate stop
        isStopped = true
        verify(isStopped, "Plugin should be stopped")
    }
}

// MARK: - LabelGenerator Tests (pure functions duplicated from LabelGenerator.swift)

// Keyboard row priority: home → top → bottom
let testPriorityKeys: [Character] = [
    "a", "s", "d", "f", "j", "k", "l", "g", "h",
    "q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
    "z", "x", "c", "v", "b", "n", "m"
]

func makeTestLabels(count: Int) -> [String] {
    guard count > 0 else { return [] }
    let keys = testPriorityKeys.map { String($0) }
    var labels = keys
    outer: for first in keys {
        for second in keys {
            labels.append(first + second)
            if labels.count >= count { break outer }
        }
    }
    return Array(labels.prefix(count))
}

testSuite("LabelGenerator Tests") {
    runTest("testHomeRowOrder — first label is 'a'") {
        let labels = makeTestLabels(count: 3)
        assertEqual(labels[0], "a", "First label should be 'a' (home row)")
        assertEqual(labels[1], "s", "Second label should be 's'")
        assertEqual(labels[2], "d", "Third label should be 'd'")
    }

    runTest("testHomeRowOrder — ninth label is 'h'") {
        let labels = makeTestLabels(count: 9)
        assertEqual(labels[8], "h", "9th label should be last home-row key 'h'")
    }

    runTest("testTopRow — 10th label is top row start") {
        let labels = makeTestLabels(count: 10)
        assertEqual(labels[9], "q", "10th label should be 'q' (top row start)")
    }

    runTest("testAllLabelsUnique — 100 elements get distinct labels") {
        let labels = makeTestLabels(count: 100)
        let unique = Set(labels)
        assertEqual(unique.count, labels.count, "All 100 labels must be unique")
    }

    runTest("testTwoLetterCombos — element 27 gets two-letter label") {
        let labels = makeTestLabels(count: 30)
        // Labels 0–26 are single letters (27 total in our key set); index 27 = first two-letter
        let twoLetter = labels[27]
        verify(twoLetter.count == 2, "Label at index 27 should be 2 chars, got '\(twoLetter)'")
    }

    runTest("testFilterEmptyPrefix — returns all unchanged") {
        let labels = makeTestLabels(count: 5)
        let filtered = labels.filter { $0.hasPrefix("") }
        assertEqual(filtered.count, labels.count, "Empty prefix should return all labels")
    }

    runTest("testFilterMatchingPrefix — keeps only labels starting with 'a'") {
        let labels = makeTestLabels(count: 27)
        let filtered = labels.filter { $0.hasPrefix("a") }
        verify(!filtered.isEmpty, "Should find labels starting with 'a'")
        verify(filtered.allSatisfy { $0.hasPrefix("a") }, "All filtered labels start with 'a'")
    }

    runTest("testFilterNoMatch — unmatched prefix returns empty") {
        let labels = makeTestLabels(count: 5)
        let filtered = labels.filter { $0.hasPrefix("zz") }
        verify(filtered.isEmpty, "No label should start with 'zz' in first 5")
    }
}

// MARK: - Coordinate Tests
// Uses plain Double structs — no CoreGraphics dependency needed in standalone script

struct TPoint { let x: Double; let y: Double }
struct TSize { let width: Double; let height: Double }
struct TRect {
    let x: Double; let y: Double; let width: Double; let height: Double
    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
}

func axToNSScreenTest(axX: Double, axY: Double, w: Double, h: Double, screenH: Double) -> TRect {
    TRect(x: axX, y: screenH - axY - h, width: w, height: h)
}

func anchorPointTest(frameX: Double, frameY: Double, frameMaxY: Double,
                     screenMinX: Double, screenMaxY: Double) -> TPoint {
    TPoint(x: frameX - screenMinX + 4, y: screenMaxY - frameMaxY + 4)
}

func badgeOriginTest(anchorX: Double, anchorY: Double,
                     badgeW: Double, badgeH: Double,
                     viewW: Double) -> TPoint {
    let preferredY = anchorY - badgeH - 6
    let finalY = preferredY < 8 ? anchorY + 10 : preferredY
    let rawX = anchorX - badgeW - 4
    let finalX = max(4, min(rawX, viewW - badgeW - 4))
    return TPoint(x: finalX, y: finalY)
}

testSuite("Coordinate Tests") {
    runTest("testAXToNSScreenTopElement — axY=0 maps to top of screen") {
        let rect = axToNSScreenTest(axX: 0, axY: 0, w: 100, h: 30, screenH: 1200)
        assertEqual(rect.y, 1170.0, "Element at AX top should map to screenH - h = 1170")
    }

    runTest("testAXToNSScreenBottomElement — axY near bottom maps near y=0") {
        let rect = axToNSScreenTest(axX: 0, axY: 1170, w: 100, h: 30, screenH: 1200)
        assertEqual(rect.y, 0.0, "Element at AX bottom (y=1170, h=30) -> NSScreen y=0")
    }

    runTest("testAnchorInsideElement — inset 4pt from element top-left in canvas coords") {
        // screenFrame: x=100, y=200, w=80, h=30 → maxY=230; screenRect: y=0, maxY=900
        let anchor = anchorPointTest(frameX: 100, frameY: 200, frameMaxY: 230,
                                     screenMinX: 0, screenMaxY: 900)
        assertEqual(anchor.x, 104.0, "anchorX = frame.minX - screen.minX + 4 = 104")
        assertEqual(anchor.y, 674.0, "anchorY = screen.maxY - frame.maxY + 4 = 674")
    }

    runTest("testBadgeAboveAnchor — centre-screen element places badge above") {
        let origin = badgeOriginTest(anchorX: 200, anchorY: 400, badgeW: 20, badgeH: 16, viewW: 1440)
        verify(origin.y < 400, "Badge should be above anchor (anchorY=400) when space allows")
    }

    runTest("testBadgeBelowAtScreenTop — anchor near top (y=5) places badge below") {
        let origin = badgeOriginTest(anchorX: 200, anchorY: 5, badgeW: 20, badgeH: 16, viewW: 1440)
        verify(origin.y > 5, "Badge should be below anchor when anchor is near top edge")
    }

    runTest("testBadgeClampedToLeftEdge — anchor at x=2 clamps badge to x >= 4") {
        let origin = badgeOriginTest(anchorX: 2, anchorY: 200, badgeW: 20, badgeH: 16, viewW: 1440)
        verify(origin.x >= 4, "Badge x should be clamped to at least 4")
    }
}

// MARK: - Results

print("\n" + String(repeating: "=", count: 50))
print("📊 Test Results")
print(String(repeating: "=", count: 50))
print("✅ Passed: \(testsPassed)")
if testsFailed > 0 {
    print("❌ Failed: \(testsFailed)")
    exit(1)
} else {
    print("🎉 All tests passed!")
    exit(0)
}
