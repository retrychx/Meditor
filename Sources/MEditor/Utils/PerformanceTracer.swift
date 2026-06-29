import os

/// Centralized os_signpost tracing for Instruments profiling.
/// Open the `.trace` file in Instruments → "os_signpost" instrument to visualize.
enum PerformanceTracer {
    // MARK: - Subsystem Logs
    static let fileOps = OSLog(subsystem: "com.meditor", category: "FileOps")
    static let editor  = OSLog(subsystem: "com.meditor", category: "Editor")
    static let preview = OSLog(subsystem: "com.meditor", category: "Preview")
    static let session = OSLog(subsystem: "com.meditor", category: "Session")

    // MARK: - Interval API (begin/end pairs for Instruments Time Profiler)

    static func begin(_ name: StaticString, log: OSLog = fileOps) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, log: OSLog = fileOps, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }

    // MARK: - Event (single point-in-time marker)

    static func event(_ name: StaticString, log: OSLog = fileOps) {
        os_signpost(.event, log: log, name: name)
    }
}
