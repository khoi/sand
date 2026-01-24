import ArgumentParser
import Foundation

struct StderrOutputStream: TextOutputStream {
    mutating func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}

@available(macOS 15.0, *)
struct Doctor: AsyncParsableCommand {
    @OptionGroup
    var logLevel: LogLevelOptions

    func run() async throws {
        var stderr = StderrOutputStream()
        let issues = await collectIssues { message in
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

    private func collectIssues(_ report: (String) -> Void) async -> [ConfigValidationIssue] {
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
            let optionalMissing = DependencyChecker.missingCommands(["scp"])
            if !optionalMissing.isEmpty {
                issues.append(.init(
                    severity: .warning,
                    message: "scp not found in PATH; runner cache preseed will be disabled."
                ))
            }
            report("- tart command health")
            issues.append(contentsOf: await checkTartHealth())
        }
        let defaultPath = Config.expandPath(Config.defaultPath)
        report("- config at \(defaultPath)")
        issues.append(contentsOf: checkConfig(at: defaultPath))
        return issues
    }

    private func checkTartHealth() async -> [ConfigValidationIssue] {
        do {
            let runner = SystemProcessRunner()
            _ = try await runner.run(executable: "tart", arguments: ["list"], wait: true)
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
            var issues = validator.validate(config)
            issues.append(contentsOf: checkRunnerCacheAssets(config))
            return issues
        } catch {
            return [ConfigValidationIssue(severity: .error, message: "Failed to load config at \(path): \(error.localizedDescription)")]
        }
    }

    private func checkRunnerCacheAssets(_ config: Config) -> [ConfigValidationIssue] {
        var issues: [ConfigValidationIssue] = []
        let fileManager = FileManager.default
        for runner in config.runners where runner.provisioner.type == .github {
            guard let cache = runner.vm.cache else { continue }
            let hostPath = cache.hostPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hostPath.isEmpty else { continue }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: hostPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            guard let entries = try? fileManager.contentsOfDirectory(atPath: hostPath) else {
                continue
            }
            let hasRunnerAsset = entries.contains { name in
                name.hasPrefix("actions-runner-") && name.hasSuffix(".tar.gz")
            }
            if !hasRunnerAsset {
                issues.append(.init(
                    severity: .warning,
                    message: "Runner cache directory has no actions-runner-*.tar.gz at \(hostPath); sand will download the runner on first boot."
                ))
            }
        }
        return issues
    }

}
