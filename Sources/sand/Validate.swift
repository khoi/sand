import ArgumentParser
import Foundation

@available(macOS 14.0, *)
struct Validate: ParsableCommand {
    @Option(name: .shortAndLong)
    var config: String = Config.defaultPath
    @OptionGroup
    var logLevel: LogLevelOptions

    func run() throws {
        let expandedPath = Config.expandPath(config)
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw ValidationError("Config file not found at \(expandedPath).")
        }
        do {
            let config = try Config.load(path: expandedPath)
            let validator = ConfigValidator()
            let issues = validator.validate(config)
            let errors = issues.filter { $0.severity == .error }
            if issues.isEmpty {
                print("Config is valid.")
                return
            }
            print("sand validate found issues:")
            for issue in issues {
                print("- [\(issue.severity.rawValue)] \(issue.message)")
            }
            if !errors.isEmpty {
                throw ExitCode(1)
            }
        } catch {
            throw ValidationError("Failed to load config at \(expandedPath): \(error.localizedDescription)")
        }
    }
}
