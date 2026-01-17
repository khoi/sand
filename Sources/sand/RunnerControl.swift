import Foundation

final class RunnerControl: @unchecked Sendable {
    private let lock = NSLock()
    private var provisioningHandle: ProcessHandle?
    private var healthCheckTask: Task<Void, Never>?

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

    func setHealthCheckTask(_ task: Task<Void, Never>) {
        lock.lock()
        healthCheckTask = task
        lock.unlock()
    }

    func clearHealthCheckTask() {
        lock.lock()
        healthCheckTask = nil
        lock.unlock()
    }

    func cancelHealthCheck() {
        lock.lock()
        let task = healthCheckTask
        healthCheckTask = nil
        lock.unlock()
        task?.cancel()
    }
}
