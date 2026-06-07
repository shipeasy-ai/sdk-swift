import XCTest
@testable import Shipeasy

final class TelemetryTests: XCTestCase {
    /// Thread-safe URL recorder for the injected sender.
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [String] = []
        func add(_ u: String) { lock.lock(); urls.append(u); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return urls }
    }

    // 1) basic telemetry send works for each entity call, hitting the right URL.
    func testFiresPerEntity() {
        let box = Box()
        let t = Telemetry(
            endpoint: "https://e.x", sdkKey: "srv", side: "server", env: "prod",
            disabled: false, sender: { box.add($0) }
        )

        t.emit("gate", "g")
        t.emit("config", "c")
        t.emit("experiment", "e")
        t.emit("ks", "k")

        let urls = box.all
        XCTAssertEqual(urls.count, 4)
        XCTAssertTrue(urls[0].hasSuffix("/gate/g"))
        XCTAssertTrue(urls[1].hasSuffix("/config/c"))
        XCTAssertTrue(urls[2].hasSuffix("/experiment/e"))
        XCTAssertTrue(urls[3].hasSuffix("/ks/k"))
        for u in urls {
            XCTAssertTrue(u.hasPrefix("https://e.x/t/"))
            XCTAssertFalse(u.contains("srv")) // raw key never appears in the URL
        }
    }

    // 2) telemetry is not sent when disabled in settings.
    func testDisabledSendsNothing() {
        let box = Box()
        let t = Telemetry(
            endpoint: "https://e.x", sdkKey: "srv", side: "server", env: "prod",
            disabled: true, sender: { box.add($0) }
        )

        t.emit("gate", "g")
        t.emit("config", "c")
        t.emit("experiment", "e")

        XCTAssertTrue(box.all.isEmpty)
    }
}
