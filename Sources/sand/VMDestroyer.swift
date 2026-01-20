import Foundation

struct VMDestroyer {
    let tart: Tart
    let logger: Logger

    func destroy(name: String) async throws {
        logger.info("stop VM \(name)")
        do {
            try await tart.stop(name: name, timeout: 30)
        } catch {
            logger.warning("failed to stop VM \(name): \(String(describing: error))")
        }
        logger.info("delete VM \(name)")
        do {
            try await tart.delete(name: name)
        } catch {
            logger.warning("failed to delete VM \(name): \(String(describing: error))")
        }
    }
}
