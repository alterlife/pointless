import SwiftUI

// MARK: - Widget Drop Delegates

/// Drop delegate for menu bar widget reordering
typealias MenuBarActiveDropDelegate = WidgetDropDelegate<MenuBarWidget>

/// Drop delegate for menu widget reordering
typealias MenuActiveDropDelegate = WidgetDropDelegate<MenuWidget>

/// Generic drop delegate that handles drag-to-reorder for any widget list
struct WidgetDropDelegate<W: WidgetProtocol>: DropDelegate {
  let targetWidgetId: String
  @Binding var draggedWidgetId: String?
  let widgetRegistry: WidgetRegistry
  let currentOrder: (WidgetRegistry) -> [W]
  let reorder: (WidgetRegistry, IndexSet, Int) -> Void

  func performDrop(info: DropInfo) -> Bool {
    draggedWidgetId = nil
    return true
  }

  func dropEntered(info: DropInfo) {
    guard let draggedId = draggedWidgetId, draggedId != targetWidgetId else { return }
    let widgets = currentOrder(widgetRegistry)
    guard let fromIndex = widgets.firstIndex(where: { $0.id == draggedId }),
          let toIndex = widgets.firstIndex(where: { $0.id == targetWidgetId }) else { return }
    reorder(widgetRegistry, IndexSet(integer: fromIndex), toIndex > fromIndex ? toIndex + 1 : toIndex)
  }
}

extension WidgetDropDelegate where W == MenuBarWidget {
  init(
    targetWidgetId: String,
    draggedWidgetId: Binding<String?>,
    widgetRegistry: WidgetRegistry
  ) {
    self.targetWidgetId = targetWidgetId
    self._draggedWidgetId = draggedWidgetId
    self.widgetRegistry = widgetRegistry
    self.currentOrder = { $0.sortedAllMenuBarWidgets }
    self.reorder = { $0.reorderAllMenuBar(from: $1, to: $2) }
  }
}

extension WidgetDropDelegate where W == MenuWidget {
  init(
    targetWidgetId: String,
    draggedWidgetId: Binding<String?>,
    widgetRegistry: WidgetRegistry
  ) {
    self.targetWidgetId = targetWidgetId
    self._draggedWidgetId = draggedWidgetId
    self.widgetRegistry = widgetRegistry
    self.currentOrder = { $0.sortedAllMenuWidgets }
    self.reorder = { $0.reorderAllMenu(from: $1, to: $2) }
  }
}
