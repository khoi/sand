import Foundation
import XCTest
@testable import sand

final class LoggerFileTests: XCTestCase {
    func testLoggerWritesToFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let path = tempDir.appendingPathComponent("sand.log").path
        let sink = try LogFileSink(path: path)
        let logger = Logger(label: "test.logger", minimumLevel: .info, sink: sink)
        logger.info("hello")

        let contents = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(contents.contains("[info] test.logger hello"))
    }
}
