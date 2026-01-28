import Foundation

enum GitHubRunnerVersionResolverError: Error {
    case invalidResponse
    case httpStatus(Int)
    case missingTag
    case invalidTag(String)
}

actor GitHubRunnerVersionResolver: Sendable {
    private let session: URLSession
    private var cachedVersion: String?
    private var inFlight: Task<String, Error>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func latestVersion() async throws -> String {
        if let cachedVersion {
            return cachedVersion
        }
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { try await fetchLatestVersion() }
        inFlight = task
        do {
            let version = try await task.value
            cachedVersion = version
            inFlight = nil
            return version
        } catch {
            inFlight = nil
            throw error
        }
    }

    private func fetchLatestVersion() async throws -> String {
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
        let payload = try JSONDecoder().decode(LatestRelease.self, from: data)
        guard let tag = payload.tag_name else {
            throw GitHubRunnerVersionResolverError.missingTag
        }
        guard let version = Self.parseTagName(tag) else {
            throw GitHubRunnerVersionResolverError.invalidTag(tag)
        }
        return version
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

    static func newestCachedVersion(in directory: String) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return nil
        }
        var newestVersion: String?
        var newestComponents: [Int]?
        for entry in entries {
            guard let version = extractVersion(from: entry),
                  let components = parseVersionComponents(version) else {
                continue
            }
            if let currentComponents = newestComponents {
                if compareVersions(components, currentComponents) == .orderedDescending {
                    newestVersion = version
                    newestComponents = components
                }
            } else {
                newestVersion = version
                newestComponents = components
            }
        }
        return newestVersion
    }

    private static func extractVersion(from filename: String) -> String? {
        let prefix = "actions-runner-"
        let suffix = ".tar.gz"
        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else {
            return nil
        }
        let core = String(filename.dropFirst(prefix.count).dropLast(suffix.count))
        guard let dashIndex = core.lastIndex(of: "-") else {
            return nil
        }
        let version = String(core[core.index(after: dashIndex)...])
        return parseTagName(version)
    }

    private static func parseVersionComponents(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".")
        guard !parts.isEmpty else {
            return nil
        }
        var components: [Int] = []
        for part in parts {
            guard let value = Int(part) else {
                return nil
            }
            components.append(value)
        }
        return components
    }

    private static func compareVersions(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left == right {
                continue
            }
            return left < right ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    private struct LatestRelease: Decodable {
        let tag_name: String?
    }
}
