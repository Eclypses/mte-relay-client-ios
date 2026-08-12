//// The MIT License (MIT)
//
// Copyright (c) Eclypses, Inc.
//
// All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import os

/// Severity levels, low → high. See `dev_docs/LOGGING_CONVENTION.md`.
/// `.off` is a sentinel used only for `minimumLevel` to silence everything.
enum RelayLogLevel: Int, Comparable {
    case trace = 0, debug, info, warning, error, fault, off

    static func < (lhs: RelayLogLevel, rhs: RelayLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Uppercased tag used in the file log.
    var name: String {
        switch self {
        case .trace:   return "TRACE"
        case .debug:   return "DEBUG"
        case .info:    return "INFO"
        case .warning: return "WARN"
        case .error:   return "ERROR"
        case .fault:   return "FAULT"
        case .off:     return "OFF"
        }
    }

    /// Map the legacy `OSLogType`-based entry point onto our levels.
    init(osLog: OSLogType) {
        switch osLog {
        case .debug:  self = .debug
        case .info:   self = .info
        case .error:  self = .error
        case .fault:  self = .fault
        default:      self = .info
        }
    }
}

// MARK: - PackageLogger Utility
struct PackageLogger {
    static var subsystem = "Relay"

    /// Minimum level actually emitted. Calls below this are cheap no-ops — the
    /// message closure is never evaluated — so disabled levels cost nothing in
    /// production. Default: `.debug` in debug builds, `.info` in release.
    #if DEBUG
    static var minimumLevel: RelayLogLevel = .debug
    #else
    static var minimumLevel: RelayLogLevel = .info
    #endif

    private static var logWriteCount = 0

    static func makeLogger(for type: Any.Type) -> LoggerWrapper {
        return LoggerWrapper(for: type)
    }

    /// True if `level` would be emitted. Callers use this to skip building a
    /// message string when the level is disabled.
    static func isEnabled(_ level: RelayLogLevel) -> Bool {
        level != .off && level >= minimumLevel
    }

    /// Back-compat entry point (used by the file-logging API in `Relay`).
    static func log(from category: String, level: OSLogType = .info, message: String) {
        write(RelayLogLevel(osLog: level), category: category, message: message)
    }

    /// The single choke point: level-gate, emit to the unified log, and (when the
    /// file toggle is on) append to the debug file.
    ///
    /// Reminder: NEVER pass secrets here — see `dev_docs/LOGGING_CONVENTION.md` §0.
    /// Everything is logged `.public`, so the no-secrets discipline is the only guard.
    static func write(_ level: RelayLogLevel, category: String, message: @autoclosure () -> String) {
        guard isEnabled(level) else { return }

        let text = message().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let logger = Logger(subsystem: subsystem, category: category)
        switch level {
        case .trace, .debug: logger.debug("\(text, privacy: .public)")
        case .info:          logger.info("\(text, privacy: .public)")
        case .warning:       logger.log(level: .default, "\(text, privacy: .public)")
        case .error:         logger.error("\(text, privacy: .public)")
        case .fault:         logger.fault("\(text, privacy: .public)")
        case .off:           return
        }

        if loggingEnabled {
            logToFile("[\(category)][\(level.name)] \(text)")
        }
    }

    static var logFileURL: URL? {
        let fm = FileManager.default
        if let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            return dir.appendingPathComponent("relay_debug_log.txt")
        }
        return nil
    }

    static var loggingEnabled: Bool = false

    static func logToFile(_ message: String) {
        guard loggingEnabled, let url = logFileURL else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = dateFormatter.string(from: Date())
        let fullMessage = "[\(timestamp)] \(message)\n"

        do {
            let data = fullMessage.data(using: .utf8)!
            if FileManager.default.fileExists(atPath: url.path) {
                let fileHandle = try FileHandle(forWritingTo: url)
                defer { fileHandle.closeFile() }
                try fileHandle.seekToEnd()
                fileHandle.write(data)
            } else {
                try data.write(to: url)
            }
            
            logWriteCount += 1

            if logWriteCount >= 1000 {
                logWriteCount = 0
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = attributes[.size] as? UInt64, fileSize > 1_048_576 {
                    trimLogFile(at: url)
                }
            }
        } catch {
            // Fail silently
        }
    }

    private static func trimLogFile(at url: URL) {
        guard let content = try? String(contentsOf: url) else { return }
        var lines = content.components(separatedBy: .newlines)
        if lines.count > 1000 {
            lines.removeFirst(1000)
            do {
                try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Fail silently
            }
        }
    }
}

struct LoggerWrapper {
    private let category: String

    init(for type: Any.Type) {
        self.category = String(describing: type)
    }

    // Messages are `@autoclosure`: when the level is disabled the string is never
    // built, so log calls on disabled levels are effectively free. See §1/§4 of
    // `dev_docs/LOGGING_CONVENTION.md` for when to use each level.
    func trace(_ message: @autoclosure () -> String)   { emit(.trace, message()) }
    func debug(_ message: @autoclosure () -> String)   { emit(.debug, message()) }
    func info(_ message: @autoclosure () -> String)    { emit(.info, message()) }
    func warning(_ message: @autoclosure () -> String) { emit(.warning, message()) }
    func error(_ message: @autoclosure () -> String)   { emit(.error, message()) }
    func fault(_ message: @autoclosure () -> String)   { emit(.fault, message()) }

    private func emit(_ level: RelayLogLevel, _ message: @autoclosure () -> String) {
        guard PackageLogger.isEnabled(level) else { return }
        PackageLogger.write(level, category: category, message: message())
    }
}

private extension String {
    func appendLine(to url: URL) throws {
        let data = (self + "\n").data(using: .utf8)!
        if FileManager.default.fileExists(atPath: url.path) {
            let fileHandle = try FileHandle(forWritingTo: url)
            defer { fileHandle.closeFile() }
            try fileHandle.seekToEnd()
            fileHandle.write(data)
        } else {
            try write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

extension NSObject {
    var className: String {
        return String(describing: type(of: self))
    }

    static var className: String {
        return String(describing: self)
    }
}
