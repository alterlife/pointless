import Foundation
import OSLog

/// Minimal logging wrapper around os.Logger with environment-based configuration
///
/// Usage:
///   Logger.info("App started")
///   Logger.warning("Plugin conflict detected")
///   Logger.error("Failed to load bundle")
///   Logger.debug("CPU value updated")  // Only shown if POINTLESS_LOG_LEVEL=debug
///
/// Environment variable control:
///   POINTLESS_LOG_LEVEL=debug   → Show all logs (debug, info, warning, error)
///   POINTLESS_LOG_LEVEL=info    → Default (info, warning, error)
///   POINTLESS_LOG_LEVEL=warning → Only warnings and errors
///   POINTLESS_LOG_LEVEL=error   → Only errors
///
/// Logs are sent to unified logging system (viewable in Console.app):
///   - Filter by subsystem: "com.alterlife.pointless"
///   - Or command line: log stream --predicate 'subsystem == "com.alterlife.pointless"'
enum Logger {
  // MARK: - Configuration

  private static let subsystem = "com.alterlife.pointless"

  /// Minimum log level to display (configured via POINTLESS_LOG_LEVEL env var)
  private static let minimumLevel: LogLevel = {
    guard let envValue = ProcessInfo.processInfo.environment["POINTLESS_LOG_LEVEL"] else {
      return .info  // Default: show info and above
    }

    switch envValue.lowercased() {
    case "debug":
      return .debug
    case "info":
      return .info
    case "warning":
      return .warning
    case "error":
      return .error
    default:
      return .info
    }
  }()

  // MARK: - Log Levels

  private enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }

  // MARK: - Subsystem Loggers

  /// Logger for plugin registry operations (registration, loading)
  static let pluginRegistry = os.Logger(subsystem: subsystem, category: "plugin-registry")

  /// Logger for plugin lifecycle events (start, stop, updates)
  static let pluginLifecycle = os.Logger(subsystem: subsystem, category: "plugin-lifecycle")

  /// Logger for app-level events (startup, shutdown)
  static let app = os.Logger(subsystem: subsystem, category: "app")

  /// Logger for UI-related events
  static let userInterface = os.Logger(subsystem: subsystem, category: "ui")

  // MARK: - Convenience Methods

  /// Log debug-level message (only shown if POINTLESS_LOG_LEVEL=debug)
  static func debug(_ message: String, logger: os.Logger = pluginLifecycle) {
    guard minimumLevel <= .debug else { return }
    let formatted = "🔍 \(message)"
    logger.debug("\(formatted, privacy: .public)")
    print(formatted)  // Debug mode always prints to console
  }

  /// Log informational message (normal operation)
  static func info(_ message: String, logger: os.Logger = app) {
    guard minimumLevel <= .info else { return }
    let formatted = "✅ \(message)"
    logger.info("\(formatted, privacy: .public)")
    if minimumLevel == .debug { print(formatted) }
  }

  /// Log warning message (recoverable issue)
  static func warning(_ message: String, logger: os.Logger = pluginRegistry) {
    guard minimumLevel <= .warning else { return }
    let formatted = "⚠️ \(message)"
    logger.warning("\(formatted, privacy: .public)")
    if minimumLevel == .debug { print(formatted) }
  }

  /// Log error message (failure condition)
  static func error(_ message: String, logger: os.Logger = pluginRegistry) {
    guard minimumLevel <= .error else { return }
    let formatted = "❌ \(message)"
    logger.error("\(formatted, privacy: .public)")
    if minimumLevel == .debug { print(formatted) }
  }
}
