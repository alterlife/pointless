import XCTest
@testable import PointlessCore

final class PluginSettingsTests: XCTestCase {
  func testEmptySettings() {
    let settings = PluginSettings()
    XCTAssertTrue(settings.definitions.isEmpty)
  }

  func testSliderSetting() {
    let settings = PluginSettings(definitions: [
      .slider(key: "volume", label: "Volume", range: 0.0...100.0, defaultValue: 50.0)
    ])

    XCTAssertEqual(settings.definitions.count, 1)

    if case .slider(let key, let label, let range, let defaultValue) = settings.definitions.first! {
      XCTAssertEqual(key, "volume")
      XCTAssertEqual(label, "Volume")
      XCTAssertEqual(range, 0.0...100.0)
      XCTAssertEqual(defaultValue, 50.0)
    } else {
      XCTFail("Expected slider definition")
    }
  }

  func testToggleSetting() {
    let settings = PluginSettings(definitions: [
      .toggle(key: "enabled", label: "Enabled", defaultValue: true)
    ])

    XCTAssertEqual(settings.definitions.count, 1)

    if case .toggle(let key, let label, let defaultValue) = settings.definitions.first! {
      XCTAssertEqual(key, "enabled")
      XCTAssertEqual(label, "Enabled")
      XCTAssertEqual(defaultValue, true)
    } else {
      XCTFail("Expected toggle definition")
    }
  }

  func testTextSetting() {
    let settings = PluginSettings(definitions: [
      .text(key: "name", label: "Name", defaultValue: "John")
    ])

    if case .text(let key, let label, let defaultValue) = settings.definitions.first! {
      XCTAssertEqual(key, "name")
      XCTAssertEqual(label, "Name")
      XCTAssertEqual(defaultValue, "John")
    } else {
      XCTFail("Expected text definition")
    }
  }

  func testDropdownSetting() {
    let settings = PluginSettings(definitions: [
      .dropdown(key: "theme", label: "Theme", options: ["Light", "Dark"], defaultValue: "Light")
    ])

    if case .dropdown(let key, let label, let options, let defaultValue) = settings.definitions.first! {
      XCTAssertEqual(key, "theme")
      XCTAssertEqual(label, "Theme")
      XCTAssertEqual(options, ["Light", "Dark"])
      XCTAssertEqual(defaultValue, "Light")
    } else {
      XCTFail("Expected dropdown definition")
    }
  }

  func testHotkeySetting() {
    let settings = PluginSettings(definitions: [
      .hotkey(key: "shortcut", label: "Keyboard Shortcut", defaultValue: "Cmd+Shift+K")
    ])

    if case .hotkey(let key, let label, let defaultValue) = settings.definitions.first! {
      XCTAssertEqual(key, "shortcut")
      XCTAssertEqual(label, "Keyboard Shortcut")
      XCTAssertEqual(defaultValue, "Cmd+Shift+K")
    } else {
      XCTFail("Expected hotkey definition")
    }
  }

  func testSettingDefinitionID() {
    let slider = SettingDefinition.slider(key: "test", label: "Test", range: 0...10, defaultValue: 5.0)
    XCTAssertEqual(slider.id, "test")
    XCTAssertEqual(slider.key, "test")
    XCTAssertEqual(slider.label, "Test")
  }

  func testColorSetting() {
    let settings = PluginSettings(definitions: [
      .color(key: "customColor", label: "Custom Color", defaultValue: "#007AFF")
    ])

    if case .color(let key, let label, let defaultValue) = settings.definitions.first! {
      XCTAssertEqual(key, "customColor")
      XCTAssertEqual(label, "Custom Color")
      XCTAssertEqual(defaultValue, "#007AFF")
    } else {
      XCTFail("Expected color definition")
    }
  }

  func testMultipleSettings() {
    let settings = PluginSettings(definitions: [
      .slider(key: "interval", label: "Refresh Interval", range: 1.0...10.0, defaultValue: 5.0),
      .toggle(key: "enabled", label: "Enabled", defaultValue: true),
      .dropdown(key: "color", label: "Color", options: ["Red", "Green", "Blue"], defaultValue: "Red"),
      .color(key: "customColor", label: "Custom Color", defaultValue: "#FF0000")
    ])

    XCTAssertEqual(settings.definitions.count, 4)
  }
}
