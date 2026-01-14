import Foundation

struct SSHWaiter {
    static func wait(for ssh: SSHClient, logger: Logger) async -> Bool {
        var attempt = 0
        let maxRetries = ssh.config.connectMaxRetries
        while true {
            if let maxRetries, attempt >= maxRetries {
                logger.warning("SSH not ready after \(maxRetries) attempts, restarting VM")
                return false
            }
            attempt += 1
            do {
                try ssh.checkConnection()
                return true
            } catch {
                if let maxRetries {
                    logger.info("SSH not ready, retrying in 1s (attempt \(attempt)/\(maxRetries))")
                } else {
                    logger.info("SSH not ready, retrying in 1s (attempt \(attempt))")
                }
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return false
                }
            }
        }
    }
}
