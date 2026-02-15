import Combine
import Foundation
import OSLog

/// Registry for managing and ordering widgets
@MainActor
class WidgetRegistry: ObservableObject {
  static let shared = WidgetRegistry()

  @Published private(set) var orderedMenuBarWidgets: [MenuBarWidget] = []
  @Published private(set) var orderedMenuWidgets: [MenuWidget] = []

  private var allMenuBarWidgets: [MenuBarWidget] = []
  private var allMenuWidgets: [MenuWidget] = []
  private var cancellables = Set<AnyCancellable>()

  private let configKey = "pointless.widgetConfigs"

  private init() {
    loadConfigs()

    // Observe PluginRegistry and rebuild widgets when plugins change
    PluginRegistry.shared.objectWillChange.sink { [weak self] _ in
      Task { @MainActor in
        self?.rebuildAllWidgets()
      }
    }
    .store(in: &cancellables)
  }

  private func rebuildAllWidgets() {
    // Get fresh widgets from all plugins
    allMenuBarWidgets.removeAll()
    allMenuWidgets.removeAll()

    for plugin in PluginRegistry.shared.plugins {
      allMenuBarWidgets.append(contentsOf: plugin.menuBarWidgets())
      allMenuWidgets.append(contentsOf: plugin.menuWidgets())
    }

    rebuildOrderedMenuBarWidgets()
    rebuildOrderedMenuWidgets()
  }

  // MARK: - Registration

  /// Register menu bar widgets from a plugin
  func registerMenuBarWidgets(_ widgets: [MenuBarWidget]) {
    for widget in widgets {
      // Check for duplicate IDs
      if allMenuBarWidgets.contains(where: { $0.id == widget.id }) {
        Logger.warning("MenuBarWidget with ID '\(widget.id)' already registered. Skipping.")
        continue
      }

      allMenuBarWidgets.append(widget)
      Logger.info("Registered MenuBarWidget: \(widget.name) (\(widget.id))")
    }

    rebuildOrderedMenuBarWidgets()
  }

  /// Register menu widgets from a plugin
  func registerMenuWidgets(_ widgets: [MenuWidget]) {
    for widget in widgets {
      // Check for duplicate IDs
      if allMenuWidgets.contains(where: { $0.id == widget.id }) {
        Logger.warning("MenuWidget with ID '\(widget.id)' already registered. Skipping.")
        continue
      }

      allMenuWidgets.append(widget)
      Logger.info("Registered MenuWidget: \(widget.name) (\(widget.id))")
    }

    rebuildOrderedMenuWidgets()
  }

  // MARK: - Reordering

  /// Reorder menu bar widgets
  func reorderMenuBar(from source: IndexSet, to destination: Int) {
    orderedMenuBarWidgets.move(fromOffsets: source, toOffset: destination)
    saveConfigs()
  }

  /// Reorder menu widgets
  func reorderMenu(from source: IndexSet, to destination: Int) {
    orderedMenuWidgets.move(fromOffsets: source, toOffset: destination)
    saveConfigs()
  }

  // MARK: - Visibility

  /// Set visibility for a menu bar widget
  func setMenuBarVisibility(widgetId: String, isVisible: Bool) {
    rebuildOrderedMenuBarWidgets(forcedVisibility: [widgetId: isVisible])
    saveConfigs()
  }

  /// Set visibility for a menu widget
  func setMenuVisibility(widgetId: String, isVisible: Bool) {
    rebuildOrderedMenuWidgets(forcedVisibility: [widgetId: isVisible])
    saveConfigs()
  }

  /// Check if a menu bar widget is visible
  func isMenuBarWidgetVisible(_ widgetId: String) -> Bool {
    return orderedMenuBarWidgets.contains(where: { $0.id == widgetId })
  }

  /// Check if a menu widget is visible
  func isMenuWidgetVisible(_ widgetId: String) -> Bool {
    return orderedMenuWidgets.contains(where: { $0.id == widgetId })
  }

  // MARK: - Rebuild Ordered Lists

  private func rebuildOrderedMenuBarWidgets(forcedVisibility: [String: Bool] = [:]) {
    let configs = loadConfigsDict()

    struct WidgetInfo {
      let widget: MenuBarWidget
      let position: Int
      let isVisible: Bool
    }

    var widgets: [WidgetInfo] = []

    for widget in allMenuBarWidgets {
      let config = configs[widget.id]
      let isVisible = forcedVisibility[widget.id] ?? config?.isVisible ?? true
      let position = config?.position ?? widget.priority

      widgets.append(WidgetInfo(widget: widget, position: position, isVisible: isVisible))
    }

    // Sort by position, then filter visible
    widgets.sort { $0.position < $1.position }
    orderedMenuBarWidgets = widgets.filter { $0.isVisible }.map { $0.widget }
  }

  private func rebuildOrderedMenuWidgets(forcedVisibility: [String: Bool] = [:]) {
    let configs = loadConfigsDict()

    struct WidgetInfo {
      let widget: MenuWidget
      let position: Int
      let isVisible: Bool
    }

    var widgets: [WidgetInfo] = []

    for widget in allMenuWidgets {
      let config = configs[widget.id]
      let isVisible = forcedVisibility[widget.id] ?? config?.isVisible ?? true
      let position = config?.position ?? widget.priority

      widgets.append(WidgetInfo(widget: widget, position: position, isVisible: isVisible))
    }

    // Sort by position, then filter visible
    widgets.sort { $0.position < $1.position }
    orderedMenuWidgets = widgets.filter { $0.isVisible }.map { $0.widget }
  }

  // MARK: - Persistence

  private func loadConfigs() {
    rebuildOrderedMenuBarWidgets()
    rebuildOrderedMenuWidgets()
  }

  private func loadConfigsDict() -> [String: WidgetConfig] {
    guard let data = UserDefaults.standard.data(forKey: configKey),
          let configs = try? JSONDecoder().decode([WidgetConfig].self, from: data) else {
      return [:]
    }

    return Dictionary(uniqueKeysWithValues: configs.map { ($0.id, $0) })
  }

  private func saveConfigs() {
    var configs: [WidgetConfig] = []

    // Save menu bar widget configs
    for (index, widget) in orderedMenuBarWidgets.enumerated() {
      configs.append(WidgetConfig(
        id: widget.id,
        widgetType: .menuBar,
        isVisible: true,
        position: index
      ))
    }

    // Save hidden menu bar widgets
    for widget in allMenuBarWidgets where !orderedMenuBarWidgets.contains(where: { $0.id == widget.id }) {
      configs.append(WidgetConfig(
        id: widget.id,
        widgetType: .menuBar,
        isVisible: false,
        position: widget.priority
      ))
    }

    // Save menu widget configs
    for (index, widget) in orderedMenuWidgets.enumerated() {
      configs.append(WidgetConfig(
        id: widget.id,
        widgetType: .menu,
        isVisible: true,
        position: index
      ))
    }

    // Save hidden menu widgets
    for widget in allMenuWidgets where !orderedMenuWidgets.contains(where: { $0.id == widget.id }) {
      configs.append(WidgetConfig(
        id: widget.id,
        widgetType: .menu,
        isVisible: false,
        position: widget.priority
      ))
    }

    if let data = try? JSONEncoder().encode(configs) {
      UserDefaults.standard.set(data, forKey: configKey)
      Logger.debug("Saved \(configs.count) widget configs")
    }
  }
}
