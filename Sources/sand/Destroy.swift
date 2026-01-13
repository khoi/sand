import ArgumentParser
import Foundation
import Logging

@available(macOS 14.0, *)
struct Destroy: ParsableCommand {
    @Option(name: .shortAndLong)
    var config: String = "sand.yml"

    func run() throws {
        LoggingSystem.bootstrap { label in
            StreamLogHandler.standardOutput(label: label)
        }
        let logger = Logger(label: "sand.destroy")
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
        let tart = Tart(processRunner: SystemProcessRunner())
        let destroyer = VMDestroyer(tart: tart, logger: logger)
        for runner in config.runners {
            destroyer.destroy(name: runner.name)
        }
    }
}
