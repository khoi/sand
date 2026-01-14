import Foundation

struct VMDestroyer {
    let tart: Tart
    let logger: Logger

    func destroy(name: String) throws {
        logger.info("stop VM \(name)")
        try? tart.stop(name: name)
        logger.info("delete VM \(name)")
        try? tart.delete(name: name)
    }
}
