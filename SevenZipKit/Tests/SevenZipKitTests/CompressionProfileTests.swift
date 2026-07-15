import Foundation
import XCTest
@testable import SevenZipKit

final class CompressionProfileTests: XCTestCase {

    // Ships built-in profiles with stable identities
    func testBuiltIns() {
        let allBuiltIn = CompressionProfile.builtIns.allSatisfy { $0.isBuiltIn }
        let stableIDs = CompressionProfile.builtIns.map(\.id) == CompressionProfile.builtIns.map(\.id)
        XCTAssertTrue(!CompressionProfile.builtIns.isEmpty)
        XCTAssertTrue(allBuiltIn)
        XCTAssertTrue(stableIDs)
    }

    // The Encrypted profile requests a password and encrypted headers
    func testEncryptedProfile() throws {
        let encrypted = try XCTUnwrap(CompressionProfile.builtIns.first { $0.name == "Encrypted" })
        XCTAssertTrue(encrypted.requiresPassword)
        XCTAssertTrue(encrypted.encryptFileNames)
        XCTAssertEqual(encrypted.format, .sevenZip)
    }

    // The Split profile carries a volume size
    func testSplitProfile() throws {
        let split = try XCTUnwrap(CompressionProfile.builtIns.first { $0.name.contains("Split") })
        XCTAssertNotNil(split.volumeSize)
        XCTAssertTrue((split.volumeSize ?? 0) > 0)
    }

    // Encodes and decodes round-trip
    func testCodableRoundTrip() throws {
        let profile = CompressionProfile(
            name: "My Preset", format: .zip, level: .maximum,
            encryptFileNames: false, requiresPassword: true, volumeSize: 700 * 1024 * 1024
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(CompressionProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }
}
