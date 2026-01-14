import CryptoKit
import Foundation

struct GitHubRunnerPrebuilder {
    enum PrebuildError: Error {
        case sshUnavailable
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var inProgress: Set<String> = []
    }

    private static let state = State()

    let tart: Tart
    let logger: Logger
    let provisioner: GitHubProvisioner

    func prebuiltSource(baseSource: String, vm: Config.VM) async throws -> String {
        let key = cacheKey(baseSource: baseSource, vm: vm)
        let name = "sand-prebuilt-\(key)"
        if try tart.hasLocal(name: name) {
            logger.info("prebuild cache hit \(name)")
            return name
        }
        let shouldBuild = try await waitForBuildSlot(key: key, name: name)
        if !shouldBuild {
            logger.info("prebuild cache hit \(name)")
            return name
        }
        defer {
            Self.finishBuild(key: key)
        }
        logger.info("prebuild cache miss \(name), building")
        try await buildPrebuilt(name: name, baseSource: baseSource, vm: vm)
        logger.info("prebuild cache ready \(name)")
        return name
    }

    private func waitForBuildSlot(key: String, name: String) async throws -> Bool {
        while true {
            if try tart.hasLocal(name: name) {
                return false
            }
            if Self.startBuild(key: key) {
                return true
            }
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return false
            }
        }
    }

    private static func startBuild(key: String) -> Bool {
        state.lock.lock()
        defer { state.lock.unlock() }
        if state.inProgress.contains(key) {
            return false
        }
        state.inProgress.insert(key)
        return true
    }

    private static func finishBuild(key: String) {
        state.lock.lock()
        state.inProgress.remove(key)
        state.lock.unlock()
    }

    private func cacheKey(baseSource: String, vm: Config.VM) -> String {
        let disk = vm.diskSizeGb.map(String.init) ?? "none"
        let seed = [baseSource, GitHubProvisioner.runnerVersion, disk].joined(separator: "|")
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func buildPrebuilt(name: String, baseSource: String, vm: Config.VM) async throws {
        try tart.prepare(source: baseSource)
        let tempName = "\(name)-tmp-\(UUID().uuidString)"
        try tart.clone(source: baseSource, name: tempName)
        var renamed = false
        defer {
            if !renamed {
                try? tart.delete(name: tempName)
            }
        }
        try VMConfigurer.applyDiskSizeIfNeeded(tart: tart, name: tempName, vm: vm)
        let runOptions = Tart.RunOptions(
            directoryMounts: [],
            noAudio: true,
            noGraphics: true,
            noClipboard: true
        )
        try tart.run(name: tempName, options: runOptions)
        var stopped = false
        defer {
            if !stopped {
                try? tart.stop(name: tempName)
            }
        }
        let ip = try tart.ip(name: tempName, wait: 60)
        let ssh = SSHClient(processRunner: tart.processRunner, host: ip, config: vm.ssh)
        guard await SSHWaiter.wait(for: ssh, logger: logger) else {
            throw PrebuildError.sshUnavailable
        }
        for command in provisioner.installScript() {
            _ = try ssh.exec(command: command)
        }
        try tart.stop(name: tempName)
        stopped = true
        do {
            try tart.rename(oldName: tempName, newName: name)
            renamed = true
        } catch {
            if try tart.hasLocal(name: name) {
                return
            }
            throw error
        }
    }
}
