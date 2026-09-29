import ArgumentParser
import Foundation

@available(macOS 15.0, *)
struct Drain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Wait for active jobs to finish and leave sand idle.")

    @Option(name: .shortAndLong, help: "Configuration used by the running sand service.")
    var config: String = Config.defaultPath

    func run() async throws {
        let (paths, instance) = try ServiceControl.requestDrain(configPath: config)
        print("Drain requested. Waiting for active jobs and VM cleanup...")
        try await ServiceControl.waitUntilDrained(paths: paths, instance: instance)
        print("Drain complete. sand is idle; it is safe to stop or restart the service.")
    }
}
