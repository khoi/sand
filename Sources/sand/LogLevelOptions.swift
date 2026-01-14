import ArgumentParser

struct LogLevelOptions: ParsableArguments {
    @Option(name: .long, help: ArgumentHelp("Log level: trace, debug, info, notice, warning, error, critical.", valueName: "level"))
    var logLevel: LogLevel?

    @Flag(name: .shortAndLong, help: "Increase verbosity (-v, -vv, -vvv, -vvvv).")
    var verbose: Int

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
}
