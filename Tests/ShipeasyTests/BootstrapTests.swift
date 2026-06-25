import XCTest
@testable import Shipeasy

final class BootstrapTests: XCTestCase {
    private func client() -> Engine {
        Engine.fromSnapshot(
            flags: [
                "gates": [
                    "new_ui": ["enabled": true, "rolloutPct": 10000, "salt": "s"],
                    "off_gate": ["enabled": false, "rolloutPct": 10000, "salt": "s"],
                ],
                "configs": ["theme": ["value": ["color": "blue"]]],
            ],
            experiments: ["experiments": [String: Any](), "universes": [String: Any]()]
        )
    }

    func testEvaluateBuildsPayload() async {
        let p = await client().evaluate(["user_id": "u1"])
        let flags = p["flags"] as? [String: Any]
        XCTAssertEqual(flags?["new_ui"] as? Bool, true)
        XCTAssertEqual(flags?["off_gate"] as? Bool, false)
        let ks = p["killswitches"] as? [String: Any]
        XCTAssertEqual(ks?.count, 0)
    }

    func testBootstrapScriptTagAttrs() async throws {
        let tag = await client().bootstrapScriptTag(["user_id": "u1"], anonId: "anon-1")
        XCTAssertTrue(tag.contains("src=\"https://cdn.shipeasy.ai/sdk/bootstrap.js\""))
        XCTAssertTrue(tag.contains("data-se-bootstrap"))
        XCTAssertTrue(tag.contains("data-anon-id=\"anon-1\""))
        XCTAssertTrue(tag.contains("data-i18n-profile=\"en:prod\""))
        XCTAssertFalse(tag.contains("data-key"))

        // data-flags decodes back to valid JSON with the evaluated flag.
        let raw = String(tag[tag.range(of: "data-flags=\"")!.upperBound...])
        let inner = String(raw[..<raw.range(of: "\"")!.lowerBound])
        let decoded = inner
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        let obj = try JSONSerialization.jsonObject(with: Data(decoded.utf8)) as? [String: Any]
        XCTAssertEqual(obj?["new_ui"] as? Bool, true)
    }

    func testBootstrapScriptTagOmitsAnonWhenUnset() async {
        let tag = await client().bootstrapScriptTag(["user_id": "u1"])
        XCTAssertFalse(tag.contains("data-anon-id"))
    }

    func testI18nScriptTag() async {
        let tag = await client().i18nScriptTag("client_pub", profile: "fr:prod")
        XCTAssertTrue(tag.contains("src=\"https://cdn.shipeasy.ai/sdk/i18n/loader.js\""))
        XCTAssertTrue(tag.contains("data-key=\"client_pub\""))
        XCTAssertTrue(tag.contains("data-profile=\"fr:prod\""))
    }
}
