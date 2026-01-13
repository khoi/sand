import Foundation
import Logging

struct VMDestroyer {
    let tart: Tart
    let logger: Logger

    func destroy(name: String) {
        logger.info("stop VM \(name)")
        try? tart.stop(name: name)
        logger.info("delete VM \(name)")
        try? tart.delete(name: name)
    }
}
