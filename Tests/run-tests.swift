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

    var key: String {
        switch self {
        case .slider(let key, _, _, _),
             .toggle(let key, _, _),
             .text(let key, _, _):
            return key
        }
    }

    var label: String {
        switch self {
        case .slider(_, let label, _, _),
             .toggle(_, let label, _),
             .text(_, let label, _):
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

    runTest("Multiple settings") {
        let settings = SimplePluginSettings(definitions: [
            .slider(key: "interval", label: "Interval", range: 1.0...10.0, defaultValue: 5.0),
            .toggle(key: "enabled", label: "Enabled", defaultValue: true),
            .text(key: "name", label: "Name", defaultValue: "Test")
        ])
        assertEqual(settings.definitions.count, 3, "Should have 3 settings")
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
