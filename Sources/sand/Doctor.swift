import ArgumentParser
import Foundation

struct StderrOutputStream: TextOutputStream {
    mutating func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}

@available(macOS 14.0, *)
struct Doctor: ParsableCommand {
    @OptionGroup
    var logLevel: LogLevelOptions

    func run() throws {
        var stderr = StderrOutputStream()
        let issues = collectIssues { message in
            print(message, to: &stderr)
        }
        let errors = issues.filter { $0.severity == .error }
        if issues.isEmpty {
            print("Your system is ready to run sand.", to: &stderr)
            return
        }
        print("sand doctor found issues:", to: &stderr)
        for issue in issues {
            print("- [\(issue.severity.rawValue)] \(issue.message)", to: &stderr)
        }
        if !errors.isEmpty {
            throw ExitCode(1)
        }
    }

    private func collectIssues(_ report: (String) -> Void) -> [ConfigValidationIssue] {
        var issues: [ConfigValidationIssue] = []
        let dependencies = ["tart", "sshpass", "ssh"]
        report("sand doctor checks:")
        report("- dependencies: \(dependencies.joined(separator: ", "))")
        let missing = DependencyChecker.missingCommands(dependencies)
        if !missing.isEmpty {
            issues.append(.init(
                severity: .error,
                message: "Missing required dependencies in PATH: \(missing.joined(separator: ", "))."
            ))
        } else {
            report("- tart command health")
            issues.append(contentsOf: checkTartHealth())
        }
        let defaultPath = Config.expandPath(Config.defaultPath)
        report("- config at \(defaultPath)")
        issues.append(contentsOf: checkConfig(at: defaultPath))
        return issues
    }

    private func checkTartHealth() -> [ConfigValidationIssue] {
        do {
            let runner = SystemProcessRunner()
            _ = try runner.run(executable: "tart", arguments: ["list"], wait: true)
            return []
        } catch {
            return [ConfigValidationIssue(severity: .error, message: "tart command failed to run. Verify Tart is installed and working.")]
        }
    }

    private func checkConfig(at path: String) -> [ConfigValidationIssue] {
        guard FileManager.default.fileExists(atPath: path) else {
            return []
        }
        return validateConfig(at: path)
    }

    private func validateConfig(at path: String) -> [ConfigValidationIssue] {
        do {
            let config = try Config.load(path: path)
            let validator = ConfigValidator()
            return validator.validate(config)
        } catch {
            return [ConfigValidationIssue(severity: .error, message: "Failed to load config at \(path): \(error.localizedDescription)")]
        }
    }

}
