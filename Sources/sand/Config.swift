import Foundation
import Yams

struct Config: Decodable {
    struct VM: Decodable {
        let source: VMSource
        let hardware: Hardware?
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
        let ramGb: Int
    }

    let vm: VM

    static func load(path: String) throws -> Config {
        let expandedPath = expandPath(path)
        let contents = try String(contentsOfFile: expandedPath, encoding: .utf8)
        let decoder = YAMLDecoder()
        let decoded = try decoder.decode(Config.self, from: contents)
        return decoded.expanded()
    }

    private func expanded() -> Config {
        switch vm.source.type {
        case .oci:
            return self
        case .local:
            let expandedPath = Config.expandFileURL(vm.source.path ?? "")
            let source = VMSource(type: .local, image: nil, path: expandedPath)
            let vm = VM(source: source, hardware: vm.hardware)
            return Config(vm: vm)
        }
    }

    private static func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        return path
    }

    private static func expandFileURL(_ path: String) -> String {
        let prefix = "file://"
        if path.hasPrefix(prefix) {
            let rawPath = String(path.dropFirst(prefix.count))
            return prefix + expandPath(rawPath)
        }
        return prefix + expandPath(path)
    }
}
