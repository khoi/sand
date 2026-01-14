import Foundation

struct VMDestroyer {
    let tart: Tart
    let logger: Logger

    func destroy(name: String) throws {
        var firstError: Error?
        logger.info("stop VM \(name)")
        do {
            try tart.stop(name: name)
        } catch {
            if firstError == nil {
                firstError = error
            }
            logger.error("stop VM \(name) failed: \(String(describing: error))")
        }
        logger.info("delete VM \(name)")
        do {
            try tart.delete(name: name)
        } catch {
            if firstError == nil {
                firstError = error
            }
            logger.error("delete VM \(name) failed: \(String(describing: error))")
        }
        if let firstError {
            throw firstError
        }
    }
}
