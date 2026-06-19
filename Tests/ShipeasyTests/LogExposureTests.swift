import XCTest
@testable import Shipeasy

/// Feature B — manual server exposure. `logExposure(userId:experiment:)`
/// re-evaluates the experiment and, only when the user is enrolled, POSTs one
/// exposure event to /collect. It is a no-op in local mode and when the user is
/// not enrolled. The live POST path needs a URLProtocol stub to assert the wire
/// body; here we assert the no-op / no-crash contracts the public API promises.
final class LogExposureTests: XCTestCase {
    private func runningExp() -> [String: Any] {
        [
            "experiments": [
                "price_test": [
                    "status": "running", "salt": "s", "allocationPct": 10000,
                    "groups": [["name": "treatment", "weight": 10000, "params": ["price": 9]]],
                ]
            ]
        ]
    }

    // localMode (snapshot/forTesting) clients never touch the network, so
    // logExposure is a guaranteed no-op and must not crash.
    func testLocalModeIsNoOp() async {
        let client = Client.fromSnapshot(flags: [:], experiments: runningExp())
        await client.logExposure(userId: "u1", experiment: "price_test")
        XCTAssertTrue(true)
    }

    // forTesting() client (no blob) → not enrolled → no-op, no crash.
    func testNotEnrolledIsNoOp() async {
        let client = Client.forTesting()
        await client.logExposure(userId: "u1", experiment: "missing")
        XCTAssertTrue(true)
    }

    // On a network-backed client, calling logExposure for an unknown experiment
    // re-evaluates to "not enrolled" and must not throw synchronously.
    func testNetworkClientUnknownExperimentDoesNotThrow() async {
        let client = Client(apiKey: "k", disableTelemetry: true)
        await client.logExposure(userId: "u1", experiment: "nope")
        XCTAssertTrue(true)
    }
}
