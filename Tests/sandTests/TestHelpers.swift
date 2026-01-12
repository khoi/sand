import Foundation
import XCTest

func writeTempFile(contents: String, suffix: String = "") throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("temp\(suffix)")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

func decodeJWTClaims(_ token: String) throws -> [String: Any] {
    let parts = token.split(separator: ".")
    XCTAssertEqual(parts.count, 3)
    let payload = String(parts[1])
    let data = try base64URLDecode(payload)
    let json = try JSONSerialization.jsonObject(with: data)
    guard let dict = json as? [String: Any] else {
        XCTFail("Invalid payload")
        return [:]
    }
    return dict
}

func base64URLDecode(_ value: String) throws -> Data {
    var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let padding = base64.count % 4
    if padding != 0 {
        base64 += String(repeating: "=", count: 4 - padding)
    }
    guard let data = Data(base64Encoded: base64) else {
        throw NSError(domain: "base64", code: 1)
    }
    return data
}
