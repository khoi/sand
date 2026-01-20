import Foundation

actor RunnerControl {
    private var provisioningHandle: ProcessHandle?
    private var healthCheckTask: Task<Void, Never>?

    func setProvisioningHandle(_ handle: ProcessHandle) {
        provisioningHandle = handle
    }

    func clearProvisioningHandle(_ handle: ProcessHandle) {
        if provisioningHandle === handle {
            provisioningHandle = nil
        }
    }

    func terminateProvisioning() async {
        let handle = provisioningHandle
        provisioningHandle = nil
        if let handle {
            await handle.terminate()
        }
    }

    func setHealthCheckTask(_ task: Task<Void, Never>) {
        healthCheckTask = task
    }

    func clearHealthCheckTask() {
        healthCheckTask = nil
    }

    func cancelHealthCheck() {
        let task = healthCheckTask
        healthCheckTask = nil
        task?.cancel()
    }
}
