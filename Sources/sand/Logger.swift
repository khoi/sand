import ArgumentParser
import os

enum LogLevel: String, ExpressibleByArgument, CaseIterable, Comparable, Sendable {
    case trace
    case debug
    case info
    case notice
    case warning
    case error
    case critical

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .trace:
            return 0
        case .debug:
            return 1
        case .info:
            return 2
        case .notice:
            return 3
        case .warning:
            return 4
        case .error:
            return 5
        case .critical:
            return 6
        }
    }
}

struct Logger: Sendable {
    private let logger: os.Logger
    private let minimumLevel: LogLevel
    private let fileSink: LogFileSink?
    private let label: String

    init(label: String, minimumLevel: LogLevel, sink: LogFileSink? = nil) {
        logger = os.Logger(subsystem: "sand", category: label)
        self.minimumLevel = minimumLevel
        self.fileSink = sink
        self.label = label
    }

    func trace(_ message: String) {
        log(.trace, message)
    }

    func debug(_ message: String) {
        log(.debug, message)
    }

    func info(_ message: String) {
        log(.info, message)
    }

    func notice(_ message: String) {
        log(.notice, message)
    }

    func warning(_ message: String) {
        log(.warning, message)
    }

    func error(_ message: String) {
        log(.error, message)
    }

    func critical(_ message: String) {
        log(.critical, message)
    }

    func log(_ level: LogLevel, _ message: String) {
        guard level >= minimumLevel else {
            return
        }
        switch level {
        case .trace:
            logger.debug("\(message, privacy: .public)")
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .notice:
            logger.notice("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .critical:
            logger.fault("\(message, privacy: .public)")
        }
        fileSink?.writeSync(level: level, label: label, message: message)
    }
}
