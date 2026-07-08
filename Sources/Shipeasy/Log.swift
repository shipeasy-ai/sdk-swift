import Foundation

// MARK: - Leveled logging
//
// Uniform, cross-SDK log contract (mirrors `@shipeasy/sdk`): a single ordered
// severity scale and a process-global logger that gates before writing to
// stderr. Logging must NEVER trap — the write is a best-effort side channel and
// a failure to log can never surface into caller code.
//
// Ordering: silent < error < warn < info < debug. A message at level `L` is
// emitted iff the configured level is `>= L` (i.e. verbose enough to include it).

/// Severity scale for the SDK's own diagnostic logging. Set via the `logLevel`
/// parameter on `configure(...)` / `Engine.init(...)`. `.silent` mutes all SDK
/// logs; `.warn` (the default) surfaces warnings and errors.
public enum LogLevel: Int, Sendable, Comparable {
    case silent = 0
    case error = 1
    case warn = 2
    case info = 3
    case debug = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Process-global, leveled logger backing the SDK's diagnostics. The level is a
/// single stored global set from `Engine.init` (last engine wins, matching the
/// default-client wiring). Writes to stderr and never throws or traps — a
/// failure to log is swallowed, by design.
enum Log {
    // Guarded stored global level. Default `.warn` so an unconfigured process
    // (e.g. a raw `see()` before any Engine) still surfaces warnings.
    private static let lock = NSLock()
    private static var _level: LogLevel = .warn

    /// Optional test sink: when set, formatted lines are handed here INSTEAD of
    /// stderr (still gated by level). Test-only.
    private static var _sink: (@Sendable (LogLevel, String) -> Void)?

    static var level: LogLevel {
        get { lock.lock(); defer { lock.unlock() }; return _level }
        set { lock.lock(); defer { lock.unlock() }; _level = newValue }
    }

    /// Install a test sink that receives `(level, message)` for every emitted
    /// line instead of the stderr write. Pass `nil` to restore stderr. Test-only.
    static func setSink(_ sink: (@Sendable (LogLevel, String) -> Void)?) {
        lock.lock(); defer { lock.unlock() }
        _sink = sink
    }

    static func error(_ msg: @autoclosure () -> String) { emit(.error, msg()) }
    static func warn(_ msg: @autoclosure () -> String) { emit(.warn, msg()) }
    static func info(_ msg: @autoclosure () -> String) { emit(.info, msg()) }
    static func debug(_ msg: @autoclosure () -> String) { emit(.debug, msg()) }

    // Emit at `level` iff the configured level is verbose enough to include it.
    // Never throws or traps.
    private static func emit(_ level: LogLevel, _ msg: String) {
        let (enabled, sink): (Bool, (@Sendable (LogLevel, String) -> Void)?) = {
            lock.lock(); defer { lock.unlock() }
            return (_level >= level, _sink)
        }()
        guard enabled else { return }
        if let sink {
            sink(level, msg)
            return
        }
        let line = "[shipeasy] \(msg)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
