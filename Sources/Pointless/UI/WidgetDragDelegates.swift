import SwiftUI

// MARK: - Menu Bar Drag Delegates

struct MenuBarActiveDropDelegate: DropDelegate {
  let targetWidgetId: String
  @Binding var draggedWidgetId: String?
  let widgetRegistry: WidgetRegistry

  func performDrop(info: DropInfo) -> Bool {
    draggedWidgetId = nil
    return true
  }

  func dropEntered(info: DropInfo) {
    guard let draggedId = draggedWidgetId, draggedId != targetWidgetId else { return }

    let widgets = widgetRegistry.sortedAllMenuBarWidgets
    guard let fromIndex = widgets.firstIndex(where: { $0.id == draggedId }),
          let toIndex = widgets.firstIndex(where: { $0.id == targetWidgetId }) else { return }

    widgetRegistry.reorderAllMenuBar(
      from: IndexSet(integer: fromIndex),
      to: toIndex > fromIndex ? toIndex + 1 : toIndex
    )
  }
}

// MARK: - Menu Drag Delegates

struct MenuActiveDropDelegate: DropDelegate {
  let targetWidgetId: String
  @Binding var draggedWidgetId: String?
  let widgetRegistry: WidgetRegistry

  func performDrop(info: DropInfo) -> Bool {
    draggedWidgetId = nil
    return true
  }

  func dropEntered(info: DropInfo) {
    guard let draggedId = draggedWidgetId, draggedId != targetWidgetId else { return }

    let widgets = widgetRegistry.sortedAllMenuWidgets
    guard let fromIndex = widgets.firstIndex(where: { $0.id == draggedId }),
          let toIndex = widgets.firstIndex(where: { $0.id == targetWidgetId }) else { return }

    widgetRegistry.reorderAllMenu(
      from: IndexSet(integer: fromIndex),
      to: toIndex > fromIndex ? toIndex + 1 : toIndex
    )
  }
}
