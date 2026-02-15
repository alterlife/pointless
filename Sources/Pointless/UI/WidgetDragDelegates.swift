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

    let widgets = widgetRegistry.orderedMenuBarWidgets
    guard let fromIndex = widgets.firstIndex(where: { $0.id == draggedId }),
          let toIndex = widgets.firstIndex(where: { $0.id == targetWidgetId }) else { return }

    widgetRegistry.reorderMenuBar(from: IndexSet(integer: fromIndex), to: toIndex > fromIndex ? toIndex + 1 : toIndex)
  }
}

struct MenuBarRemoveDropDelegate: DropDelegate {
  @Binding var draggedWidgetId: String?
  let widgetRegistry: WidgetRegistry

  func performDrop(info: DropInfo) -> Bool {
    if let widgetId = draggedWidgetId {
      widgetRegistry.setMenuBarVisibility(widgetId: widgetId, isVisible: false)
    }
    draggedWidgetId = nil
    return true
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

    let widgets = widgetRegistry.orderedMenuWidgets
    guard let fromIndex = widgets.firstIndex(where: { $0.id == draggedId }),
          let toIndex = widgets.firstIndex(where: { $0.id == targetWidgetId }) else { return }

    widgetRegistry.reorderMenu(from: IndexSet(integer: fromIndex), to: toIndex > fromIndex ? toIndex + 1 : toIndex)
  }
}

struct MenuRemoveDropDelegate: DropDelegate {
  @Binding var draggedWidgetId: String?
  let widgetRegistry: WidgetRegistry

  func performDrop(info: DropInfo) -> Bool {
    if let widgetId = draggedWidgetId {
      widgetRegistry.setMenuVisibility(widgetId: widgetId, isVisible: false)
    }
    draggedWidgetId = nil
    return true
  }
}
