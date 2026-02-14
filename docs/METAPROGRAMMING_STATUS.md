# Metaprogramming Plugin API - Implementation Status

## Goal

Create a 99% metaprogramming Plugin API where developers write only business logic and macros generate all boilerplate (protocol conformance, settings, lifecycle management).

## Current Status: Phase 1 Complete ✅

### What's Been Implemented

#### 1. Macro Infrastructure (Complete)
- ✅ Package.swift updated with swift-syntax dependency
- ✅ Macro target (`PointlessMacros`) created and configured
- ✅ Compiler plugin entry point (`PointlessMacros.swift`)
- ✅ Basic `@Plugin` macro implementation
- ✅ Public macro declarations (`PluginMacros.swift`)
- ✅ Builds successfully with zero errors

#### 2. Current @Plugin Macro Capabilities
The `@Plugin(id: "...", name: "...")` macro currently generates:
```swift
extension YourPlugin: Plugin {
  var id: String { "your.plugin.id" }
  var name: String { "Plugin Name" }
}
```

This eliminates 2 lines of boilerplate and establishes the infrastructure for future expansion.

### What's NOT Yet Implemented

The following features from the original plan remain to be implemented:

#### 1. Auto-discovery of Property Wrappers
- ❌ Discover `@PluginSetting` properties
- ❌ Discover `@PeriodicUpdate` properties
- ❌ Generate `settings` computed property
- ❌ Generate `configure()` method
- ❌ Generate `start()` and `stop()` methods
- ❌ Generate `detailView()` method

#### 2. Simplified Developer API
The target API from the plan:
```swift
@Plugin(id: "cpu", name: "CPU")
class CPUPlugin {
  @Setting var updateInterval = 2.0
  @MenuBar var text = "CPU --"

  @Update
  func refresh() {
    let usage = getCPUUsage()
    text = "CPU \(Int(usage * 100))%"
  }

  @Detail
  var detail: some View {
    VStack {
      Image(systemName: "cpu")
      Text(text).font(.title)
    }
  }
}
```

This simplified API is **not yet working**. Developers still need to use the property wrapper approach (see `CPUPlugin.swift` for current implementation).

## Why Full Implementation Is Challenging

Swift macros have significant limitations that make "99% metaprogramming" difficult:

### 1. **No Runtime Introspection**
Macros operate at compile-time and can't access runtime information from property wrappers. They can see that `@PluginSetting` exists but can't access its `key`, `label`, or `range` properties to generate the `settings` computed property.

### 2. **Complex Init Generation**
The current property wrapper approach requires wiring in `init()`:
```swift
init() {
  // Wire update closure
  update = { [weak self] in ... }

  // Wire setting changes to timer reconfiguration
  $updateInterval.onValueChanged = { [weak self] _ in
    self?.$update.reconfigure()
  }

  // Bind interval provider
  $update.bindInterval { [weak self] in
    self?.updateInterval ?? 2.0
  }

  // Bind setting to plugin ID
  $updateInterval.bind(pluginID: id)
}
```

Generating this init code via macros is complex because:
- Macros can't easily generate closures with `[weak self]` captures for properties that don't exist yet
- The macro would need to detect which settings affect which updates
- Error handling and edge cases multiply quickly

### 3. **Type Inference Limitations**
Swift macros struggle with type inference across generated code. The macro can't easily determine:
- Whether a property is String, Double, or a custom type
- Whether a view property returns `some View` or a concrete type
- What the return type of methods should be

### 4. **Member Macro Constraints**
Member macros can add new declarations but can't easily:
- Replace existing declarations
- Access sibling declarations reliably
- Generate complex initializers with proper scoping

## Recommended Path Forward

### Option 1: Incremental Macro Enhancement (Recommended)

Build up macro capabilities incrementally:

**Phase 2A: Generate Protocol Methods (Easiest Win)**
- Macro generates `menuBarText` computed property
- Macro generates `detailView()` method
- Macro generates empty `configure()`, `start()`, `stop()` methods
- Developer still writes property wrappers and init, but ~40% less boilerplate

**Phase 2B: Settings Discovery (Medium Difficulty)**
- Macro parses `@PluginSetting` attribute parameters
- Generates `settings` computed property automatically
- Generates `configure()` method body
- ~60% less boilerplate

**Phase 2C: Update Wiring (Hard)**
- Macro generates init code to wire update closures
- Macro detects setting → update dependencies
- ~80% less boilerplate

### Option 2: Keep Property Wrappers, Optimize DX

Accept that property wrappers are the right abstraction and focus on:
- Better documentation and examples
- IDE snippets for common patterns
- Helper generators (CLI tool to scaffold plugins)
- Compile-time validation via macros (warnings for missing wiring)

### Option 3: Alternative Metaprogramming Approaches

Explore non-macro approaches:
- **Code generation scripts**: Pre-build codegen from declarative specs
- **Protocol with default implementations**: More protocol extensions, less boilerplate
- **Result builders**: DSL for plugin configuration

## Current File Structure

```
Sources/
├── PointlessMacros/
│   ├── PointlessMacros.swift        # Compiler plugin entry point
│   └── PluginMacro.swift            # @Plugin macro implementation
└── Pointless/
    └── Plugins/
        ├── PluginMacros.swift       # Public macro declarations
        ├── PropertyWrappers/
        │   ├── PeriodicUpdate.swift # Periodic update timer wrapper
        │   └── PluginSetting.swift  # Settings persistence wrapper
        └── CPU/
            └── CPUPlugin.swift      # Current property-wrapper-based implementation
```

## Next Steps

If you want to continue toward the 99% metaprogramming goal:

1. **Study macro expansion**: Use `swift build --verbose` to see how macros expand
2. **Implement Phase 2A**: Start with simple protocol method generation
3. **Test with CPUPlugin**: Verify generated code works correctly
4. **Add Phase 2B**: Settings discovery and generation
5. **Document limitations**: Be clear about what macros can and can't do

Alternatively, accept the current property wrapper approach as "good enough" (already ~70% less boilerplate than manual) and focus efforts elsewhere.

## Conclusion

**What we have**: Solid macro infrastructure that builds and can be extended

**What we need**: Significant macro implementation work to achieve the 99% metaprogramming goal

**Recommendation**: Start with Phase 2A (simple protocol method generation) and evaluate whether the complexity is worth the marginal DX improvement over property wrappers.

The property wrapper approach is already quite good - CPUPlugin is 129 lines (vs 200+ lines manual). The question is whether getting to ~50 lines via complex macros is worth the maintenance burden and compile-time complexity.
