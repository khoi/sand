import CryptoKit
import Foundation

enum RunnerCacheError: Error {
    case missingDigest(String)
    case downloadFailed(url: String, status: Int?)
    case digestMismatch(asset: String, expected: String, actual: String)
}

struct RunnerAsset: Sendable, Equatable {
    let platform: String
    let version: String

    var name: String {
        "actions-runner-\(platform)-\(version).tar.gz"
    }

    var url: URL {
        URL(string: "https://github.com/actions/runner/releases/download/v\(version)/\(name)")!
    }

    static func platform(os: String, arch: String) -> String? {
        let runnerOS: String
        switch os {
        case "Darwin":
            runnerOS = "osx"
        case "Linux":
            runnerOS = "linux"
        default:
            return nil
        }
        let runnerArch: String
        switch arch {
        case "x86_64", "amd64":
            runnerArch = "x64"
        case "arm64", "aarch64":
            runnerArch = "arm64"
        case "armv7l", "armv6l":
            runnerArch = "arm"
        default:
            return nil
        }
        return "\(runnerOS)-\(runnerArch)"
    }
}

actor RunnerCache {
    static let keptVersions = 3

    private let download: @Sendable (URL) async throws -> URL
    private var inFlight: [String: Task<String, Error>] = [:]

    init(download: @escaping @Sendable (URL) async throws -> URL = RunnerCache.download) {
        self.download = download
    }

    func verifiedTarball(directory: String, asset: RunnerAsset, digest: String) async throws -> String {
        let path = (directory as NSString).appendingPathComponent(asset.name)
        if let task = inFlight[path] {
            return try await task.value
        }
        let download = download
        let task = Task {
            try await Self.fetchVerified(directory: directory, path: path, asset: asset, digest: digest, download: download)
        }
        inFlight[path] = task
        defer {
            inFlight[path] = nil
        }
        return try await task.value
    }

    nonisolated static func newestVerifiedTarball(directory: String, platform: String) -> (path: String, version: String)? {
        for (path, version) in tarballs(directory: directory, platform: platform) {
            if let expected = readSidecar(for: path), (try? sha256(ofFileAt: path)) == expected {
                return (path, version)
            }
        }
        return nil
    }

    nonisolated static func sha256(ofFileAt path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer {
            try? handle.close()
        }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @Sendable
    static func download(_ url: URL) async throws -> URL {
        let (file, response) = try await URLSession.shared.download(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode
        guard let status, (200..<300).contains(status) else {
            try? FileManager.default.removeItem(at: file)
            throw RunnerCacheError.downloadFailed(url: url.absoluteString, status: status)
        }
        return file
    }

    private static func fetchVerified(
        directory: String,
        path: String,
        asset: RunnerAsset,
        digest: String,
        download: @Sendable (URL) async throws -> URL
    ) async throws -> String {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path), (try? sha256(ofFileAt: path)) == digest {
            if readSidecar(for: path) != digest {
                try writeSidecar(digest, for: path)
            }
            return path
        }
        let downloaded = try await download(asset.url)
        defer {
            try? fileManager.removeItem(at: downloaded)
        }
        let actual = try sha256(ofFileAt: downloaded.path)
        guard actual == digest else {
            throw RunnerCacheError.digestMismatch(asset: asset.name, expected: digest, actual: actual)
        }
        let staging = (directory as NSString).appendingPathComponent(".\(asset.name).\(UUID().uuidString)")
        try fileManager.moveItem(atPath: downloaded.path, toPath: staging)
        guard rename(staging, path) == 0 else {
            let code = errno
            try? fileManager.removeItem(atPath: staging)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        try writeSidecar(digest, for: path)
        prune(directory: directory, platform: asset.platform)
        return path
    }

    private static func prune(directory: String, platform: String) {
        for (path, _) in tarballs(directory: directory, platform: platform).dropFirst(keptVersions) {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + ".sha256")
        }
    }

    private static func tarballs(directory: String, platform: String) -> [(path: String, version: String)] {
        let prefix = "actions-runner-\(platform)-"
        let suffix = ".tar.gz"
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return entries
            .compactMap { entry -> (path: String, version: String)? in
                guard entry.hasPrefix(prefix), entry.hasSuffix(suffix) else {
                    return nil
                }
                let raw = String(entry.dropFirst(prefix.count).dropLast(suffix.count))
                guard let version = GitHubRunnerVersionResolver.parseTagName(raw) else {
                    return nil
                }
                return ((directory as NSString).appendingPathComponent(entry), version)
            }
            .sorted { GitHubRunnerVersionResolver.isNewer($0.version, than: $1.version) }
    }

    private static func readSidecar(for path: String) -> String? {
        let value = (try? String(contentsOfFile: path + ".sha256", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private static func writeSidecar(_ digest: String, for path: String) throws {
        try Data(digest.utf8).write(to: URL(fileURLWithPath: path + ".sha256"), options: .atomic)
    }
}
