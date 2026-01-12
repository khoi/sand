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
    let config = Config(
        vm: vm,
        provisioner: Config.Provisioner(type: .github, script: nil, github: github),
        stopAfter: 1,
        runnerCount: 2
    )
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
        ssh: Config.SSH(user: "", password: "", port: 70_000)
    )
    let config = Config(
        vm: vm,
        provisioner: Config.Provisioner(type: .script, script: .init(run: "  "), github: nil),
        stopAfter: 0,
        runnerCount: 0
    )
    let issues = ConfigValidator().validate(config)
    #expect(issues.contains(.init(severity: .warning, message: "stopAfter is 0; sand will exit immediately.")))
    #expect(issues.contains(.init(severity: .error, message: "runnerCount must be greater than 0.")))
    #expect(issues.contains(.init(severity: .error, message: "Local VM path does not exist: /missing-vm.")))
    #expect(issues.contains(.init(severity: .error, message: "vm.hardware.ramGb must be greater than 0.")))
    #expect(issues.contains(.init(severity: .error, message: "vm.hardware.cpuCores must be greater than 0.")))
    #expect(issues.contains(.init(severity: .error, message: "vm.hardware.display width/height must be greater than 0.")))
    #expect(issues.contains(.init(severity: .error, message: "vm.diskSizeGb must be greater than 0.")))
    #expect(issues.contains(.init(severity: .error, message: "vm.ssh.user must not be empty.")))
    #expect(issues.contains(.init(severity: .error, message: "vm.ssh.password must not be empty.")))
    #expect(issues.contains(.init(severity: .error, message: "vm.ssh.port must be between 1 and 65535.")))
    #expect(issues.contains(.init(severity: .warning, message: "Mount hostPath does not exist: /missing-mount.")))
    #expect(issues.contains(.init(severity: .error, message: "vm.mounts.guestFolder must not be empty.")))
    #expect(issues.contains(.init(severity: .error, message: "provisioner.config.run must not be empty for script provisioner.")))
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
        Config.RunnerConfig(name: "same", vm: vm, provisioner: provisioner, stopAfter: nil),
        Config.RunnerConfig(name: "same", vm: vm, provisioner: provisioner, stopAfter: nil)
    ]
    let config = Config(vm: nil, provisioner: nil, stopAfter: nil, runnerCount: nil, runners: runners)
    let issues = ConfigValidator().validate(config)
    #expect(issues.contains(.init(severity: .error, message: "runner name must be unique: same.")))
}
