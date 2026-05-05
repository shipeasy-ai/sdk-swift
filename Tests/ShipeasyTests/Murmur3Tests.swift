import XCTest
@testable import Shipeasy

final class Murmur3Tests: XCTestCase {
    func testVectors() {
        // Values match the Ruby SDK reference impl across languages.
        let cases: [(String, UInt32)] = [
            ("", 0x00000000),
            ("a", 0x3c2569b2),
            ("ab", 0x9bbfd75f),
            ("abc", 0xb3dd93fa),
            ("aaaa", 0x7eeed987),
            ("aaaaa", 0xe9ca302b),
            ("Hello, 世界", 0xe2a131eb),
            ("The quick brown fox jumps over the lazy dog", 0x2e4ff723),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(Murmur3.hash32(input), expected, input)
        }
    }
}
