import Foundation
import Yams

struct Config: Decodable {
    struct SSH: Decodable {
        let username: String
        let password: String
    }

    struct Provisioner: Decodable {
        enum ProvisionerType: String, Decodable {
            case script
            case github
        }

        struct Script: Decodable {
            let run: String
        }

        struct GitHub: Decodable {
            let appId: Int
            let organization: String
            let repository: String?
            let privateKeyPath: String
            let runnerName: String
            let extraLabels: [String]?
        }

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

    let source: String
    let provisioner: Provisioner
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
        let provisioner = self.provisioner.expanded()
        return Config(source: source, provisioner: provisioner, ssh: ssh)
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

extension Config.Provisioner {
    func expanded() -> Config.Provisioner {
        switch type {
        case .script:
            return self
        case .github:
            guard let github else {
                return self
            }
            let expanded = Config.Provisioner.GitHub(
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
