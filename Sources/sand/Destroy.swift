import ArgumentParser
import Foundation

@available(macOS 15.0, *)
struct Destroy: ParsableCommand {
    @Option(name: .shortAndLong)
    var config: String = "sand.yml"
    @OptionGroup
    var logLevel: LogLevelOptions

    func run() throws {
        let level = logLevel.resolvedLevel()
        let logger = Logger(label: "sand.destroy", minimumLevel: level)
        let missing = DependencyChecker.missingCommands(["tart"])
        if !missing.isEmpty {
            throw ValidationError("Missing required dependencies in PATH: \(missing.joined(separator: ", ")). Install them and re-run.")
        }
        let config = try Config.load(path: config)
        let validator = ConfigValidator()
        let issues = validator.validate(config)
        let errors = issues.filter { $0.severity == .error }
        if !errors.isEmpty {
            let message = errors.map(\.message).joined(separator: " ")
            throw ValidationError("Config validation failed: \(message)")
        }
        for warning in issues where warning.severity == .warning {
            logger.warning("\(warning.message)")
        }
        let tart = Tart(processRunner: SystemProcessRunner(), logger: Logger(label: "tart.destroy", minimumLevel: level))
        let destroyer = VMDestroyer(tart: tart, logger: logger)
        var firstError: Error?
        for runner in config.runners {
            do {
                try destroyer.destroy(name: runner.name)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw firstError
        }
    }
}
