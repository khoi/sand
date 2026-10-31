import Foundation

/// One Tart disk attachment, never a fragment of a shell command or arbitrary flags.
struct DiskAttachment: Decodable, Equatable, Sendable {
    enum Synchronization: String, Decodable, CaseIterable, Sendable {
        case disabled = "none"
        case fsync
        case full
    }

    enum Caching: String, Decodable, CaseIterable, Sendable {
        case automatic
        case cached
        case uncached
    }

    enum InvalidAttachment: LocalizedError {
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let message):
                return message
            }
        }
    }

    let source: String
    let readOnly: Bool
    let synchronization: Synchronization?
    let caching: Caching?

    init(
        source: String,
        readOnly: Bool = false,
        synchronization: Synchronization? = nil,
        caching: Caching? = nil
    ) throws {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !source.contains(where: { $0 == "\0" || $0 == "\n" || $0 == "\r" }),
              !source.hasSuffix(":") else {
            throw InvalidAttachment.invalid("Disk attachment source must be nonempty and contain no NUL or line breaks.")
        }
        // Tart consumes a final recognized option segment, even with no colon.
        // Mapping-form sources must therefore keep those options in typed fields.
        guard !Self.containsOption(String(source.split(separator: ":").last ?? "")) else {
            throw InvalidAttachment.invalid("Keep disk options out of source; use readOnly, synchronization and caching fields.")
        }
        let networkSchemes = ["nbd", "nbds", "nbd+unix", "nbds+unix"]
        if let scheme = URL(string: source)?.scheme, networkSchemes.contains(scheme) {
            guard synchronization != .fsync, caching == nil else {
                throw InvalidAttachment.invalid("NBD attachments support synchronization none/full and no disk-image caching option.")
            }
        }
        self.source = source
        self.readOnly = readOnly
        self.synchronization = synchronization
        self.caching = caching
    }

    var tartArgument: String {
        var options: [String] = []
        if readOnly { options.append("ro") }
        if let synchronization { options.append("sync=\(synchronization.rawValue)") }
        if let caching { options.append("caching=\(caching.rawValue)") }
        return "--disk=\(source)" + (options.isEmpty ? "" : ":" + options.joined(separator: ","))
    }

    func expanded() -> Self {
        // Only local leading-tilde paths are expanded; URL syntax stays intact.
        guard source.hasPrefix("~") else { return self }
        return Self(
            validatedSource: (source as NSString).expandingTildeInPath,
            readOnly: readOnly,
            synchronization: synchronization,
            caching: caching
        )
    }

    private init(
        validatedSource: String,
        readOnly: Bool,
        synchronization: Synchronization?,
        caching: Caching?
    ) {
        self.source = validatedSource
        self.readOnly = readOnly
        self.synchronization = synchronization
        self.caching = caching
    }

    private static func containsOption(_ suffix: String) -> Bool {
        suffix.split(separator: ",", omittingEmptySubsequences: false).contains {
            $0 == "ro" || $0.hasPrefix("sync=") || $0.hasPrefix("caching=")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case readOnly
        case synchronization
        case caching
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            source: container.decode(String.self, forKey: .source),
            readOnly: container.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false,
            synchronization: container.decodeIfPresent(Synchronization.self, forKey: .synchronization),
            caching: container.decodeIfPresent(Caching.self, forKey: .caching)
        )
    }
}
