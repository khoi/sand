import Foundation
import Yams

struct Config: Decodable {
    struct GitHub: Decodable {
        let appId: Int
        let organization: String
        let repository: String?
        let privateKeyPath: String
        let runnerName: String
        let extraLabels: [String]?
    }

    struct SSH: Decodable {
        let username: String
        let password: String
    }

    let source: String
    let github: GitHub
    let ssh: SSH

    static func load(path: String) throws -> Config {
        let expandedPath = expandPath(path)
        let contents = try String(contentsOfFile: expandedPath, encoding: .utf8)
        let decoder = YAMLDecoder()
        let decoded = try decoder.decode(Config.self, from: contents)
        return decoded.expanded()
    }

    private func expanded() -> Config {
        let source = Config.expandSource(self.source)
        let github = GitHub(
            appId: github.appId,
            organization: github.organization,
            repository: github.repository,
            privateKeyPath: Config.expandPath(github.privateKeyPath),
            runnerName: github.runnerName,
            extraLabels: github.extraLabels
        )
        return Config(source: source, github: github, ssh: ssh)
    }

    private static func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        return path
    }

    private static func expandSource(_ source: String) -> String {
        if source.hasPrefix("file://") {
            let prefix = "file://"
            let rawPath = String(source.dropFirst(prefix.count))
            let expanded = expandPath(rawPath)
            return prefix + expanded
        }
        return source
    }
}
