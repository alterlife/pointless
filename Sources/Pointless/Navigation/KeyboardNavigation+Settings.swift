import AppKit
import SwiftUI

extension KeyboardNavigation {
  static let defaultSettingDefinitions: [SettingDefinition] = [
    .section(label: "Activation", description: "Keyboard shortcut and enable/disable"),
    .toggle(key: "enabled", label: "Enabled", defaultValue: true),
    .hotkey(key: "activationHotkey", label: "Activation Shortcut", defaultValue: "⌘⇧Space"),
    .toggle(
      key: "captureShortcuts",
      label: "Capture Shortcuts",
      defaultValue: true,
      description: "Pointless consumes its shortcuts so apps never see them — e.g. ⌘⇧J won't also " +
        "trigger an app's own shortcut. Turn off to let shortcuts pass through to apps."
    ),
    .section(label: "Scroll Mode", description: "Cycle and scroll scrollable areas by keyboard"),
    .hotkey(key: "scrollNextHotkey", label: "Scroll / Next Area", defaultValue: "⌘⇧J"),
    .hotkey(key: "scrollPrevHotkey", label: "Previous Scroll Area", defaultValue: "⌘⇧K"),
    .slider(key: "scrollSpeed", label: "Scroll Speed", range: 0.25...4, defaultValue: 1, step: 0.25),
    .section(label: "Pointer Mode", description: "Hold a modifier during a session for pointer controls"),
    .choice(
      key: "gridModifier", label: "Grid Modifier",
      options: [
        (title: "Option",
         detail: "Hold ⌥ — the default; never conflicts with label typing."),
        (title: "Command",
         detail: "Hold ⌘ — replaces the hold-to-highlight gesture while the grid is up."),
        (title: "Globe",
         detail: "Hold 🌐 (fn) — leaves ⌥ and ⌘ free for their usual roles.")
      ],
      defaultValue: "Option"
    ),
    .choice(
      key: "gridKeyCluster", label: "Grid Keys",
      options: [
        (title: "Right Hand",
         detail: "Spatially mapped 3×3 under the right hand: uio / jkl / m,."),
        (title: "Left Hand",
         detail: "Spatially mapped 3×3 under the left hand: qwe / asd / zxc."),
        (title: "Classic Home Row",
         detail: "Pointless default priority keys: asd / fjk / lgh.")
      ],
      defaultValue: "Right Hand"
    ),
    .toggle(
      key: "gridAutoClick",
      label: "Auto-Click on Max Zoom",
      defaultValue: true,
      description: "Automatically left-clicks and ends the session when the deepest zoom level is reached."
    ),
    .choice(
      key: "gridMaxLevels", label: "Zoom Depth",
      options: [
        (title: "4 Levels",
         detail: "Drills down to ~64×40 px — reaches small buttons, icons, and checkboxes."),
        (title: "3 Levels",
         detail: "Drills down to ~192×120 px — 3 quick taps for larger controls and panes.")
      ],
      defaultValue: "4 Levels"
    ),
    .section(label: "Overlay Style", description: "Customize the letter hints on screen elements"),
    .choice(
      key: "labelStrategy", label: "Shortcut Hints",
      options: [
        (title: "Homerow Keys",
         detail: "Short keyboard combos assigned by position — fast to type, " +
           "meaningless until memorized."),
        (title: "Element Text",
         detail: "Hints derived from each control's own label (Save → s) — " +
           "self-documenting and stable, occasionally longer.")
      ],
      defaultValue: "Homerow Keys"
    ),
    .color(key: "badgeColor", label: "Hint Color", defaultValue: "#F2BF1A"),
    .color(key: "textColor", label: "Hint Text Color", defaultValue: "#000000"),
    .slider(key: "fontSize", label: "Hint Size", range: 9...16, defaultValue: 11, step: 1),
    .toggle(key: "showLines", label: "Lines to Targets", defaultValue: true),
    .slider(key: "fadeIn", label: "Appear Speed", range: 0...0.3, defaultValue: 0.08, step: 0.02)
  ]

  func settings() -> PluginSettings {
    PluginSettings(definitions: Self.defaultSettingDefinitions)
  }

  func configure(with values: [String: Any]) {
    if let enabled = values["enabled"] as? Bool { isEnabled = enabled }
    if let capture = values["captureShortcuts"] as? Bool { captureShortcuts = capture }
    applyAppearanceSettings(values)
    applyGridSettings(values)
    applyScrollSettings(values)
    if let shortcut = values["activationHotkey"] as? String {
      shortcutDisplay = shortcut
      activationHotkey = parseShortcutString(shortcut)
    }
    applyAppearanceToOverlay()
    reinstallMonitors()
    saveSettings(values)
  }

  private func applyAppearanceSettings(_ values: [String: Any]) {
    if let hex = values["badgeColor"] as? String {
      badgeColor = Color(hex: hex) ?? Color(red: 0.95, green: 0.75, blue: 0.1)
    }
    if let hex = values["textColor"] as? String {
      badgeTextColor = Color(hex: hex) ?? .black
    }
    if let size = values["fontSize"] as? Double { badgeFontSize = CGFloat(size) }
    if let lines = values["showLines"] as? Bool { showConnectorLines = lines }
    if let fade = values["fadeIn"] as? Double { fadeInDuration = fade }
    if let strategy = values["labelStrategy"] as? String { labelStrategy = strategy }
  }

  private func applyGridSettings(_ values: [String: Any]) {
    if let modifier = values["gridModifier"] as? String {
      gridModifierChoice = modifier
      gridModifierFlags = Self.modifierFlags(for: modifier)
      overlayState.gridModifierHint = Self.modifierSymbol(for: modifier)
    }
    if let cluster = values["gridKeyCluster"] as? String {
      gridKeyClusterChoice = cluster
      gridLetters = Self.gridLetters(for: cluster)
      overlayState.gridLetters = gridLetters
    }
    if let autoClick = values["gridAutoClick"] as? Bool {
      gridAutoClick = autoClick
    }
    if let levels = values["gridMaxLevels"] as? String {
      gridMaxLevelsChoice = levels
      gridMaxLevel = levels.hasPrefix("3") ? 3 : 4
    }
  }

  private static func modifierFlags(for choice: String) -> NSEvent.ModifierFlags {
    switch choice {
    case "Command": return .command
    case "Globe": return .function
    default: return .option
    }
  }

  private static func modifierSymbol(for choice: String) -> String {
    switch choice {
    case "Command": return "⌘"
    case "Globe": return "🌐"
    default: return "⌥"
    }
  }

  private static func gridLetters(for choice: String) -> [Character] {
    switch choice {
    case "Left Hand":
      return LabelGenerator.leftHandGridLetters
    case "Classic Home Row":
      return LabelGenerator.classicGridLetters
    default:
      return LabelGenerator.rightHandGridLetters
    }
  }

  private func applyScrollSettings(_ values: [String: Any]) {
    if let shortcut = values["scrollNextHotkey"] as? String {
      scrollNextShortcutDisplay = shortcut
      scrollNextHotkey = parseShortcutString(shortcut)
    }
    if let shortcut = values["scrollPrevHotkey"] as? String {
      scrollPrevShortcutDisplay = shortcut
      scrollPrevHotkey = parseShortcutString(shortcut)
    }
    if let speed = values["scrollSpeed"] as? Double { scrollSpeed = speed }
  }

  private func saveSettings(_ values: [String: Any]) {
    var stored = UserDefaults.standard.dictionary(forKey: "plugin.\(id)") ?? [:]
    values.forEach { stored[$0.key] = $0.value }
    UserDefaults.standard.set(stored, forKey: "plugin.\(id)")
  }

  func applyAppearanceToOverlay() {
    overlayState.badgeColor = badgeColor
    overlayState.textColor = badgeTextColor
    overlayState.badgeFontSize = badgeFontSize
    overlayState.showConnectorLines = showConnectorLines
    overlayState.fadeInDuration = fadeInDuration
  }
}
