import Foundation
import Yams

struct Config: Decodable {
    struct VM: Decodable {
        let source: VMSource
        let hardware: Hardware?
        let mounts: [DirectoryMount]
        let run: RunOptions
        let diskSizeGb: Int?
        let ssh: SSH

        init(source: VMSource, hardware: Hardware?, mounts: [DirectoryMount], run: RunOptions, diskSizeGb: Int?, ssh: SSH) {
            self.source = source
            self.hardware = hardware
            self.mounts = mounts
            self.run = run
            self.diskSizeGb = diskSizeGb
            self.ssh = ssh
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.source = try container.decode(VMSource.self, forKey: .source)
            self.hardware = try container.decodeIfPresent(Hardware.self, forKey: .hardware)
            self.mounts = try container.decodeIfPresent([DirectoryMount].self, forKey: .mounts) ?? []
            self.run = try container.decodeIfPresent(RunOptions.self, forKey: .run) ?? .default
            self.diskSizeGb = try container.decodeIfPresent(Int.self, forKey: .diskSizeGb)
            self.ssh = try container.decodeIfPresent(SSH.self, forKey: .ssh) ?? .standard
        }

        private enum CodingKeys: String, CodingKey {
            case source
            case hardware
            case mounts
            case run
            case diskSizeGb
            case ssh
        }
    }

    struct VMSource: Decodable {
        enum SourceType: String, Decodable {
            case oci
            case local
        }

        let type: SourceType
        let image: String?
        let path: String?

        init(type: SourceType, image: String?, path: String?) {
            self.type = type
            self.image = image
            self.path = path
        }

        var resolvedSource: String {
            switch type {
            case .oci:
                return image ?? ""
            case .local:
                return Config.expandFileURL(path ?? "")
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try container.decode(SourceType.self, forKey: .type)
            self.image = try container.decodeIfPresent(String.self, forKey: .image)
            self.path = try container.decodeIfPresent(String.self, forKey: .path)

            switch type {
            case .oci:
                if (image ?? "").isEmpty {
                    throw DecodingError.dataCorruptedError(forKey: .image, in: container, debugDescription: "OCI source requires image")
                }
            case .local:
                if (path ?? "").isEmpty {
                    throw DecodingError.dataCorruptedError(forKey: .path, in: container, debugDescription: "Local source requires path")
                }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case image
            case path
        }
    }

    struct Hardware: Decodable {
        let ramGb: Int?
        let cpuCores: Int?
        let display: Display?
        let audio: Bool?
    }

    struct Display: Decodable {
        enum Unit: String, Decodable {
            case pt
            case px
        }

        let width: Int
        let height: Int
        let unit: Unit?
        let refit: Bool?
    }

    struct DirectoryMount: Decodable {
        let hostPath: String
        let guestFolder: String
        let readOnly: Bool
        let tag: String?

        init(hostPath: String, guestFolder: String, readOnly: Bool, tag: String?) {
            self.hostPath = hostPath
            self.guestFolder = guestFolder
            self.readOnly = readOnly
            self.tag = tag
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.hostPath = try container.decode(String.self, forKey: .hostPath)
            self.guestFolder = try container.decode(String.self, forKey: .guestFolder)
            self.readOnly = try container.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
            self.tag = try container.decodeIfPresent(String.self, forKey: .tag)
        }

        private enum CodingKeys: String, CodingKey {
            case hostPath
            case guestFolder
            case readOnly
            case tag
        }
    }

    struct RunOptions: Decodable {
        let noGraphics: Bool
        let noClipboard: Bool

        static let `default` = RunOptions(noGraphics: true, noClipboard: false)

        init(noGraphics: Bool, noClipboard: Bool) {
            self.noGraphics = noGraphics
            self.noClipboard = noClipboard
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.noGraphics = try container.decodeIfPresent(Bool.self, forKey: .noGraphics) ?? true
            self.noClipboard = try container.decodeIfPresent(Bool.self, forKey: .noClipboard) ?? false
        }

        private enum CodingKeys: String, CodingKey {
            case noGraphics
            case noClipboard
        }
    }

    struct SSH: Decodable {
        let user: String
        let password: String
        let port: Int
        static let standard = SSH(user: "admin", password: "admin", port: 22)

        init(user: String, password: String, port: Int) {
            self.user = user
            self.password = password
            self.port = port
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.user = try container.decodeIfPresent(String.self, forKey: .user) ?? "admin"
            self.password = try container.decodeIfPresent(String.self, forKey: .password) ?? "admin"
            self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        }

        private enum CodingKeys: String, CodingKey {
            case user
            case password
            case port
        }
    }

    struct Provisioner: Decodable {
        enum ProvisionerType: String, Decodable {
            case script
            case github
        }

        struct Script: Decodable {
            let run: String
        }

        typealias GitHub = GitHubProvisionerConfig

        let type: ProvisionerType
        let script: Script?
        let github: GitHub?

        init(type: ProvisionerType, script: Script?, github: GitHub?) {
            self.type = type
            self.script = script
            self.github = github
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(ProvisionerType.self, forKey: .type)
            switch type {
            case .script:
                let script = try container.decode(Script.self, forKey: .config)
                self.init(type: type, script: script, github: nil)
            case .github:
                let github = try container.decode(GitHub.self, forKey: .config)
                self.init(type: type, script: nil, github: github)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case config
        }
    }

    struct RunnerConfig: Decodable {
        let name: String
        let vm: VM
        let provisioner: Provisioner
        let stopAfter: Int?
    }

    let vm: VM?
    let provisioner: Provisioner?
    let stopAfter: Int?
    let runnerCount: Int?
    let runners: [RunnerConfig]?

    init(
        vm: VM?,
        provisioner: Provisioner?,
        stopAfter: Int?,
        runnerCount: Int? = nil,
        runners: [RunnerConfig]? = nil
    ) {
        self.vm = vm
        self.provisioner = provisioner
        self.stopAfter = stopAfter
        self.runnerCount = runnerCount
        self.runners = runners
    }

    static func load(path: String) throws -> Config {
        let expandedPath = expandPath(path)
        let contents = try String(contentsOfFile: expandedPath, encoding: .utf8)
        let decoder = YAMLDecoder()
        let decoded = try decoder.decode(Config.self, from: contents)
        return decoded.expanded()
    }

    private func expanded() -> Config {
        if let runners, !runners.isEmpty {
            let expandedRunners = runners.map { runner in
                RunnerConfig(
                    name: runner.name,
                    vm: expandVM(runner.vm),
                    provisioner: runner.provisioner.expanded(),
                    stopAfter: runner.stopAfter
                )
            }
            return Config(
                vm: vm,
                provisioner: provisioner,
                stopAfter: stopAfter,
                runnerCount: runnerCount,
                runners: expandedRunners
            )
        }
        guard let vm, let provisioner else {
            return self
        }
        return Config(
            vm: expandVM(vm),
            provisioner: provisioner.expanded(),
            stopAfter: stopAfter,
            runnerCount: runnerCount
        )
    }

    private func expandVM(_ vm: VM) -> VM {
        let vmSource: VMSource
        switch vm.source.type {
        case .oci:
            vmSource = vm.source
        case .local:
            let expandedPath = Config.expandFileURL(vm.source.path ?? "")
            vmSource = VMSource(type: .local, image: nil, path: expandedPath)
        }

        let mounts = vm.mounts.map { mount in
            DirectoryMount(
                hostPath: Config.expandPath(mount.hostPath),
                guestFolder: mount.guestFolder,
                readOnly: mount.readOnly,
                tag: mount.tag
            )
        }
        return VM(
            source: vmSource,
            hardware: vm.hardware,
            mounts: mounts,
            run: vm.run,
            diskSizeGb: vm.diskSizeGb,
            ssh: vm.ssh
        )
    }

    static func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        return path
    }

    static func expandFileURL(_ path: String) -> String {
        let prefix = "file://"
        if path.hasPrefix(prefix) {
            let rawPath = String(path.dropFirst(prefix.count))
            return prefix + expandPath(rawPath)
        }
        return prefix + expandPath(path)
    }
}

extension Config.Provisioner {
    func expanded() -> Config.Provisioner {
        switch type {
        case .script:
            return self
        case .github:
            guard let github else {
                return self
            }
            let expanded = GitHubProvisionerConfig(
                appId: github.appId,
                organization: github.organization,
                repository: github.repository,
                privateKeyPath: Config.expandPath(github.privateKeyPath),
                runnerName: github.runnerName,
                extraLabels: github.extraLabels
            )
            return Config.Provisioner(type: type, script: nil, github: expanded)
        }
    }
}
