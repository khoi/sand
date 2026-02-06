import Foundation
import XCTest
@testable import sand

final class ConfigValidatorTests: XCTestCase {
    func testValidConfigHasNoIssues() throws {
        let keyURL = try writeTempFile(contents: "key", suffix: ".pem")
        let vm = Config.VM(
            source: Config.VMSource(type: .oci, image: "ghcr.io/acme/vm:latest", path: nil),
            hardware: nil,
            mounts: [],
            cache: Config.Cache(hostPath: "/tmp/sand-cache", name: "sand-cache"),
            run: .default,
            diskSizeGb: nil,
            ssh: .standard
        )
        let github = GitHubProvisionerConfig(
            appId: 1,
            organization: "acme",
            repository: nil,
            privateKeyPath: keyURL.path,
            runnerName: "runner-1",
            extraLabels: nil
        )
        let runner = Config.RunnerConfig(
            name: "runner-1",
            vm: vm,
            provisioner: Config.Provisioner(type: .github, script: nil, github: github),
            preRun: nil,
            postRun: nil,
            stopAfter: 1,
            numberOfRunsUntilHostReboot: 3,
            healthCheck: Config.HealthCheck(command: "true")
        )
        let config = Config(runners: [runner])
        let issues = ConfigValidator().validate(config)
        XCTAssertTrue(issues.isEmpty)
    }

    func testInvalidConfigReportsIssues() {
        let vm = Config.VM(
            source: Config.VMSource(type: .local, image: nil, path: "/missing-vm"),
            hardware: Config.Hardware(
                ramGb: 0,
                cpuCores: 0,
                display: Config.Display(width: 0, height: 0, unit: nil, refit: nil),
                audio: nil
            ),
            mounts: [Config.DirectoryMount(hostPath: "/missing-mount", name: "bad/name", mode: .rw)],
            cache: nil,
            run: .default,
            diskSizeGb: 0,
            ssh: Config.SSH(user: "", password: "", port: 70_000, connectMaxRetries: 0)
        )
        let runner = Config.RunnerConfig(
            name: "runner-1",
            vm: vm,
            provisioner: Config.Provisioner(type: .script, script: .init(run: "  "), github: nil),
            preRun: nil,
            postRun: nil,
            stopAfter: 0,
            numberOfRunsUntilHostReboot: 0,
            healthCheck: Config.HealthCheck(command: "  ", interval: 0, delay: -1)
        )
        let config = Config(runners: [runner])
        let issues = ConfigValidator().validate(config)
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .warning, message: "runner runner-1: stopAfter is 0; sand will exit immediately.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: numberOfRunsUntilHostReboot must be greater than 0.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: Local VM path does not exist: /missing-vm.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.hardware.ramGb must be greater than 0.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.hardware.cpuCores must be greater than 0.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.hardware.display width/height must be greater than 0.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.diskSizeGb must be greater than 0.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.ssh.user must not be empty.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.ssh.password must not be empty.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.ssh.port must be between 1 and 65535.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.ssh.connectMaxRetries must be greater than 0.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.mounts.name must not contain '/'.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: provisioner.config.run must not be empty for script provisioner.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: healthCheck.command must not be empty.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: healthCheck.interval must be greater than 0.")))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: healthCheck.delay must be greater than or equal to 0.")))
    }

    func testDuplicateRunnerNamesAreRejected() {
        let vm = Config.VM(
            source: Config.VMSource(type: .oci, image: "ghcr.io/acme/vm:latest", path: nil),
            hardware: nil,
            mounts: [],
            cache: nil,
            run: .default,
            diskSizeGb: nil,
            ssh: .standard
        )
        let provisioner = Config.Provisioner(type: .script, script: .init(run: "echo hi"), github: nil)
        let runners = [
            Config.RunnerConfig(name: "same", vm: vm, provisioner: provisioner, preRun: nil, postRun: nil, stopAfter: nil, numberOfRunsUntilHostReboot: nil, healthCheck: nil),
            Config.RunnerConfig(name: "same", vm: vm, provisioner: provisioner, preRun: nil, postRun: nil, stopAfter: nil, numberOfRunsUntilHostReboot: nil, healthCheck: nil)
        ]
        let config = Config(runners: runners)
        let issues = ConfigValidator().validate(config)
        XCTAssertTrue(issues.contains(ConfigValidationIssue(severity: .error, message: "runner name must be unique: same.")))
    }

    func testRunnerCacheValidation() throws {
        let cacheFile = try writeTempFile(contents: "not-a-directory")
        let vm = Config.VM(
            source: Config.VMSource(type: .oci, image: "ghcr.io/acme/vm:latest", path: nil),
            hardware: nil,
            mounts: [],
            cache: Config.Cache(hostPath: cacheFile.path, name: "bad/cache"),
            run: .default,
            diskSizeGb: nil,
            ssh: .standard
        )
        let runner = Config.RunnerConfig(
            name: "runner-1",
            vm: vm,
            provisioner: Config.Provisioner(type: .script, script: .init(run: "echo ok"), github: nil),
            preRun: nil,
            postRun: nil,
            stopAfter: nil,
            numberOfRunsUntilHostReboot: nil,
            healthCheck: nil
        )
        let issues = ConfigValidator().validate(Config(runners: [runner]))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(
            severity: .warning,
            message: "runner runner-1: vm.cache is set but provisioner is not github; cache will be ignored."
        )))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(
            severity: .error,
            message: "runner runner-1: vm.cache.name must not contain '/'."
        )))
        XCTAssertTrue(issues.contains(ConfigValidationIssue(
            severity: .error,
            message: "runner runner-1: vm.cache.host must be a directory: \(cacheFile.path)."
        )))
    }
}
