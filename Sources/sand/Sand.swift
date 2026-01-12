import ArgumentParser
import Foundation

@main
@available(macOS 14.0, *)
struct Sand: AsyncParsableCommand {
    @Option(name: .shortAndLong)
    var config: String = "sand.yml"

    mutating func run() async throws {
        let config = try Config.load(path: config)
        let processRunner = SystemProcessRunner()
        let tart = Tart(processRunner: processRunner)
        let runner = Runner(tart: tart, config: config)
        try await runner.run()
    }
}
