import ArgumentParser
import Foundation

struct LogLevelOptions: ParsableArguments {
    @Option(name: .long, help: ArgumentHelp("Log level: trace, debug, info, notice, warning, error, critical.", valueName: "level"))
    var logLevel: LogLevel?

    @Flag(name: .shortAndLong, help: "Increase verbosity (-v, -vv, -vvv, -vvvv).")
    var verbose: Int

    @Option(name: .long, help: ArgumentHelp("Write logs to a file.", valueName: "path"))
    var logFile: String?

    func resolvedLevel() -> LogLevel {
        if let logLevel {
            return logLevel
        }
        switch verbose {
        case 0:
            return .info
        case 1:
            return .debug
        default:
            return .trace
        }
    }

    func resolvedLogFile() -> String? {
        if let logFile, !logFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return logFile
        }
        let env = ProcessInfo.processInfo.environment["SAND_LOG_FILE"] ?? ""
        return env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : env
    }

    func makeLogFileSink() throws -> LogFileSink? {
        guard let path = resolvedLogFile() else {
            return nil
        }
        return try LogFileSink(path: path)
    }
}
