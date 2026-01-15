import Foundation
import Testing
@testable import sand

@Test
func validConfigHasNoIssues() throws {
    let keyURL = try writeTempFile(contents: "key", suffix: ".pem")
    let vm = Config.VM(
        source: Config.VMSource(type: .oci, image: "ghcr.io/acme/vm:latest", path: nil),
        hardware: nil,
        mounts: [],
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
        healthCheck: Config.HealthCheck(command: "true")
    )
    let config = Config(runners: [runner])
    let issues = ConfigValidator().validate(config)
    #expect(issues.isEmpty)
}

@Test
func invalidConfigReportsIssues() {
    let vm = Config.VM(
        source: Config.VMSource(type: .local, image: nil, path: "/missing-vm"),
        hardware: Config.Hardware(
            ramGb: 0,
            cpuCores: 0,
            display: Config.Display(width: 0, height: 0, unit: nil, refit: nil),
            audio: nil
        ),
        mounts: [Config.DirectoryMount(hostPath: "/missing-mount", guestFolder: "", readOnly: false, tag: nil)],
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
        healthCheck: Config.HealthCheck(command: "  ", interval: 0, delay: -1)
    )
    let config = Config(runners: [runner])
    let issues = ConfigValidator().validate(config)
    #expect(issues.contains(ConfigValidationIssue(severity: .warning, message: "runner runner-1: stopAfter is 0; sand will exit immediately.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: Local VM path does not exist: /missing-vm.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.hardware.ramGb must be greater than 0.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.hardware.cpuCores must be greater than 0.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.hardware.display width/height must be greater than 0.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.diskSizeGb must be greater than 0.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.ssh.user must not be empty.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.ssh.password must not be empty.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.ssh.port must be between 1 and 65535.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.ssh.connectMaxRetries must be greater than 0.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .warning, message: "runner runner-1: Mount hostPath does not exist: /missing-mount.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: vm.mounts.guestFolder must not be empty.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: provisioner.config.run must not be empty for script provisioner.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: healthCheck.command must not be empty.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: healthCheck.interval must be greater than 0.")))
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner runner-1: healthCheck.delay must be greater than or equal to 0.")))
}

@Test
func duplicateRunnerNamesAreRejected() {
    let vm = Config.VM(
        source: Config.VMSource(type: .oci, image: "ghcr.io/acme/vm:latest", path: nil),
        hardware: nil,
        mounts: [],
        run: .default,
        diskSizeGb: nil,
        ssh: .standard
    )
    let provisioner = Config.Provisioner(type: .script, script: .init(run: "echo hi"), github: nil)
    let runners = [
        Config.RunnerConfig(name: "same", vm: vm, provisioner: provisioner, preRun: nil, postRun: nil, stopAfter: nil, healthCheck: nil),
        Config.RunnerConfig(name: "same", vm: vm, provisioner: provisioner, preRun: nil, postRun: nil, stopAfter: nil, healthCheck: nil)
    ]
    let config = Config(runners: runners)
    let issues = ConfigValidator().validate(config)
    #expect(issues.contains(ConfigValidationIssue(severity: .error, message: "runner name must be unique: same.")))
}
