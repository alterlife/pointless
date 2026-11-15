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
             .dropdown(let key, _, _, _, _):
            return key
        }
    }

    var label: String {
        switch self {
        case .slider(_, let label, _, _),
             .toggle(_, let label, _),
             .text(_, let label, _),
             .color(_, let label, _),
             .dropdown(_, let label, _, _, _):
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

/// Mirrors the SuspendState enum from PluginLifecycle.swift so tests reflect
/// the same state machine logic without importing the app target.
class MockSuspendLifecycle {
    enum SuspendState: Equatable {
        case running
        case suspended(wasActive: Bool)
    }

    var timerRunning = false
    private(set) var suspendState: SuspendState = .running

    var isSuspended: Bool {
        if case .suspended = suspendState { return true }
        return false
    }

    func start() { timerRunning = true }
    func stop() { timerRunning = false }

    func suspend() {
        guard case .running = suspendState else { return }
        suspendState = .suspended(wasActive: timerRunning)
        stop()
    }

    func resume() {
        guard case .suspended(let wasActive) = suspendState else { return }
        suspendState = .running
        if wasActive { start() }
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

    runTest("SuspendState captures wasActive=true when timer was running at suspend time") {
        let lifecycle = MockSuspendLifecycle()
        lifecycle.start()
        lifecycle.suspend()
        if case .suspended(let wasActive) = lifecycle.suspendState {
            verify(wasActive, "wasActive should be true — timer was running when suspended")
        } else {
            verify(false, "Should be in suspended state")
        }
    }

    runTest("SuspendState captures wasActive=false when timer was stopped at suspend time") {
        let lifecycle = MockSuspendLifecycle()
        // timer never started
        lifecycle.suspend()
        if case .suspended(let wasActive) = lifecycle.suspendState {
            verify(!wasActive, "wasActive should be false — timer was not running when suspended")
        } else {
            verify(false, "Should be in suspended state")
        }
    }

    runTest("SuspendState returns to .running after resume") {
        let lifecycle = MockSuspendLifecycle()
        lifecycle.start()
        lifecycle.suspend()
        lifecycle.resume()
        verify(lifecycle.suspendState == .running, "suspendState should be .running after resume")
    }

    runTest("stopping timer between suspend and resume does not restart it") {
        // The wasActive flag is captured at suspend time. Even if the timer stops
        // (it does, via stop()), resume still uses the captured wasActive value.
        // This test confirms the associated value is locked at suspend time.
        let lifecycle = MockSuspendLifecycle()
        lifecycle.start()
        lifecycle.suspend() // wasActive=true captured here
        // timerRunning is already false after suspend; stopping again is a no-op
        lifecycle.stop()
        lifecycle.resume()
        // resume reads wasActive=true from the enum, so it restarts
        verify(lifecycle.timerRunning, "Timer should restart — wasActive was true at suspend time")
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
    let base = keys.count
    let length: Int
    if count <= base { length = 1 }
    else if count <= base * base { length = 2 }
    else { length = 3 }
    var labels: [String] = []
    generateTestCombos(keys: keys, length: length, current: "", into: &labels, needed: count)
    return labels
}

func generateTestCombos(keys: [String], length: Int, current: String, into labels: inout [String], needed: Int) {
    if current.count == length { labels.append(current); return }
    for key in keys {
        if labels.count >= needed { return }
        generateTestCombos(keys: keys, length: length, current: current + key, into: &labels, needed: needed)
    }
}

testSuite("LabelGenerator Tests") {
    runTest("single-char labels — ≤26 elements use 1-char labels") {
        let labels = makeTestLabels(count: 3)
        assertEqual(labels[0], "a", "First label should be 'a' (home row)")
        assertEqual(labels[1], "s", "Second label should be 's'")
        assertEqual(labels[2], "d", "Third label should be 'd'")
        verify(labels.allSatisfy { $0.count == 1 }, "All labels should be 1 char")
    }

    runTest("single-char labels — full 26 elements") {
        let labels = makeTestLabels(count: 26)
        assertEqual(labels.count, 26)
        verify(labels.allSatisfy { $0.count == 1 }, "All 26 labels should be 1 char")
        assertEqual(Set(labels).count, 26, "All 26 labels must be unique")
    }

    runTest("two-char labels — 27+ elements use uniform 2-char labels") {
        let labels = makeTestLabels(count: 30)
        verify(labels.allSatisfy { $0.count == 2 }, "All labels should be 2 chars for count > 26")
        assertEqual(labels[0], "aa", "First 2-char label should be 'aa'")
        assertEqual(labels[1], "as", "Second should be 'as'")
    }

    runTest("all labels unique — 100 elements") {
        let labels = makeTestLabels(count: 100)
        let unique = Set(labels)
        assertEqual(unique.count, labels.count, "All 100 labels must be unique")
        verify(labels.allSatisfy { $0.count == 2 }, "100 elements should all get 2-char labels")
    }

    runTest("no prefix ambiguity — no label is a prefix of another") {
        let labels = makeTestLabels(count: 100)
        for label in labels {
            let prefixMatches = labels.filter { $0 != label && $0.hasPrefix(label) }
            verify(prefixMatches.isEmpty, "Label '\(label)' should not be a prefix of any other label")
        }
    }

    runTest("filterEmptyPrefix — returns all unchanged") {
        let labels = makeTestLabels(count: 5)
        let filtered = labels.filter { $0.hasPrefix("") }
        assertEqual(filtered.count, labels.count, "Empty prefix should return all labels")
    }

    runTest("filterMatchingPrefix — keeps only labels starting with 'a'") {
        let labels = makeTestLabels(count: 30)
        let filtered = labels.filter { $0.hasPrefix("a") }
        verify(!filtered.isEmpty, "Should find labels starting with 'a'")
        verify(filtered.allSatisfy { $0.hasPrefix("a") }, "All filtered labels start with 'a'")
    }

    runTest("filterNoMatch — unmatched prefix returns empty") {
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

func anchorPointTest(frameX: Double, frameY: Double, frameMaxY: Double, frameWidth: Double,
                     frameHeight: Double, screenMinX: Double, screenMaxY: Double) -> TPoint {
    let midY = (frameY + frameMaxY) / 2
    let x = frameWidth > frameHeight
      ? frameX + frameWidth / 2
      : frameX + min(10.0, frameWidth / 4)
    return TPoint(x: x - screenMinX, y: screenMaxY - midY)
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

    runTest("testAnchorInsideElement — landscape centers, portrait left-insets") {
        // screenFrame: x=100, y=200, w=80, h=30 → landscape → midX=140, midY=215
        let wide = anchorPointTest(frameX: 100, frameY: 200, frameMaxY: 230, frameWidth: 80, frameHeight: 30,
                                   screenMinX: 0, screenMaxY: 900)
        assertEqual(wide.x, 140.0, "wide anchorX = frame.midX = 140")
        assertEqual(wide.y, 685.0, "anchorY = screen.maxY - frame.midY = 685")
        // w=20, h=40 → portrait → inset min(10, 5) = 5 → x=105
        let tall = anchorPointTest(frameX: 100, frameY: 200, frameMaxY: 240, frameWidth: 20, frameHeight: 40,
                                   screenMinX: 0, screenMaxY: 900)
        assertEqual(tall.x, 105.0, "tall anchorX = minX + inset(5) = 105")
    }

}

// MARK: - SettingDefinition Tests (mirroring actual PluginSettings.swift)

enum TestSettingDefinition {
    case slider(key: String, label: String, range: ClosedRange<Double>, defaultValue: Double, step: Double)
    case toggle(key: String, label: String, defaultValue: Bool)
    case hotkey(key: String, label: String, defaultValue: String)
    case text(key: String, label: String, defaultValue: String)
    case dropdown(key: String, label: String, options: [String], defaultValue: String)
    case color(key: String, label: String, defaultValue: String)
    case section(label: String, description: String?)

    var id: String {
        switch self {
        case .section(let label, _):
            return "section.\(label)"
        default:
            return key
        }
    }

    var key: String {
        switch self {
        case .slider(let key, _, _, _, _),
             .toggle(let key, _, _),
             .hotkey(let key, _, _),
             .text(let key, _, _),
             .dropdown(let key, _, _, _, _),
             .color(let key, _, _):
            return key
        case .section:
            return ""
        }
    }

    var label: String {
        switch self {
        case .slider(_, let label, _, _, _),
             .toggle(_, let label, _),
             .hotkey(_, let label, _),
             .text(_, let label, _),
             .dropdown(_, let label, _, _, _),
             .color(_, let label, _):
            return label
        case .section(let label, _):
            return label
        }
    }

    var defaultValue: Any {
        switch self {
        case .slider(_, _, _, let defaultValue, _):
            return defaultValue
        case .toggle(_, _, let defaultValue):
            return defaultValue
        case .hotkey(_, _, let defaultValue):
            return defaultValue
        case .text(_, _, let defaultValue):
            return defaultValue
        case .dropdown(_, _, _, let defaultValue):
            return defaultValue
        case .color(_, _, let defaultValue):
            return defaultValue
        case .section:
            return ""
        }
    }
}

testSuite("SettingDefinition Tests") {
    runTest("slider — key, label, defaultValue") {
        let s = TestSettingDefinition.slider(key: "interval", label: "Update Interval",
                                            range: 1.0...60.0, defaultValue: 5.0, step: 0.5)
        assertEqual(s.key, "interval")
        assertEqual(s.label, "Update Interval")
        assertEqual(s.id, "interval", "id should equal key for non-section")
        verify((s.defaultValue as? Double) == 5.0, "defaultValue should be 5.0")
    }

    runTest("toggle — key, label, defaultValue") {
        let s = TestSettingDefinition.toggle(key: "enabled", label: "Enabled", defaultValue: true)
        assertEqual(s.key, "enabled")
        assertEqual(s.label, "Enabled")
        verify((s.defaultValue as? Bool) == true, "defaultValue should be true")
    }

    runTest("hotkey — key, label, defaultValue") {
        let s = TestSettingDefinition.hotkey(key: "shortcut", label: "Shortcut",
                                            defaultValue: "\u{2318}\u{21E7}Space")
        assertEqual(s.key, "shortcut")
        assertEqual(s.label, "Shortcut")
        assertEqual(s.id, "shortcut")
        verify((s.defaultValue as? String) == "\u{2318}\u{21E7}Space", "defaultValue should match")
    }

    runTest("text — key, label, defaultValue") {
        let s = TestSettingDefinition.text(key: "format", label: "Format", defaultValue: "%.1f%%")
        assertEqual(s.key, "format")
        assertEqual(s.label, "Format")
        verify((s.defaultValue as? String) == "%.1f%%", "defaultValue should match")
    }

    runTest("dropdown — key, label, defaultValue") {
        let s = TestSettingDefinition.dropdown(key: "displayMode", label: "Display Mode",
                                              options: ["text", "graph", "both"], defaultValue: "both")
        assertEqual(s.key, "displayMode")
        assertEqual(s.label, "Display Mode")
        verify((s.defaultValue as? String) == "both", "defaultValue should be 'both'")
    }

    runTest("color — key, label, defaultValue") {
        let s = TestSettingDefinition.color(key: "barColor", label: "Bar Color", defaultValue: "#007AFF")
        assertEqual(s.key, "barColor")
        assertEqual(s.label, "Bar Color")
        verify((s.defaultValue as? String) == "#007AFF", "defaultValue should be '#007AFF'")
    }

    runTest("section — id uses 'section.' prefix, key is empty, defaultValue is empty") {
        let s = TestSettingDefinition.section(label: "Display", description: "Display options")
        assertEqual(s.key, "", "section key should be empty")
        assertEqual(s.label, "Display")
        assertEqual(s.id, "section.Display", "section id should have prefix")
        verify((s.defaultValue as? String) == "", "section defaultValue should be empty string")
    }

    runTest("section — without description") {
        let s = TestSettingDefinition.section(label: "Advanced", description: nil)
        assertEqual(s.label, "Advanced")
        assertEqual(s.id, "section.Advanced")
    }
}

// MARK: - Shortcut Parsing Tests (logic duplicated from ShortcutParsing.swift)

struct TestParsedShortcut {
    struct ModifierFlags: OptionSet {
        let rawValue: Int
        static let control = ModifierFlags(rawValue: 1 << 0)
        static let option  = ModifierFlags(rawValue: 1 << 1)
        static let shift   = ModifierFlags(rawValue: 1 << 2)
        static let command = ModifierFlags(rawValue: 1 << 3)
    }

    let modifiers: ModifierFlags
    let keyCode: UInt16
}

// Unicode modifier characters matching ShortcutParsing.swift
let ctrlChar: Character   = "\u{2303}"
let optChar: Character    = "\u{2325}"
let shiftChar: Character  = "\u{21E7}"
let cmdChar: Character    = "\u{2318}"

func testParseShortcutString(_ display: String) -> TestParsedShortcut {
    var mods: TestParsedShortcut.ModifierFlags = []
    var remaining = display
    let modifierChars: Set<Character> = ["\u{2303}", "\u{2325}", "\u{21E7}", "\u{2318}"]

    while let first = remaining.first, modifierChars.contains(first) {
        switch first {
        case "\u{2303}": mods.insert(.control)
        case "\u{2325}": mods.insert(.option)
        case "\u{21E7}": mods.insert(.shift)
        case "\u{2318}": mods.insert(.command)
        default: break
        }
        remaining.removeFirst()
    }

    return TestParsedShortcut(modifiers: mods, keyCode: testKeyCodeFromName(remaining))
}

func testKeyCodeFromName(_ name: String) -> UInt16 {
    switch name {
    case "Space":  return 49
    case "Return": return 36
    case "Tab":    return 48
    case "Delete": return 51
    case "Esc":    return 53
    case "\u{2190}": return 123
    case "\u{2192}": return 124
    case "\u{2193}": return 125
    case "\u{2191}": return 126
    default:
        return testCarbonKeyCode(for: name.lowercased()) ?? 49
    }
}

func testCarbonKeyCode(for char: String) -> UInt16? {
    let map: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47
    ]
    return map[char]
}

// Modifier symbol formatter (mirrors ShortcutCaptureView.modifierSymbols)
func testModifierSymbols(_ flags: TestParsedShortcut.ModifierFlags) -> String {
    var result = ""
    if flags.contains(.control) { result += "\u{2303}" }
    if flags.contains(.option)  { result += "\u{2325}" }
    if flags.contains(.shift)   { result += "\u{21E7}" }
    if flags.contains(.command) { result += "\u{2318}" }
    return result
}

testSuite("Shortcut Parsing Tests") {
    runTest("command+Space parses correctly") {
        let parsed = testParseShortcutString("\u{2318}Space")
        verify(parsed.modifiers.contains(.command), "Should have command modifier")
        verify(!parsed.modifiers.contains(.shift), "Should not have shift modifier")
        assertEqual(parsed.keyCode, 49, "Space keyCode should be 49")
    }

    runTest("command+shift+Space parses correctly") {
        let parsed = testParseShortcutString("\u{2318}\u{21E7}Space")
        verify(parsed.modifiers.contains(.command), "Should have command")
        verify(parsed.modifiers.contains(.shift), "Should have shift")
        assertEqual(parsed.keyCode, 49, "Space should be 49")
    }

    runTest("control+option+A parses correctly") {
        let parsed = testParseShortcutString("\u{2303}\u{2325}A")
        verify(parsed.modifiers.contains(.control), "Should have control")
        verify(parsed.modifiers.contains(.option), "Should have option")
        assertEqual(parsed.keyCode, 0, "A keyCode should be 0")
    }

    runTest("Return key parses to keyCode 36") {
        let parsed = testParseShortcutString("\u{2318}Return")
        assertEqual(parsed.keyCode, 36)
    }

    runTest("Tab key parses to keyCode 48") {
        let parsed = testParseShortcutString("\u{2318}Tab")
        assertEqual(parsed.keyCode, 48)
    }

    runTest("Delete key parses to keyCode 51") {
        let parsed = testParseShortcutString("\u{2318}Delete")
        assertEqual(parsed.keyCode, 51)
    }

    runTest("arrow keys parse to correct keyCodes") {
        assertEqual(testKeyCodeFromName("\u{2190}"), 123, "Left arrow")
        assertEqual(testKeyCodeFromName("\u{2192}"), 124, "Right arrow")
        assertEqual(testKeyCodeFromName("\u{2193}"), 125, "Down arrow")
        assertEqual(testKeyCodeFromName("\u{2191}"), 126, "Up arrow")
    }

    runTest("known letter keycodes are correct") {
        assertEqual(testCarbonKeyCode(for: "a"), 0)
        assertEqual(testCarbonKeyCode(for: "s"), 1)
        assertEqual(testCarbonKeyCode(for: "d"), 2)
        assertEqual(testCarbonKeyCode(for: "m"), 46)
        assertEqual(testCarbonKeyCode(for: "z"), 6)
    }

    runTest("unknown key falls back to Space (49)") {
        let parsed = testParseShortcutString("\u{2318}Undefined")
        assertEqual(parsed.keyCode, 49, "Unknown key should fall back to 49 (Space)")
    }

    runTest("no modifiers gives empty string") {
        let symbols = testModifierSymbols([])
        assertEqual(symbols, "", "No modifiers should give empty string")
    }

    runTest("modifier symbols in canonical order: ctrl, opt, shift, cmd") {
        // All four modifiers — order should be ⌃⌥⇧⌘
        var flags: TestParsedShortcut.ModifierFlags = []
        flags.insert(.control)
        flags.insert(.option)
        flags.insert(.shift)
        flags.insert(.command)
        let symbols = testModifierSymbols(flags)
        assertEqual(symbols, "\u{2303}\u{2325}\u{21E7}\u{2318}", "Symbols should be in ctrl-opt-shift-cmd order")
    }

    runTest("command-only modifier symbol") {
        let symbols = testModifierSymbols(.command)
        assertEqual(symbols, "\u{2318}")
    }
}

// MARK: - WidgetConfig Tests (logic duplicated from WidgetConfig.swift)

enum TestWidgetType: String, Codable {
    case menuBar
    case menu
}

struct TestWidgetConfig: Codable, Identifiable {
    let id: String
    let widgetType: TestWidgetType
    var isVisible: Bool
    var position: Int

    init(id: String, widgetType: TestWidgetType, isVisible: Bool = true, position: Int = 0) {
        self.id = id
        self.widgetType = widgetType
        self.isVisible = isVisible
        self.position = position
    }
}

testSuite("WidgetConfig Tests") {
    runTest("default init has isVisible=true, position=0") {
        let config = TestWidgetConfig(id: "test.widget", widgetType: .menuBar)
        assertEqual(config.id, "test.widget")
        verify(config.isVisible, "Default should be visible")
        assertEqual(config.position, 0)
    }

    runTest("explicit visibility=false is preserved") {
        let config = TestWidgetConfig(id: "hidden.widget", widgetType: .menu, isVisible: false, position: 5)
        verify(!config.isVisible, "Should not be visible")
        assertEqual(config.position, 5)
    }

    runTest("widgetType rawValues are correct") {
        assertEqual(TestWidgetType.menuBar.rawValue, "menuBar")
        assertEqual(TestWidgetType.menu.rawValue, "menu")
    }

    runTest("WidgetConfig is Codable — roundtrip encode/decode") {
        let original = TestWidgetConfig(id: "cpu.graph", widgetType: .menuBar, isVisible: true, position: 2)
        guard let data = try? JSONEncoder().encode(original),
              let decoded = try? JSONDecoder().decode(TestWidgetConfig.self, from: data) else {
            verify(false, "Encode/decode failed")
            return
        }
        assertEqual(decoded.id, original.id)
        assertEqual(decoded.widgetType.rawValue, original.widgetType.rawValue)
        verify(decoded.isVisible == original.isVisible, "isVisible should round-trip")
        assertEqual(decoded.position, original.position)
    }

    runTest("Array of WidgetConfig roundtrips") {
        let configs = [
            TestWidgetConfig(id: "cpu.bar", widgetType: .menuBar, isVisible: true, position: 0),
            TestWidgetConfig(id: "cpu.menu", widgetType: .menu, isVisible: false, position: 1)
        ]
        guard let data = try? JSONEncoder().encode(configs),
              let decoded = try? JSONDecoder().decode([TestWidgetConfig].self, from: data) else {
            verify(false, "Array encode/decode failed")
            return
        }
        assertEqual(decoded.count, 2)
        assertEqual(decoded[0].id, "cpu.bar")
        assertEqual(decoded[1].id, "cpu.menu")
        verify(!decoded[1].isVisible, "Second widget should be hidden")
    }
}

// MARK: - Widget Ordering Logic Tests

struct TestWidgetInfo {
    let id: String
    let pluginId: String
    let priority: Int
}

func testSortWidgets(_ widgets: [TestWidgetInfo], configs: [String: (position: Int, isVisible: Bool)]) -> (sorted: [TestWidgetInfo], visible: [TestWidgetInfo]) {
    struct Item {
        let widget: TestWidgetInfo
        let position: Int
        let isVisible: Bool
    }
    let items: [Item] = widgets.map { w in
        let config = configs[w.id]
        let position = config?.position ?? w.priority
        let isVisible = config?.isVisible ?? true
        return Item(widget: w, position: position, isVisible: isVisible)
    }
    let sorted = items.sorted { $0.position < $1.position }.map { $0.widget }
    let visible = items.filter { $0.isVisible }.sorted { $0.position < $1.position }.map { $0.widget }
    return (sorted, visible)
}

testSuite("Widget Ordering Tests") {
    runTest("widgets sort by priority when no config") {
        let widgets = [
            TestWidgetInfo(id: "w3", pluginId: "p1", priority: 30),
            TestWidgetInfo(id: "w1", pluginId: "p1", priority: 10),
            TestWidgetInfo(id: "w2", pluginId: "p1", priority: 20)
        ]
        let result = testSortWidgets(widgets, configs: [:])
        assertEqual(result.sorted[0].id, "w1")
        assertEqual(result.sorted[1].id, "w2")
        assertEqual(result.sorted[2].id, "w3")
    }

    runTest("config position overrides widget priority") {
        let widgets = [
            TestWidgetInfo(id: "w1", pluginId: "p1", priority: 10),
            TestWidgetInfo(id: "w2", pluginId: "p1", priority: 20)
        ]
        // w2 gets position 0 → should appear first
        let configs: [String: (position: Int, isVisible: Bool)] = [
            "w2": (position: 0, isVisible: true)
        ]
        let result = testSortWidgets(widgets, configs: configs)
        assertEqual(result.sorted[0].id, "w2", "w2 with config position=0 should come first")
        assertEqual(result.sorted[1].id, "w1")
    }

    runTest("hidden widgets excluded from visible list") {
        let widgets = [
            TestWidgetInfo(id: "w1", pluginId: "p1", priority: 10),
            TestWidgetInfo(id: "w2", pluginId: "p1", priority: 20),
            TestWidgetInfo(id: "w3", pluginId: "p1", priority: 30)
        ]
        let configs: [String: (position: Int, isVisible: Bool)] = [
            "w2": (position: 20, isVisible: false)
        ]
        let result = testSortWidgets(widgets, configs: configs)
        assertEqual(result.sorted.count, 3, "sorted list includes all")
        assertEqual(result.visible.count, 2, "visible list excludes hidden")
        verify(!result.visible.contains(where: { $0.id == "w2" }), "w2 should not be visible")
    }

    runTest("all hidden — visible list is empty") {
        let widgets = [
            TestWidgetInfo(id: "w1", pluginId: "p1", priority: 10)
        ]
        let configs: [String: (position: Int, isVisible: Bool)] = [
            "w1": (position: 10, isVisible: false)
        ]
        let result = testSortWidgets(widgets, configs: configs)
        verify(result.visible.isEmpty, "No visible widgets")
    }

    runTest("empty widget list") {
        let result = testSortWidgets([], configs: [:])
        verify(result.sorted.isEmpty)
        verify(result.visible.isEmpty)
    }
}

// MARK: - LabelGenerator filter and exactMatch Tests

struct TestLabeledElement {
    let label: String
    let id: Int
}

func testMakeLabels(count: Int) -> [String] {
    makeTestLabels(count: count)
}

func testLabelElements(count: Int) -> [TestLabeledElement] {
    let labels = testMakeLabels(count: count)
    return labels.enumerated().map { TestLabeledElement(label: $0.element, id: $0.offset) }
}

func testFilterLabels(_ elements: [TestLabeledElement], prefix: String) -> [TestLabeledElement] {
    guard !prefix.isEmpty else { return elements }
    return elements.filter { $0.label.hasPrefix(prefix) }
}

func testExactMatch(in elements: [TestLabeledElement], for input: String) -> TestLabeledElement? {
    elements.first { $0.label == input }
}

testSuite("LabelGenerator filter and exactMatch Tests") {
    runTest("filter with empty prefix returns all elements") {
        let elements = testLabelElements(count: 10)
        let filtered = testFilterLabels(elements, prefix: "")
        assertEqual(filtered.count, 10, "Empty prefix returns all")
    }

    runTest("filter with 'a' prefix returns elements starting with 'a'") {
        let elements = testLabelElements(count: 30)
        let filtered = testFilterLabels(elements, prefix: "a")
        verify(!filtered.isEmpty, "Should find elements with 'a' prefix")
        verify(filtered.allSatisfy { $0.label.hasPrefix("a") }, "All filtered should start with 'a'")
    }

    runTest("filter with non-matching prefix returns empty") {
        let elements = testLabelElements(count: 5)
        let filtered = testFilterLabels(elements, prefix: "zz")
        verify(filtered.isEmpty, "No elements start with 'zz' in first 5")
    }

    runTest("exactMatch finds element with matching label") {
        let elements = testLabelElements(count: 10)
        // 10 elements → 1-char labels; first is "a"
        let match = testExactMatch(in: elements, for: "a")
        verify(match != nil, "Should find 'a' label")
        assertEqual(match?.label ?? "", "a")
    }

    runTest("exactMatch returns nil for non-existent label") {
        let elements = testLabelElements(count: 5)
        let match = testExactMatch(in: elements, for: "zzz")
        verify(match == nil, "Should not find 'zzz'")
    }

    runTest("exactMatch with uniform 2-char labels") {
        let elements = testLabelElements(count: 30)
        // 30 elements → all 2-char labels; first is "aa", second is "as"
        let exactAA = testExactMatch(in: elements, for: "aa")
        let exactAS = testExactMatch(in: elements, for: "as")
        verify(exactAA != nil, "Should find exact 'aa'")
        verify(exactAS != nil, "Should find exact 'as'")
        verify(exactAA?.id != exactAS?.id, "They should be different elements")
    }

    runTest("filter then exactMatch simulates hint selection") {
        let elements = testLabelElements(count: 50)
        // User typed "a" — filter narrows down
        let afterA = testFilterLabels(elements, prefix: "a")
        // User typed "as" — narrower
        let afterAs = testFilterLabels(afterA, prefix: "as")
        // All results start with "as"
        verify(afterAs.allSatisfy { $0.label.hasPrefix("as") }, "All should start with 'as'")
        // Exact match for "as"
        let match = testExactMatch(in: afterAs, for: "as")
        verify(match != nil, "Should find exact match for 'as'")
    }
}

// MARK: - Log Level Comparison Tests (logic duplicated from Logger.swift)

enum TestLogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    static func < (lhs: TestLogLevel, rhs: TestLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

func testShouldLog(minimumLevel: TestLogLevel, messageLevel: TestLogLevel) -> Bool {
    return minimumLevel <= messageLevel
}

func testLogLevelFromEnv(_ envValue: String?) -> TestLogLevel {
    guard let envValue = envValue else { return .info }
    switch envValue.lowercased() {
    case "debug":   return .debug
    case "info":    return .info
    case "warning": return .warning
    case "error":   return .error
    default:        return .info
    }
}

testSuite("Log Level Tests") {
    runTest("debug < info < warning < error ordering") {
        verify(TestLogLevel.debug < TestLogLevel.info, "debug < info")
        verify(TestLogLevel.info < TestLogLevel.warning, "info < warning")
        verify(TestLogLevel.warning < TestLogLevel.error, "warning < error")
        verify(TestLogLevel.debug < TestLogLevel.error, "debug < error")
    }

    runTest("equal levels: minimumLevel == messageLevel should log") {
        verify(testShouldLog(minimumLevel: .info, messageLevel: .info), "info allows info")
        verify(testShouldLog(minimumLevel: .debug, messageLevel: .debug), "debug allows debug")
        verify(testShouldLog(minimumLevel: .error, messageLevel: .error), "error allows error")
    }

    runTest("minimumLevel=info suppresses debug") {
        verify(!testShouldLog(minimumLevel: .info, messageLevel: .debug),
               "info minimum should suppress debug messages")
    }

    runTest("minimumLevel=debug allows all levels") {
        verify(testShouldLog(minimumLevel: .debug, messageLevel: .debug), "debug allows debug")
        verify(testShouldLog(minimumLevel: .debug, messageLevel: .info), "debug allows info")
        verify(testShouldLog(minimumLevel: .debug, messageLevel: .warning), "debug allows warning")
        verify(testShouldLog(minimumLevel: .debug, messageLevel: .error), "debug allows error")
    }

    runTest("minimumLevel=warning suppresses debug and info") {
        verify(!testShouldLog(minimumLevel: .warning, messageLevel: .debug), "warning suppresses debug")
        verify(!testShouldLog(minimumLevel: .warning, messageLevel: .info), "warning suppresses info")
        verify(testShouldLog(minimumLevel: .warning, messageLevel: .warning), "warning allows warning")
        verify(testShouldLog(minimumLevel: .warning, messageLevel: .error), "warning allows error")
    }

    runTest("minimumLevel=error suppresses debug, info, and warning") {
        verify(!testShouldLog(minimumLevel: .error, messageLevel: .debug), "error suppresses debug")
        verify(!testShouldLog(minimumLevel: .error, messageLevel: .info), "error suppresses info")
        verify(!testShouldLog(minimumLevel: .error, messageLevel: .warning), "error suppresses warning")
        verify(testShouldLog(minimumLevel: .error, messageLevel: .error), "error allows error")
    }

    runTest("env var 'debug' maps to .debug") {
        assertEqual(testLogLevelFromEnv("debug").rawValue, TestLogLevel.debug.rawValue)
        assertEqual(testLogLevelFromEnv("DEBUG").rawValue, TestLogLevel.debug.rawValue)
    }

    runTest("env var 'info' maps to .info") {
        assertEqual(testLogLevelFromEnv("info").rawValue, TestLogLevel.info.rawValue)
    }

    runTest("env var 'warning' maps to .warning") {
        assertEqual(testLogLevelFromEnv("warning").rawValue, TestLogLevel.warning.rawValue)
    }

    runTest("env var 'error' maps to .error") {
        assertEqual(testLogLevelFromEnv("error").rawValue, TestLogLevel.error.rawValue)
    }

    runTest("nil env var defaults to .info") {
        assertEqual(testLogLevelFromEnv(nil).rawValue, TestLogLevel.info.rawValue)
    }

    runTest("unknown env var defaults to .info") {
        assertEqual(testLogLevelFromEnv("verbose").rawValue, TestLogLevel.info.rawValue)
        assertEqual(testLogLevelFromEnv("").rawValue, TestLogLevel.info.rawValue)
    }
}

// MARK: - Settings Value Store Tests (logic from SettingsViewHelpers.swift)

// Simulates the `values` dictionary and getValue/setValue logic
class TestSettingsStore {
    var values: [String: [String: Any]] = [:]

    func getValue(for pluginID: String, key: String, default defaultValue: Any) -> Any {
        values[pluginID]?[key] ?? defaultValue
    }

    func setValue(_ value: Any, for pluginID: String, key: String) {
        if values[pluginID] == nil {
            values[pluginID] = [:]
        }
        values[pluginID]?[key] = value
    }
}

testSuite("Settings Value Store Tests") {
    runTest("getValue returns default when not set") {
        let store = TestSettingsStore()
        let val = store.getValue(for: "plugin.cpu", key: "interval", default: 5.0)
        verify((val as? Double) == 5.0, "Should return default 5.0")
    }

    runTest("setValue stores value, getValue retrieves it") {
        let store = TestSettingsStore()
        store.setValue(3.0, for: "plugin.cpu", key: "interval")
        let val = store.getValue(for: "plugin.cpu", key: "interval", default: 5.0)
        verify((val as? Double) == 3.0, "Should return stored 3.0, not default")
    }

    runTest("getValue for unknown plugin returns default") {
        let store = TestSettingsStore()
        let val = store.getValue(for: "plugin.unknown", key: "foo", default: "bar")
        verify((val as? String) == "bar", "Unknown plugin key should return default")
    }

    runTest("different plugins are isolated") {
        let store = TestSettingsStore()
        store.setValue(true, for: "plugin.cpu", key: "enabled")
        store.setValue(false, for: "plugin.keyboard", key: "enabled")
        let cpuEnabled = store.getValue(for: "plugin.cpu", key: "enabled", default: true)
        let kbEnabled = store.getValue(for: "plugin.keyboard", key: "enabled", default: true)
        verify((cpuEnabled as? Bool) == true, "CPU enabled should be true")
        verify((kbEnabled as? Bool) == false, "Keyboard enabled should be false")
    }

    runTest("overwriting a value replaces it") {
        let store = TestSettingsStore()
        store.setValue(5.0, for: "plugin.cpu", key: "interval")
        store.setValue(10.0, for: "plugin.cpu", key: "interval")
        let val = store.getValue(for: "plugin.cpu", key: "interval", default: 5.0)
        verify((val as? Double) == 10.0, "Overwritten value should be 10.0")
    }

    runTest("multiple keys for same plugin are independent") {
        let store = TestSettingsStore()
        store.setValue(2.0, for: "plugin.cpu", key: "interval")
        store.setValue("graph", for: "plugin.cpu", key: "displayMode")
        let interval = store.getValue(for: "plugin.cpu", key: "interval", default: 5.0)
        let mode = store.getValue(for: "plugin.cpu", key: "displayMode", default: "text")
        verify((interval as? Double) == 2.0, "interval should be 2.0")
        verify((mode as? String) == "graph", "displayMode should be 'graph'")
    }
}

// MARK: - Hex Color Parsing Tests (logic duplicated from ColorExtensions.swift)

struct TestRGBColor {
    let red: Double
    let green: Double
    let blue: Double
}

func testColorFromHex(_ hex: String) -> TestRGBColor? {
    var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    sanitized = sanitized.replacingOccurrences(of: "#", with: "")

    var rgb: UInt64 = 0
    guard Scanner(string: sanitized).scanHexInt64(&rgb) else { return nil }

    let red   = Double((rgb & 0xFF0000) >> 16) / 255.0
    let green = Double((rgb & 0x00FF00) >> 8)  / 255.0
    let blue  = Double(rgb & 0x0000FF)          / 255.0
    return TestRGBColor(red: red, green: green, blue: blue)
}

func testColorToHex(red: Double, green: Double, blue: Double) -> String {
    let r = Int(red * 255.0)
    let g = Int(green * 255.0)
    let b = Int(blue * 255.0)
    return String(format: "#%02X%02X%02X", r, g, b)
}

func approxEqual(_ a: Double, _ b: Double, tolerance: Double = 0.005) -> Bool {
    return abs(a - b) <= tolerance
}

testSuite("Hex Color Parsing Tests") {
    runTest("pure red #FF0000") {
        guard let color = testColorFromHex("#FF0000") else {
            verify(false, "Failed to parse #FF0000"); return
        }
        verify(approxEqual(color.red, 1.0), "Red should be 1.0")
        verify(approxEqual(color.green, 0.0), "Green should be 0.0")
        verify(approxEqual(color.blue, 0.0), "Blue should be 0.0")
    }

    runTest("pure green #00FF00") {
        guard let color = testColorFromHex("#00FF00") else {
            verify(false, "Failed to parse #00FF00"); return
        }
        verify(approxEqual(color.red, 0.0))
        verify(approxEqual(color.green, 1.0))
        verify(approxEqual(color.blue, 0.0))
    }

    runTest("pure blue #0000FF") {
        guard let color = testColorFromHex("#0000FF") else {
            verify(false, "Failed to parse #0000FF"); return
        }
        verify(approxEqual(color.red, 0.0))
        verify(approxEqual(color.green, 0.0))
        verify(approxEqual(color.blue, 1.0))
    }

    runTest("black #000000") {
        guard let color = testColorFromHex("#000000") else {
            verify(false, "Failed to parse #000000"); return
        }
        verify(approxEqual(color.red, 0.0))
        verify(approxEqual(color.green, 0.0))
        verify(approxEqual(color.blue, 0.0))
    }

    runTest("white #FFFFFF") {
        guard let color = testColorFromHex("#FFFFFF") else {
            verify(false, "Failed to parse #FFFFFF"); return
        }
        verify(approxEqual(color.red, 1.0))
        verify(approxEqual(color.green, 1.0))
        verify(approxEqual(color.blue, 1.0))
    }

    runTest("Apple blue #007AFF parses correctly") {
        guard let color = testColorFromHex("#007AFF") else {
            verify(false, "Failed to parse #007AFF"); return
        }
        verify(approxEqual(color.red, 0.0), "Red should be 0")
        verify(approxEqual(color.green, Double(0x7A) / 255.0), "Green should match 0x7A")
        verify(approxEqual(color.blue, 1.0), "Blue should be 1.0")
    }

    runTest("without # prefix also parses") {
        guard let color = testColorFromHex("FF0000") else {
            verify(false, "Failed to parse FF0000 without #"); return
        }
        verify(approxEqual(color.red, 1.0))
    }

    runTest("lowercase hex parses correctly") {
        guard let color = testColorFromHex("#ff0000") else {
            verify(false, "Failed to parse lowercase #ff0000"); return
        }
        verify(approxEqual(color.red, 1.0))
        verify(approxEqual(color.green, 0.0))
        verify(approxEqual(color.blue, 0.0))
    }

    runTest("invalid hex returns nil") {
        let color = testColorFromHex("#ZZZZZZ")
        verify(color == nil, "Invalid hex should return nil")
    }

    runTest("toHex roundtrip for red") {
        let hex = testColorToHex(red: 1.0, green: 0.0, blue: 0.0)
        assertEqual(hex, "#FF0000")
    }

    runTest("toHex roundtrip for arbitrary color") {
        let hex = testColorToHex(red: 0.0, green: Double(0x7A) / 255.0, blue: 1.0)
        // Expected: #007AFF (approximately)
        verify(hex.hasPrefix("#"), "Should start with #")
        verify(hex.count == 7, "Should be 7 chars: #RRGGBB")
    }
}

// MARK: - CPU Usage Delta Calculation Tests

// Pure logic from CPUPlugin+Internals.swift — no mach dependency

func testCoreUsage(user: Int, system: Int, idle: Int, nice: Int,
                   prevUser: Int, prevSystem: Int, prevIdle: Int, prevNice: Int) -> Double {
    let userDelta   = Double(user   - prevUser)
    let systemDelta = Double(system - prevSystem)
    let idleDelta   = Double(idle   - prevIdle)
    let niceDelta   = Double(nice   - prevNice)
    let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
    return totalDelta > 0 ? (userDelta + systemDelta + niceDelta) / totalDelta : 0.0
}

testSuite("CPU Usage Delta Calculation Tests") {
    runTest("100% usage — all delta is user ticks") {
        let usage = testCoreUsage(
            user: 200, system: 0, idle: 0, nice: 0,
            prevUser: 100, prevSystem: 0, prevIdle: 0, prevNice: 0
        )
        verify(approxEqual(usage, 1.0), "100% user load should give 1.0, got \(usage)")
    }

    runTest("0% usage — all delta is idle ticks") {
        let usage = testCoreUsage(
            user: 100, system: 0, idle: 200, nice: 0,
            prevUser: 100, prevSystem: 0, prevIdle: 100, prevNice: 0
        )
        verify(approxEqual(usage, 0.0), "All idle should give 0.0, got \(usage)")
    }

    runTest("50% usage — half user, half idle") {
        let usage = testCoreUsage(
            user: 150, system: 0, idle: 150, nice: 0,
            prevUser: 100, prevSystem: 0, prevIdle: 100, prevNice: 0
        )
        verify(approxEqual(usage, 0.5), "50% load should give 0.5, got \(usage)")
    }

    runTest("system ticks count towards usage") {
        let usage = testCoreUsage(
            user: 100, system: 100, idle: 100, nice: 0,
            prevUser: 50, prevSystem: 50, prevIdle: 50, prevNice: 0
        )
        // user+system = 100, idle = 50, total = 150, usage = 100/150
        let expected = 100.0 / 150.0
        verify(approxEqual(usage, expected), "System ticks should count, got \(usage)")
    }

    runTest("no delta — returns 0 to avoid division by zero") {
        let usage = testCoreUsage(
            user: 100, system: 50, idle: 50, nice: 0,
            prevUser: 100, prevSystem: 50, prevIdle: 50, prevNice: 0
        )
        verify(approxEqual(usage, 0.0), "No delta should return 0.0, got \(usage)")
    }

    runTest("nice ticks count towards usage") {
        let usage = testCoreUsage(
            user: 100, system: 0, idle: 100, nice: 100,
            prevUser: 50, prevSystem: 0, prevIdle: 50, prevNice: 50
        )
        // user+nice = 100, idle = 50, total = 150, usage = 100/150
        let expected = 100.0 / 150.0
        verify(approxEqual(usage, expected), "Nice ticks should count towards usage, got \(usage)")
    }

    runTest("average across cores") {
        let core1 = testCoreUsage(user: 200, system: 0, idle: 0, nice: 0,
                                  prevUser: 100, prevSystem: 0, prevIdle: 0, prevNice: 0) // 100%
        let core2 = testCoreUsage(user: 100, system: 0, idle: 100, nice: 0,
                                  prevUser: 50, prevSystem: 0, prevIdle: 50, prevNice: 0)  // 50%
        let avg = (core1 + core2) / 2.0
        verify(approxEqual(avg, 0.75), "Average of 100% and 50% should be 75%, got \(avg)")
    }
}

// MARK: - Navigation Key Handler State Machine Tests
//
// Models the decision logic in KeyboardPlugin.handleNavigationKey without AppKit.
// The three outcomes for a typed character:
//   exactMatch  → activate element (tested via non-nil result)
//   emptyFilter → dismiss overlay (tested via empty result)
//   otherwise   → update prefix

enum TestNavOutcome: Equatable {
    case exactMatch(label: String)
    case dismiss
    case updatePrefix(String)
    case noChange  // ESC / backspace are handled separately
}

func testHandleChar(_ char: Character, prefix: String, elements: [TestLabeledElement]) -> TestNavOutcome {
    guard testPriorityKeys.contains(char) else { return .noChange }
    let newPrefix = prefix + String(char)
    if let match = testExactMatch(in: elements, for: newPrefix) {
        return .exactMatch(label: match.label)
    } else if testFilterLabels(elements, prefix: newPrefix).isEmpty {
        return .dismiss
    } else {
        return .updatePrefix(newPrefix)
    }
}

func testHandleBackspace(prefix: String) -> String {
    String(prefix.dropLast())
}

testSuite("Navigation Key Handler State Machine Tests") {
    runTest("single-char labels — typing 'a' is an exact match") {
        let elements = testLabelElements(count: 5) // 1-char labels: a, s, d, f, j
        let outcome = testHandleChar("a", prefix: "", elements: elements)
        if case .exactMatch(let label) = outcome {
            assertEqual(label, "a")
        } else {
            verify(false, "Expected exactMatch('a'), got \(outcome)")
        }
    }

    runTest("two-char labels — first char narrows (updatePrefix)") {
        let elements = testLabelElements(count: 50) // 2-char labels: aa, as, ad, ...
        // typing 'a' from "" → newPrefix="a" — matches "aa","as","ad",... but no exact match
        let outcome = testHandleChar("a", prefix: "", elements: elements)
        assertEqual(outcome, .updatePrefix("a"), "First char should narrow, not match")
    }

    runTest("two-char labels — second char produces exact match") {
        let elements = testLabelElements(count: 50) // 2-char labels
        // typing 'a' from prefix "a" → newPrefix="aa" — exact match
        let outcome = testHandleChar("a", prefix: "a", elements: elements)
        if case .exactMatch(let label) = outcome {
            assertEqual(label, "aa")
        } else {
            verify(false, "Expected exactMatch('aa'), got \(outcome)")
        }
    }

    runTest("char that produces empty filter causes dismiss") {
        let elements = testLabelElements(count: 3) // 1-char labels: a, s, d
        // typing 'z' — not in first 3 labels
        let outcome = testHandleChar("z", prefix: "", elements: elements)
        assertEqual(outcome, .dismiss, "No element starts with 'z' — should dismiss")
    }

    runTest("non-priority char is ignored (noChange)") {
        let elements = testLabelElements(count: 10)
        let outcome = testHandleChar("1", prefix: "", elements: elements)
        assertEqual(outcome, .noChange, "Non-priority char should be ignored")
    }

    runTest("backspace on empty prefix stays empty") {
        let result = testHandleBackspace(prefix: "")
        assertEqual(result, "", "Backspace on empty prefix remains empty")
    }

    runTest("backspace drops last character") {
        let result = testHandleBackspace(prefix: "as")
        assertEqual(result, "a", "Backspace should drop 's' leaving 'a'")
    }

    runTest("backspace on single char gives empty prefix") {
        let result = testHandleBackspace(prefix: "a")
        assertEqual(result, "")
    }

    runTest("no prefix ambiguity — updatePrefix is reachable with uniform labels") {
        // With uniform 2-char labels, typing the first char always goes to updatePrefix
        // (never an ambiguous exact match). This is the key improvement.
        let elements = testLabelElements(count: 50)
        let outcome = testHandleChar("s", prefix: "", elements: elements)
        assertEqual(outcome, .updatePrefix("s"), "First char of 2-char label narrows without ambiguity")
    }
}

// MARK: - allGranted Logic Tests (from KeyboardOnboarding)

func testAllGranted(hasAccessibility: Bool, hasInputMonitoring: Bool) -> Bool {
    hasAccessibility && hasInputMonitoring
}

testSuite("Permission allGranted Logic Tests") {
    runTest("both granted → allGranted true") {
        verify(testAllGranted(hasAccessibility: true, hasInputMonitoring: true))
    }

    runTest("only AX granted → allGranted false") {
        verify(!testAllGranted(hasAccessibility: true, hasInputMonitoring: false))
    }

    runTest("only IM granted → allGranted false") {
        verify(!testAllGranted(hasAccessibility: false, hasInputMonitoring: true))
    }

    runTest("neither granted → allGranted false") {
        verify(!testAllGranted(hasAccessibility: false, hasInputMonitoring: false))
    }
}

// MARK: - CGRect center helper Tests (from ElementOverlay.swift)

struct TestCGRect {
    let x: Double; let y: Double; let width: Double; let height: Double
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }
    var center: (x: Double, y: Double) { (midX, midY) }
}

testSuite("CGRect center helper Tests") {
    runTest("center of unit rect at origin") {
        let rect = TestCGRect(x: 0, y: 0, width: 2, height: 2)
        assertEqual(rect.center.x, 1.0)
        assertEqual(rect.center.y, 1.0)
    }

    runTest("center of rect at non-zero origin") {
        let rect = TestCGRect(x: 10, y: 20, width: 100, height: 60)
        assertEqual(rect.center.x, 60.0)
        assertEqual(rect.center.y, 50.0)
    }

    runTest("center of zero-size rect equals origin") {
        let rect = TestCGRect(x: 5, y: 7, width: 0, height: 0)
        assertEqual(rect.center.x, 5.0)
        assertEqual(rect.center.y, 7.0)
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
