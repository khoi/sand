import Foundation

struct ConfigValidationIssue: Equatable {
    enum Severity: String {
        case warning
        case error
    }

    let severity: Severity
    let message: String
}

final class ConfigValidator {
    func validate(_ config: Config) -> [ConfigValidationIssue] {
        var issues: [ConfigValidationIssue] = []
        if let seconds = config.imageRefreshIntervalSeconds,
           seconds <= 0 || !seconds.isFinite {
            issues.append(.init(severity: .error, message: "imageRefreshIntervalSeconds must be finite and greater than 0."))
        }
        if config.runners.isEmpty {
            issues.append(.init(severity: .error, message: "runners must not be empty."))
            return issues
        }
        issues.append(contentsOf: validateRunners(config.runners))
        return issues
    }

    private func validateRunners(_ runners: [Config.RunnerConfig]) -> [ConfigValidationIssue] {
        var issues: [ConfigValidationIssue] = []
        var seenNames = Set<String>()

        for runner in runners {
            let trimmedName = runner.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = trimmedName.isEmpty ? "runner <unnamed>" : "runner \(trimmedName)"
            if trimmedName.isEmpty {
                issues.append(.init(severity: .error, message: "runner name must not be empty."))
            } else if seenNames.contains(trimmedName) {
                issues.append(.init(severity: .error, message: "runner name must be unique: \(trimmedName)."))
            } else {
                seenNames.insert(trimmedName)
            }
            if let stopAfter = runner.stopAfter, stopAfter <= 0 {
                issues.append(.init(
                    severity: .warning,
                    message: "\(label): stopAfter is \(stopAfter); sand will exit immediately."
                ))
            }
            var runnerIssues: [ConfigValidationIssue] = []
            if let preRun = runner.preRun, preRun.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                runnerIssues.append(.init(severity: .error, message: "preRun must not be empty when provided."))
            }
            if let postRun = runner.postRun, postRun.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                runnerIssues.append(.init(severity: .error, message: "postRun must not be empty when provided."))
            }
            validateVM(runner.vm, issues: &runnerIssues)
            validateProvisioner(runner.provisioner, issues: &runnerIssues)
            if let healthCheck = runner.healthCheck {
                validateHealthCheck(healthCheck, issues: &runnerIssues)
            }
            validateRunnerCache(runner, issues: &runnerIssues)
            issues.append(contentsOf: runnerIssues.map {
                ConfigValidationIssue(
                    severity: $0.severity,
                    message: "\(label): \($0.message)"
                )
            })
        }

        return issues
    }

    private func validateVM(_ vm: Config.VM, issues: inout [ConfigValidationIssue]) {
        switch vm.source.type {
        case .oci:
            if (vm.source.image ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(severity: .error, message: "vm.source.image is required for OCI sources."))
            }
        case .local:
            if (vm.source.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(severity: .error, message: "vm.source.name is required for local sources."))
            }
        }

        if let ramGb = vm.hardware?.ramGb, ramGb <= 0 {
            issues.append(.init(severity: .error, message: "vm.hardware.ramGb must be greater than 0."))
        }
        if let cpuCores = vm.hardware?.cpuCores, cpuCores <= 0 {
            issues.append(.init(severity: .error, message: "vm.hardware.cpuCores must be greater than 0."))
        }
        if let display = vm.hardware?.display {
            if display.width <= 0 || display.height <= 0 {
                issues.append(.init(severity: .error, message: "vm.hardware.display width/height must be greater than 0."))
            }
        }
        if let diskSizeGb = vm.diskSizeGb, diskSizeGb <= 0 {
            issues.append(.init(severity: .error, message: "vm.diskSizeGb must be greater than 0."))
        }
        if let rootDiskOpts = vm.run.rootDiskOpts, rootDiskOpts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, message: "vm.run.rootDiskOpts must not be empty when set."))
        }

        if vm.ssh.user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, message: "vm.ssh.user must not be empty."))
        }
        if vm.ssh.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, message: "vm.ssh.password must not be empty."))
        }
        if vm.ssh.port <= 0 || vm.ssh.port > 65_535 {
            issues.append(.init(severity: .error, message: "vm.ssh.port must be between 1 and 65535."))
        }
        if let connectMaxRetries = vm.ssh.connectMaxRetries, connectMaxRetries <= 0 {
            issues.append(.init(severity: .error, message: "vm.ssh.connectMaxRetries must be greater than 0."))
        }

        for mount in vm.mounts {
            let hostPath = mount.hostPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if hostPath.isEmpty {
                issues.append(.init(severity: .error, message: "vm.mounts.host must not be empty."))
            } else {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: hostPath, isDirectory: &isDirectory), !isDirectory.boolValue {
                    issues.append(.init(severity: .error, message: "vm.mounts.host must be a directory: \(hostPath)."))
                }
            }
            let resolvedName = Config.resolveMountName(hostPath: mount.hostPath, name: mount.name)
            validateMountName(resolvedName, label: "vm.mounts.name", issues: &issues)
        }
    }

    private func validateHealthCheck(_ healthCheck: Config.HealthCheck, issues: inout [ConfigValidationIssue]) {
        if healthCheck.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, message: "healthCheck.command must not be empty."))
        }
        if healthCheck.interval <= 0 {
            issues.append(.init(severity: .error, message: "healthCheck.interval must be greater than 0."))
        }
        if healthCheck.delay < 0 {
            issues.append(.init(severity: .error, message: "healthCheck.delay must be greater than or equal to 0."))
        }
    }

    private func validateProvisioner(_ provisioner: Config.Provisioner, issues: inout [ConfigValidationIssue]) {
        switch provisioner.type {
        case .script:
            let script = provisioner.script?.run.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if script.isEmpty {
                issues.append(.init(severity: .error, message: "provisioner.config.run must not be empty for script provisioner."))
            }
        case .github:
            guard let github = provisioner.github else {
                issues.append(.init(severity: .error, message: "provisioner.config is required for github provisioner."))
                return
            }
            if github.appId <= 0 {
                issues.append(.init(severity: .error, message: "provisioner.config.appId must be greater than 0."))
            }
            if github.organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(severity: .error, message: "provisioner.config.organization must not be empty."))
            }
            if github.runnerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(severity: .error, message: "provisioner.config.runnerName must not be empty."))
            }
            let keyPath = github.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if keyPath.isEmpty {
                issues.append(.init(severity: .error, message: "provisioner.config.privateKeyPath must not be empty."))
            } else if !FileManager.default.fileExists(atPath: keyPath) {
                issues.append(.init(severity: .error, message: "Private key not found at \(keyPath)."))
            }
            if let repository = github.repository, repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(severity: .warning, message: "provisioner.config.repository is set but empty."))
            }
            if let runnerGroup = github.runnerGroup {
                if runnerGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(.init(severity: .error, message: "provisioner.config.runnerGroup must not be empty when set."))
                }
                if github.repository != nil {
                    issues.append(.init(severity: .error, message: "provisioner.config.runnerGroup requires organization-level registration; remove provisioner.config.repository."))
                }
            }
        }
    }

    private func validateRunnerCache(_ runner: Config.RunnerConfig, issues: inout [ConfigValidationIssue]) {
        guard let cache = runner.vm.cache else {
            return
        }
        if runner.provisioner.type != .github {
            issues.append(.init(
                severity: .warning,
                message: "vm.cache is set but provisioner is not github; cache will be ignored."
            ))
        }
        let hostPath = cache.hostPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if hostPath.isEmpty {
            issues.append(.init(severity: .error, message: "vm.cache.host must not be empty."))
        } else {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: hostPath, isDirectory: &isDirectory), !isDirectory.boolValue {
                issues.append(.init(
                    severity: .error,
                    message: "vm.cache.host must be a directory: \(hostPath)."
                ))
            }
        }
        if cache.name != nil {
            issues.append(.init(
                severity: .warning,
                message: "vm.cache.name is ignored; the runner cache stays on the host and is copied into each VM."
            ))
        }
    }

    private func validateMountName(_ name: String, label: String, issues: inout [ConfigValidationIssue]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            issues.append(.init(severity: .error, message: "\(label) must not be empty."))
            return
        }
        if trimmed.contains("/") {
            issues.append(.init(severity: .error, message: "\(label) must not contain '/'."))
        }
        if trimmed.contains(":") {
            issues.append(.init(severity: .error, message: "\(label) must not contain ':'."))
        }
    }
}
