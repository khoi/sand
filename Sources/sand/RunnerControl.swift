import Foundation

final class RunnerControl: @unchecked Sendable {
    private let lock = NSLock()
    private var provisioningHandle: ProcessHandle?

    func setProvisioningHandle(_ handle: ProcessHandle) {
        lock.lock()
        provisioningHandle = handle
        lock.unlock()
    }

    func clearProvisioningHandle(_ handle: ProcessHandle) {
        lock.lock()
        if provisioningHandle === handle {
            provisioningHandle = nil
        }
        lock.unlock()
    }

    func terminateProvisioning() {
        lock.lock()
        let handle = provisioningHandle
        provisioningHandle = nil
        lock.unlock()
        handle?.terminate()
    }
}
