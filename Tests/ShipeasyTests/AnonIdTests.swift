import XCTest
@testable import Shipeasy

final class AnonIdTests: XCTestCase {
    func testMintIsValidUuid() {
        let id = AnonId.mint()
        XCTAssertTrue(AnonId.isValid(id))
        XCTAssertEqual(id.count, 36)
        XCTAssertNotEqual(AnonId.mint(), AnonId.mint())
    }

    func testRejectsTampered() {
        XCTAssertFalse(AnonId.isValid("bad value!"))
        XCTAssertFalse(AnonId.isValid(nil))
        XCTAssertFalse(AnonId.isValid(""))
    }

    func testReadFromCookieHeader() {
        XCTAssertEqual(AnonId.read(cookieHeader: "a=1; __se_anon_id=xyz-1; b=2"), "xyz-1")
        XCTAssertNil(AnonId.read(cookieHeader: "a=1; b=2"))
        XCTAssertNil(AnonId.read(cookieHeader: nil))
    }

    func testResolveReusesValidCookie() {
        let r = AnonId.resolve(cookieHeader: "__se_anon_id=stable-1")
        XCTAssertEqual(r.id, "stable-1")
        XCTAssertFalse(r.minted)
    }

    func testResolveMintsWhenAbsentOrTampered() {
        let absent = AnonId.resolve(cookieHeader: nil)
        XCTAssertTrue(absent.minted)
        XCTAssertTrue(AnonId.isValid(absent.id))

        let tampered = AnonId.resolve(cookieHeader: "__se_anon_id=bad value!")
        XCTAssertTrue(tampered.minted)
        XCTAssertNotEqual(tampered.id, "bad value!")
    }

    func testSetCookieHeaderContract() {
        let h = AnonId.setCookieHeader("abc", secure: true)
        XCTAssertTrue(h.contains("__se_anon_id=abc"))
        XCTAssertTrue(h.contains("Path=/"))
        XCTAssertTrue(h.contains("Max-Age=31536000"))
        XCTAssertTrue(h.contains("SameSite=Lax"))
        XCTAssertTrue(h.contains("Secure"))
        XCTAssertFalse(h.contains("HttpOnly"))
        XCTAssertFalse(AnonId.setCookieHeader("abc", secure: false).contains("Secure"))
    }
}
