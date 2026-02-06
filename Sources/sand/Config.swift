import Foundation
import Yams

struct Config: Decodable, Sendable {
    static let defaultPath = "sand.yml"

    struct VM: Decodable, Sendable {
        let source: VMSource
        let hardware: Hardware?
        let mounts: [DirectoryMount]
        let cache: Cache?
        let run: RunOptions
        let diskSizeGb: Int?
        let ssh: SSH

        init(
            source: VMSource,
            hardware: Hardware?,
            mounts: [DirectoryMount],
            cache: Cache?,
            run: RunOptions,
            diskSizeGb: Int?,
            ssh: SSH
        ) {
            self.source = source
            self.hardware = hardware
            self.mounts = mounts
            self.cache = cache
            self.run = run
            self.diskSizeGb = diskSizeGb
            self.ssh = ssh
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.source = try container.decode(VMSource.self, forKey: .source)
            self.hardware = try container.decodeIfPresent(Hardware.self, forKey: .hardware)
            self.mounts = try container.decodeIfPresent([DirectoryMount].self, forKey: .mounts) ?? []
            self.cache = try container.decodeIfPresent(Cache.self, forKey: .cache)
            self.run = try container.decodeIfPresent(RunOptions.self, forKey: .run) ?? .default
            self.diskSizeGb = try container.decodeIfPresent(Int.self, forKey: .diskSizeGb)
            self.ssh = try container.decodeIfPresent(SSH.self, forKey: .ssh) ?? .standard
        }

        private enum CodingKeys: String, CodingKey {
            case source
            case hardware
            case mounts
            case cache
            case run
            case diskSizeGb
            case ssh
        }
    }

    struct VMSource: Decodable, Sendable {
        enum SourceType: String, Decodable, Sendable {
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

    struct Hardware: Decodable, Sendable {
        let ramGb: Int?
        let cpuCores: Int?
        let display: Display?
        let audio: Bool?
    }

    struct Display: Decodable, Sendable {
        enum Unit: String, Decodable, Sendable {
            case pt
            case px
        }

        let width: Int
        let height: Int
        let unit: Unit?
        let refit: Bool?
    }

    struct DirectoryMount: Decodable, Sendable {
        enum Mode: String, Decodable, Sendable {
            case ro
            case rw
        }

        let hostPath: String
        let name: String?
        let mode: Mode

        init(hostPath: String, name: String?, mode: Mode) {
            self.hostPath = hostPath
            self.name = name
            self.mode = mode
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.hostPath = try container.decode(String.self, forKey: .host)
            self.name = try container.decodeIfPresent(String.self, forKey: .name)
            self.mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .rw
        }

        private enum CodingKeys: String, CodingKey {
            case host
            case name
            case mode
        }
    }

    struct Cache: Decodable, Sendable {
        let hostPath: String
        let name: String?

        init(hostPath: String, name: String?) {
            self.hostPath = hostPath
            self.name = name
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.hostPath = try container.decode(String.self, forKey: .host)
            self.name = try container.decodeIfPresent(String.self, forKey: .name)
        }

        private enum CodingKeys: String, CodingKey {
            case host
            case name
        }
    }

    struct RunOptions: Decodable, Sendable {
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

    struct SSH: Decodable, Sendable {
        let user: String
        let password: String
        let port: Int
        let connectMaxRetries: Int?
        static let standard = SSH(user: "admin", password: "admin", port: 22)

        init(user: String, password: String, port: Int, connectMaxRetries: Int? = nil) {
            self.user = user
            self.password = password
            self.port = port
            self.connectMaxRetries = connectMaxRetries
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.user = try container.decodeIfPresent(String.self, forKey: .user) ?? "admin"
            self.password = try container.decodeIfPresent(String.self, forKey: .password) ?? "admin"
            self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
            self.connectMaxRetries = try container.decodeIfPresent(Int.self, forKey: .connectMaxRetries)
        }

        private enum CodingKeys: String, CodingKey {
            case user
            case password
            case port
            case connectMaxRetries
        }
    }

    struct HealthCheck: Decodable, Sendable {
        static let defaultCommand = "echo healthcheck"
        static let standard = HealthCheck(command: defaultCommand)
        private static let defaultInterval: TimeInterval = 30
        private static let defaultDelay: TimeInterval = 60

        let command: String
        let interval: TimeInterval
        let delay: TimeInterval

        init(
            command: String,
            interval: TimeInterval = Self.defaultInterval,
            delay: TimeInterval = Self.defaultDelay
        ) {
            self.command = command
            self.interval = interval
            self.delay = delay
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.command = try container.decode(String.self, forKey: .command)
            self.interval = try container.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? Self.defaultInterval
            self.delay = try container.decodeIfPresent(TimeInterval.self, forKey: .delay) ?? Self.defaultDelay
        }

        private enum CodingKeys: String, CodingKey {
            case command
            case interval
            case delay
        }
    }

    struct Provisioner: Decodable, Sendable {
        enum ProvisionerType: String, Decodable, Sendable {
            case script
            case github
        }

        struct Script: Decodable, Sendable {
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

    struct RunnerConfig: Decodable, Sendable {
        let name: String
        let vm: VM
        let provisioner: Provisioner
        let preRun: String?
        let postRun: String?
        let stopAfter: Int?
        let numberOfRunsUntilHostReboot: Int?
        let healthCheck: HealthCheck?
    }

    let runners: [RunnerConfig]

    init(runners: [RunnerConfig]) {
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
        let expandedRunners = runners.map { runner in
            RunnerConfig(
                name: runner.name,
                vm: expandVM(runner.vm),
                provisioner: runner.provisioner.expanded(),
                preRun: runner.preRun,
                postRun: runner.postRun,
                stopAfter: runner.stopAfter,
                numberOfRunsUntilHostReboot: runner.numberOfRunsUntilHostReboot,
                healthCheck: runner.healthCheck
            )
        }
        return Config(runners: expandedRunners)
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
                name: mount.name,
                mode: mount.mode
            )
        }
        let cache = vm.cache.map { cache in
            Cache(
                hostPath: Config.expandPath(cache.hostPath),
                name: cache.name
            )
        }
        return VM(
            source: vmSource,
            hardware: vm.hardware,
            mounts: mounts,
            cache: cache,
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

    static func resolveMountName(hostPath: String, name: String?) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty {
            return trimmedName
        }
        let trimmedHost = hostPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            return ""
        }
        let last = URL(fileURLWithPath: trimmedHost).lastPathComponent
        return last.isEmpty ? trimmedHost : last
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
