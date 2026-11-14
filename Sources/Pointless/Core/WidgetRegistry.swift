import Combine
import Foundation
import OSLog

/// Registry for managing and ordering widgets provided by `WidgetSource`s
/// (plugins and the core navigation feature).
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
  private var sources: [WeakWidgetSource] = []
  private var cancellables = Set<AnyCancellable>()

  private let configKey = "pointless.widgetConfigs"

  init() {
    loadConfigs()
  }

  // MARK: - Sources

  /// Register a widget source. The registry rebuilds its widget lists now and
  /// again whenever the source publishes a change.
  func registerSource<S: WidgetSource & ObservableObject>(_ source: S) {
    guard !sources.contains(where: { $0.source?.id == source.id }) else {
      Logger.warning("Widget source '\(source.id)' already registered. Skipping.")
      return
    }

    sources.append(WeakWidgetSource(source))

    // objectWillChange fires in willSet, before the property updates — defer
    // one run-loop turn so rebuilds read the new values (same as PluginLifecycle).
    source.objectWillChange
      .sink { [weak self] _ in
        Task { @MainActor in self?.rebuildAllWidgets() }
      }
      .store(in: &cancellables)

    Logger.info("Registered widget source: \(source.id)")
    rebuildAllWidgets()
  }

  private var liveSources: [any WidgetSource] {
    sources.compactMap(\.source)
  }

  /// Whether the source with this id is enabled. Unknown ids report disabled.
  func sourceIsEnabled(_ ownerId: String) -> Bool {
    liveSources.first { $0.id == ownerId }?.isEnabled ?? false
  }

  /// SF Symbol icon for the source with this id, if registered.
  func sourceIcon(_ ownerId: String) -> String? {
    liveSources.first { $0.id == ownerId }?.icon
  }

  private func rebuildAllWidgets() {
    var menuBar: [MenuBarWidget] = []
    var menu: [MenuWidget] = []

    for source in liveSources {
      for widget in source.menuBarWidgets() where !menuBar.contains(where: { $0.id == widget.id }) {
        menuBar.append(widget)
      }
      for widget in source.menuWidgets() where !menu.contains(where: { $0.id == widget.id }) {
        menu.append(widget)
      }
    }

    allMenuBarWidgets = menuBar
    allMenuWidgets = menu

    rebuildOrderedMenuBarWidgets()
    rebuildOrderedMenuWidgets()

    Logger.debug("Menu bar widgets: \(orderedMenuBarWidgets.map(\.id))")
    Logger.debug("Menu widgets: \(orderedMenuWidgets.map(\.id))")
  }

  // MARK: - Per-Source Queries

  /// All menu bar widgets provided by a specific source
  func menuBarWidgets(forSource sourceId: String) -> [MenuBarWidget] {
    allMenuBarWidgets.filter { $0.ownerId == sourceId }
  }

  /// All menu widgets provided by a specific source
  func menuWidgets(forSource sourceId: String) -> [MenuWidget] {
    allMenuWidgets.filter { $0.ownerId == sourceId }
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
    orderedMenuBarWidgets = sortedAllMenuBarWidgets.filter { widget in
      sourceIsEnabled(widget.ownerId) && isMenuBarWidgetVisible(widget.id)
    }
    saveConfigs()
  }

  /// Reorder all menu widgets (visible + hidden), then rebuild visible list
  func reorderAllMenu(from source: IndexSet, to destination: Int) {
    sortedAllMenuWidgets.move(fromOffsets: source, toOffset: destination)
    orderedMenuWidgets = sortedAllMenuWidgets.filter { widget in
      sourceIsEnabled(widget.ownerId) && isMenuWidgetVisible(widget.id)
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
    let enabledOwners = Set(liveSources.filter { $0.isEnabled }.map(\.id))

    // Sort by saved position (or widget priority as default)
    let sorted = widgets.sorted { lhs, rhs in
      let lhsPos = configs[lhs.id]?.position ?? lhs.priority
      let rhsPos = configs[rhs.id]?.position ?? rhs.priority
      return lhsPos < rhsPos
    }

    let ordered = sorted.filter { widget in
      let ownerEnabled = enabledOwners.contains(widget.ownerId)
      return ownerEnabled && (forcedVisibility[widget.id] ?? configs[widget.id]?.isVisible ?? true)
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

// MARK: - Weak source box

/// Weak reference box so the registry doesn't keep sources alive —
/// `PluginRegistry` owns plugins, `KeyboardNavigation` is a singleton.
private struct WeakWidgetSource {
  weak var source: (any WidgetSource)?

  init(_ source: any WidgetSource) {
    self.source = source
  }
}
