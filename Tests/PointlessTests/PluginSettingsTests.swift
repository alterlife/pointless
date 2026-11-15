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

    guard let first = settings.definitions.first,
          case .slider(let key, let label, let range, let defaultValue, _) = first else {
      XCTFail("Expected slider definition")
      return
    }

    XCTAssertEqual(key, "volume")
    XCTAssertEqual(label, "Volume")
    XCTAssertEqual(range, 0.0...100.0)
    XCTAssertEqual(defaultValue, 50.0)
  }

  func testToggleSetting() {
    let settings = PluginSettings(definitions: [
      .toggle(key: "enabled", label: "Enabled", defaultValue: true)
    ])

    XCTAssertEqual(settings.definitions.count, 1)

    guard let first = settings.definitions.first,
          case .toggle(let key, let label, let defaultValue, _) = first else {
      XCTFail("Expected toggle definition")
      return
    }

    XCTAssertEqual(key, "enabled")
    XCTAssertEqual(label, "Enabled")
    XCTAssertEqual(defaultValue, true)
  }

  func testTextSetting() {
    let settings = PluginSettings(definitions: [
      .text(key: "name", label: "Name", defaultValue: "John")
    ])

    guard let first = settings.definitions.first,
          case .text(let key, let label, let defaultValue) = first else {
      XCTFail("Expected text definition")
      return
    }

    XCTAssertEqual(key, "name")
    XCTAssertEqual(label, "Name")
    XCTAssertEqual(defaultValue, "John")
  }

  func testDropdownSetting() {
    let settings = PluginSettings(definitions: [
      .dropdown(key: "theme", label: "Theme", options: ["Light", "Dark"], defaultValue: "Light")
    ])

    guard let first = settings.definitions.first,
          case .dropdown(let key, let label, let options, let defaultValue, _) = first else {
      XCTFail("Expected dropdown definition")
      return
    }

    XCTAssertEqual(key, "theme")
    XCTAssertEqual(label, "Theme")
    XCTAssertEqual(options, ["Light", "Dark"])
    XCTAssertEqual(defaultValue, "Light")
  }

  func testHotkeySetting() {
    let settings = PluginSettings(definitions: [
      .hotkey(key: "shortcut", label: "Keyboard Shortcut", defaultValue: "Cmd+Shift+K")
    ])

    guard let first = settings.definitions.first,
          case .hotkey(let key, let label, let defaultValue) = first else {
      XCTFail("Expected hotkey definition")
      return
    }

    XCTAssertEqual(key, "shortcut")
    XCTAssertEqual(label, "Keyboard Shortcut")
    XCTAssertEqual(defaultValue, "Cmd+Shift+K")
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

    guard let first = settings.definitions.first,
          case .color(let key, let label, let defaultValue) = first else {
      XCTFail("Expected color definition")
      return
    }

    XCTAssertEqual(key, "customColor")
    XCTAssertEqual(label, "Custom Color")
    XCTAssertEqual(defaultValue, "#007AFF")
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
