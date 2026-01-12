import ArgumentParser
import Foundation
import Logging

@available(macOS 14.0, *)
struct Doctor: ParsableCommand {
    func run() throws {
        LoggingSystem.bootstrap { label in
            StreamLogHandler.standardOutput(label: label)
        }
        let issues = collectIssues()
        let errors = issues.filter { $0.severity == .error }
        if issues.isEmpty {
            print("Your system is ready to run sand.")
            return
        }
        print("sand doctor found issues:")
        for issue in issues {
            print("- [\(issue.severity.rawValue)] \(issue.message)")
        }
        if !errors.isEmpty {
            throw ExitCode(1)
        }
    }

    private func collectIssues() -> [ConfigValidationIssue] {
        var issues: [ConfigValidationIssue] = []
        let missing = DependencyChecker.missingCommands(["tart", "sshpass", "ssh"])
        if !missing.isEmpty {
            issues.append(.init(
                severity: .error,
                message: "Missing required dependencies in PATH: \(missing.joined(separator: ", "))."
            ))
        } else {
            issues.append(contentsOf: checkTartHealth())
        }
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

}
