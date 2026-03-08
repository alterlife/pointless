import Combine
import Foundation
import OSLog

/// Registry for managing and ordering widgets
@MainActor
class WidgetRegistry: ObservableObject {
  static let shared = WidgetRegistry()

  @Published private(set) var orderedMenuBarWidgets: [MenuBarWidget] = []
  @Published private(set) var orderedMenuWidgets: [MenuWidget] = []

  /// All widgets sorted by saved position (visible + hidden)
  @Published private(set) var sortedAllMenuBarWidgets: [MenuBarWidget] = []
  @Published private(set) var sortedAllMenuWidgets: [MenuWidget] = []

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

  // MARK: - Per-Plugin Queries

  /// All menu bar widgets registered by a specific plugin
  func menuBarWidgets(forPlugin pluginId: String) -> [MenuBarWidget] {
    allMenuBarWidgets.filter { $0.pluginId == pluginId }
  }

  /// All menu widgets registered by a specific plugin
  func menuWidgets(forPlugin pluginId: String) -> [MenuWidget] {
    allMenuWidgets.filter { $0.pluginId == pluginId }
  }

  // MARK: - Reordering

  /// Reorder menu bar widgets (visible only)
  func reorderMenuBar(from source: IndexSet, to destination: Int) {
    orderedMenuBarWidgets.move(fromOffsets: source, toOffset: destination)
    saveConfigs()
  }

  /// Reorder menu widgets (visible only)
  func reorderMenu(from source: IndexSet, to destination: Int) {
    orderedMenuWidgets.move(fromOffsets: source, toOffset: destination)
    saveConfigs()
  }

  /// Reorder all menu bar widgets (visible + hidden), then rebuild visible list
  func reorderAllMenuBar(from source: IndexSet, to destination: Int) {
    sortedAllMenuBarWidgets.move(fromOffsets: source, toOffset: destination)
    let enabledPlugins = Set(PluginRegistry.shared.plugins.filter { $0.isEnabled }.map { $0.id })
    orderedMenuBarWidgets = sortedAllMenuBarWidgets.filter { widget in
      enabledPlugins.contains(widget.pluginId) && isMenuBarWidgetVisible(widget.id)
    }
    saveConfigs()
  }

  /// Reorder all menu widgets (visible + hidden), then rebuild visible list
  func reorderAllMenu(from source: IndexSet, to destination: Int) {
    sortedAllMenuWidgets.move(fromOffsets: source, toOffset: destination)
    let enabledPlugins = Set(PluginRegistry.shared.plugins.filter { $0.isEnabled }.map { $0.id })
    orderedMenuWidgets = sortedAllMenuWidgets.filter { widget in
      enabledPlugins.contains(widget.pluginId) && isMenuWidgetVisible(widget.id)
    }
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
    let (sorted, ordered) = buildSortedWidgets(allMenuBarWidgets, forcedVisibility: forcedVisibility)
    sortedAllMenuBarWidgets = sorted
    orderedMenuBarWidgets = ordered
  }

  private func rebuildOrderedMenuWidgets(forcedVisibility: [String: Bool] = [:]) {
    let (sorted, ordered) = buildSortedWidgets(allMenuWidgets, forcedVisibility: forcedVisibility)
    sortedAllMenuWidgets = sorted
    orderedMenuWidgets = ordered
  }

  private func buildSortedWidgets<W: WidgetProtocol>(
    _ widgets: [W],
    forcedVisibility: [String: Bool]
  ) -> (sorted: [W], ordered: [W]) {
    let configs = loadConfigsDict()
    let enabledPlugins = Set(PluginRegistry.shared.plugins.filter { $0.isEnabled }.map { $0.id })

    // Sort by saved position (or widget priority as default)
    let sorted = widgets.sorted { lhs, rhs in
      let lhsPos = configs[lhs.id]?.position ?? lhs.priority
      let rhsPos = configs[rhs.id]?.position ?? rhs.priority
      return lhsPos < rhsPos
    }

    let ordered = sorted.filter { widget in
      let pluginEnabled = enabledPlugins.contains(widget.pluginId)
      return pluginEnabled && (forcedVisibility[widget.id] ?? configs[widget.id]?.isVisible ?? true)
    }

    return (sorted: sorted, ordered: ordered)
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
    let visibleMenuBarIds = Set(orderedMenuBarWidgets.map { $0.id })
    let visibleMenuIds = Set(orderedMenuWidgets.map { $0.id })

    // Save all menu bar widgets in their sorted order
    for (index, widget) in sortedAllMenuBarWidgets.enumerated() {
      configs.append(WidgetConfig(
        id: widget.id,
        widgetType: .menuBar,
        isVisible: visibleMenuBarIds.contains(widget.id),
        position: index
      ))
    }

    // Save all menu widgets in their sorted order
    for (index, widget) in sortedAllMenuWidgets.enumerated() {
      configs.append(WidgetConfig(
        id: widget.id,
        widgetType: .menu,
        isVisible: visibleMenuIds.contains(widget.id),
        position: index
      ))
    }

    if let data = try? JSONEncoder().encode(configs) {
      UserDefaults.standard.set(data, forKey: configKey)
      Logger.debug("Saved \(configs.count) widget configs")
    }
  }
}
