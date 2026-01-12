import Foundation
import OSLog

struct Runner {
    let tart: Tart
    let config: Config
    private let logger = Logger(subsystem: "sand", category: "runner")

    func run() async throws {
        try await runOnce()
    }

    private func runOnce() async throws {
        let name = "ephemeral"
        let source = config.vm.source.resolvedSource
        logger.info("prepare source \(source, privacy: .public)")
        try tart.prepare(source: source)
        logger.info("clone VM \(name, privacy: .public) from \(source, privacy: .public)")
        try tart.clone(source: source, name: name)
        defer {
            logger.info("delete VM \(name, privacy: .public)")
            try? tart.delete(name: name)
        }
        logger.info("boot VM \(name, privacy: .public)")
        try tart.run(name: name)
        defer {
            logger.info("stop VM \(name, privacy: .public)")
            try? tart.stop(name: name)
        }
        logger.info("wait for VM IP")
        let ip = try tart.ip(name: name, wait: 60)
        logger.info("VM IP \(ip, privacy: .public)")
    }
}
