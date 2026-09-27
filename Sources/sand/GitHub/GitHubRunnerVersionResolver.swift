import Foundation

enum GitHubRunnerVersionResolverError: Error {
    case invalidResponse
    case httpStatus(Int)
    case missingTag
    case invalidTag(String)
}

struct RunnerRelease: Sendable, Equatable {
    let version: String
    let digests: [String: String]
}

actor GitHubRunnerVersionResolver: Sendable {
    static let refreshInterval: TimeInterval = 86_400

    private let session: URLSession
    private var cached: (release: RunnerRelease, fetchedAt: Date)?
    private var inFlight: Task<RunnerRelease, Error>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func latestRelease() async throws -> RunnerRelease {
        if let cached, Date().timeIntervalSince(cached.fetchedAt) < Self.refreshInterval {
            return cached.release
        }
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { try await fetchLatestRelease() }
        inFlight = task
        defer {
            inFlight = nil
        }
        do {
            let release = try await task.value
            cached = (release, Date())
            return release
        } catch {
            if let cached {
                return cached.release
            }
            throw error
        }
    }

    private func fetchLatestRelease() async throws -> RunnerRelease {
        guard let url = URL(string: "https://api.github.com/repos/actions/runner/releases/latest") else {
            throw GitHubRunnerVersionResolverError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("sand", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubRunnerVersionResolverError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubRunnerVersionResolverError.httpStatus(httpResponse.statusCode)
        }
        return try Self.parseRelease(data)
    }

    static func parseRelease(_ data: Data) throws -> RunnerRelease {
        let payload = try JSONDecoder().decode(LatestRelease.self, from: data)
        guard let tag = payload.tag_name else {
            throw GitHubRunnerVersionResolverError.missingTag
        }
        guard let version = parseTagName(tag) else {
            throw GitHubRunnerVersionResolverError.invalidTag(tag)
        }
        var digests: [String: String] = [:]
        for asset in payload.assets ?? [] {
            if let digest = asset.digest.flatMap(parseDigest) {
                digests[asset.name] = digest
            }
        }
        return RunnerRelease(version: version, digests: digests)
    }

    static func parseDigest(_ digest: String) -> String? {
        let prefix = "sha256:"
        guard digest.hasPrefix(prefix) else {
            return nil
        }
        let hex = digest.dropFirst(prefix.count).lowercased()
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return hex
    }

    static func parseTagName(_ tagName: String) -> String? {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        guard !version.isEmpty else {
            return nil
        }
        let allowed = CharacterSet(charactersIn: "0123456789.")
        guard version.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }
        return version
    }

    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r {
                return l > r
            }
        }
        return false
    }

    private struct LatestRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let digest: String?
        }

        let tag_name: String?
        let assets: [Asset]?
    }
}
