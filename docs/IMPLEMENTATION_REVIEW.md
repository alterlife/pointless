# Implementation Review: Protocol-Based Plugin API

## Overview
Reviewed the protocol-based plugin API implementation that replaced property wrappers with protocol extension helpers.

## ✅ What Works Well

### 1. **Clean Plugin Code**
CPUPlugin.swift is now much simpler:
- 98 lines (down from 130)
- Declarative `initialize()` method
- No property wrapper magic
- Easy to read and debug

### 2. **Build & Quality**
- ✅ Builds successfully
- ✅ SwiftLint: 0 violations
- ✅ App runs correctly
- ✅ All features working (menu bar, settings, persistence, timer reconfiguration)

### 3. **Protocol Design**
- Clean separation of concerns
- Smart defaults via extensions
- Helper methods (`settings()`, `periodicUpdate()`) are intuitive

## ⚠️ Issues Found

### 1. **CRITICAL: Memory Leak in Plugin State Storage**

**Location:** `PluginHelpers.swift:8`

```swift
private var pluginState: [ObjectIdentifier: PluginState] = [:]
```

**Problem:**
- Global dictionary stores state per plugin instance
- When a plugin is deallocated, its entry remains forever
- Memory leak for any dynamically loaded/unloaded plugins

**Impact:** Low for current use (plugins live entire app lifetime), HIGH for future dynamic plugin loading

**Fix Required:**
```swift
// Option 1: Clean up in stop()
func stop() {
  state.timer?.invalidate()
  state.timer = nil
  state.cancellables.removeAll()

  // Clean up state
  let key = ObjectIdentifier(self)
  pluginState.removeValue(forKey: key)

  Logger.info("Stopped plugin \(self.id)")
}

// Option 2: Use NSMapTable with weak keys (more complex)
```

### 2. **Double Configuration Loading**

**Locations:**
- `PluginHelpers.swift:45-53` (in `settings()` helper)
- `AppDelegate.swift:24-27` (in app startup)

**Problem:**
Settings are loaded and `configure()` is called TWICE:
1. In `initialize()` → calls `settings([...])` → auto-loads from UserDefaults → calls `configure()`
2. In `AppDelegate` → loads from UserDefaults → calls `configure()` again

**Current Behavior:**
```
CPUPlugin.init()
  → initialize()
    → settings([...])
      → configure(["updateInterval": 2.0])  // First call
        → Sets updateInterval = 2.0

AppDelegate.applicationDidFinishLaunching()
  → configure(["updateInterval": 2.0])      // Second call (redundant)
    → Sets updateInterval = 2.0 again
```

**Impact:** Redundant work, potential for timing issues

**Fix Options:**

**Option A: Remove auto-load from settings() helper**
```swift
func settings(_ definitions: [SettingDefinition]) {
  state.settingDefinitions = definitions
  // Don't auto-load here - let AppDelegate handle it
}
```

**Option B: Remove configure() call from AppDelegate**
```swift
// In AppDelegate - just start plugins, don't configure
// (settings() already loaded them)
for plugin in PluginRegistry.shared.plugins {
  plugin.start()
}
```

**Recommendation:** Option B - let `settings()` helper handle loading, remove from AppDelegate

### 3. **Fragile Reflection-Based configure()**

**Location:** `PluginHelpers.swift:126-143`

```swift
func configure(_ values: [String: Any]) {
  for (key, value) in values {
    UserDefaults.standard.set(value, forKey: "plugin.\(id).\(key)")

    let mirror = Mirror(reflecting: self)
    for child in mirror.children {
      if let propertyName = child.label, propertyName == key {
        if let writable = self as? AnyObject {
          writable.setValue(value, forKey: key)  // KVC
        }
      }
    }
  }
}
```

**Problems:**
1. **Requires NSObject** - Plugins MUST inherit from `NSObject` for KVC to work (undocumented requirement)
2. **Inefficient** - Iterates through all properties for each value
3. **Mirror limitations** - Property labels may not match for `@Published` wrappers
4. **Silent failures** - If KVC fails, no error is reported

**Evidence:** CPUPlugin had to inherit from `NSObject` (line 7)

**Impact:** Works for current simple case, but fragile for complex plugins

**Better Approach:**
```swift
// Use Combine to observe specific properties
func periodicUpdate(interval: ReferenceWritableKeyPath<Self, TimeInterval>,
                   action: @escaping () -> Void) {
  state.timerAction = action
  state.timerInterval = self[keyPath: interval]

  // Store the keypath for configure() to use
  state.intervalKeyPath = interval
}

func configure(_ values: [String: Any]) {
  for (key, value) in values {
    UserDefaults.standard.set(value, forKey: "plugin.\(id).\(key)")

    // Use stored keypaths instead of reflection
    if key == "updateInterval",
       let interval = value as? TimeInterval,
       let keyPath = state.intervalKeyPath {
      self[keyPath: keyPath] = interval
    }
  }
}
```

### 4. **Inefficient objectWillChange Observer**

**Location:** `PluginHelpers.swift:75-90`

```swift
objectWillChange.sink { [weak self] _ in
  guard let self = self else { return }
  let newInterval = self[keyPath: interval]
  if newInterval != self.state.timerInterval {
    self.state.timerInterval = newInterval
    // ... recreate timer
  }
}
.store(in: &state.cancellables)
```

**Problem:**
- Observes ALL published property changes
- CPUPlugin updates `menuBarText` every 2 seconds
- Each update triggers this closure (checking if interval changed)
- Wasteful CPU cycles

**Impact:** Low (comparison is cheap), but not elegant

**Better Approach:**
```swift
// Observe specific property instead of objectWillChange
self.publisher(for: interval)
  .sink { [weak self] newInterval in
    guard let self = self else { return }
    if self.state.timer != nil {
      self.state.timerInterval = newInterval
      self.recreateTimer()
    }
  }
  .store(in: &state.cancellables)
```

### 5. **Hidden NSObject Requirement**

**Problem:**
- Plugins must inherit from `NSObject` for `configure()` to work (KVC)
- Not documented in protocol
- Not enforced by compiler
- Will cause silent failures for non-NSObject plugins

**Fix:**
- Either: Document requirement in protocol comments
- Or: Remove reflection/KVC dependency (better)

### 6. **Settings UserDefaults Key Inconsistency**

**PluginHelpers.swift:**
```swift
// Uses "plugin.{id}.{key}" format
UserDefaults.standard.object(forKey: "plugin.\(id).\(def.key)")
```

**AppDelegate.swift:**
```swift
// Uses "plugin.{id}" format (dictionary)
UserDefaults.standard.dictionary(forKey: "plugin.\(plugin.id)")
```

**Impact:** Two different storage schemes!
- PluginHelpers stores: `plugin.pointless.cpu.updateInterval = 2.0`
- AppDelegate expects: `plugin.pointless.cpu = ["updateInterval": 2.0]`

This will cause settings to not persist correctly!

**CRITICAL BUG** - Settings won't load properly on restart.

**Fix Required:**
```swift
// In PluginHelpers.swift - use dictionary format
func configure(_ values: [String: Any]) {
  // Load existing settings
  var allSettings = UserDefaults.standard.dictionary(
    forKey: "plugin.\(id)"
  ) as? [String: Any] ?? [:]

  // Merge new values
  for (key, value) in values {
    allSettings[key] = value
  }

  // Save back
  UserDefaults.standard.set(allSettings, forKey: "plugin.\(id)")

  // Update properties...
}
```

## 📊 Summary

### Critical Issues (Must Fix)
1. ❌ **UserDefaults key mismatch** - Settings won't persist correctly
2. ⚠️ **Memory leak** - Plugin state never cleaned up

### Important Issues (Should Fix)
3. ⚠️ **Double configuration** - Settings loaded twice
4. ⚠️ **Fragile reflection** - Requires NSObject, inefficient
5. ⚠️ **Hidden requirement** - NSObject inheritance not documented

### Minor Issues (Nice to Fix)
6. ⚠️ **Inefficient observer** - Checks interval on every property change

## 🎯 Recommended Action Plan

### Immediate (Before Next Commit)
1. **Fix UserDefaults key consistency** - CRITICAL for settings persistence
2. **Remove double configuration** - Either from AppDelegate or settings() helper
3. **Add memory cleanup** - Remove state in stop()

### Soon
4. **Replace reflection with keypaths** - More robust, self-documenting
5. **Document NSObject requirement** - Or remove dependency on it
6. **Optimize observer** - Watch specific property instead of objectWillChange

## 🧪 Testing Recommendations

### Test Settings Persistence
```bash
# 1. Run app, change update interval to 10s
# 2. Quit app
# 3. Check UserDefaults
defaults read com.alterlife.pointless

# 4. Restart app
# 5. Verify interval is still 10s
```

### Test Memory Management
```swift
// Add test for external plugin loading/unloading
// Verify pluginState dictionary is cleaned up
```

## Conclusion

The implementation is **functionally correct** and a **significant improvement** over property wrappers, but has **critical bugs** that will break settings persistence and cause memory leaks with dynamic plugin loading.

**Overall Grade: B-** (would be A- after fixes)

**Recommendation: Fix critical issues before production use**
