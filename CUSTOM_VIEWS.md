# Custom Menu Bar Views - Plugin Examples

## Overview

Plugins can now provide **custom graphics** for the menu bar! Each plugin has complete control over its menu bar appearance using SwiftUI.

## Current Implementation: CPUPlugin

The CPU plugin now shows:
- 🟢 **Green dot** when CPU < 50%
- 🟡 **Yellow dot** when CPU 50-80%
- 🔴 **Red dot** when CPU > 80%
- **CPU icon** (system symbol)
- **Percentage** in monospace font

```
[🟢] [CPU icon] 42%
```

## How Plugins Control Graphics

### Protocol Method
```swift
protocol Plugin: ObservableObject {
  func menuBarView() -> NSView?  // Return nil to use text fallback
}
```

### Example: CPUPlugin
```swift
func menuBarView() -> NSView? {
  let view = NSHostingView(rootView:
    HStack(spacing: 4) {
      // Color-coded dot
      Circle()
        .fill(statusColor)  // green/yellow/red based on usage
        .frame(width: 6, height: 6)

      // Icon
      Image(systemName: "cpu")
        .font(.system(size: 11))

      // Data
      Text(String(format: "%.0f%%", cpuUsage * 100))
        .font(.system(size: 12, weight: .medium, design: .monospaced))
    }
  )
  return view
}
```

## What Plugins Can Render

### Simple Graphics
- **Icons** - SF Symbols, custom images
- **Colored indicators** - dots, bars, badges
- **Styled text** - fonts, weights, colors

### Advanced Graphics
- **Mini charts** - bar graphs, sparklines
- **Gauges** - circular progress, meters
- **Animations** - pulsing, fading, rotating
- **Custom drawings** - any SwiftUI shape/path

## Example Ideas

### Memory Plugin
```
[🔵] [Memory icon] 8.2 GB
```

### Network Plugin
```
[↓ 2.1 MB/s] [↑ 0.8 MB/s]
```

### Battery Plugin
```
[🔋 █████░░░░░] 73%
```

### Keyboard Plugin
```
[⌨️] 120 WPM [████████░░]
```

### Mini Graph Plugin
```
CPU: [▁▂▃▅▇█▇▅▃]
```

## Layout

Multiple plugins are combined horizontally:
```
[🟢 CPU 42%] | [🔵 MEM 8.2GB] | [⌨️ 120 WPM]
```

## Fallback

If a plugin returns `nil` from `menuBarView()`, the system uses `menuBarText` instead:
```swift
// Simple text fallback
var menuBarText: String { "CPU 42%" }
```

## Performance

- Views update automatically when plugin `@Published` properties change
- Rendering is lightweight (SwiftUI)
- Each plugin controls its own update frequency
