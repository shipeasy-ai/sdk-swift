import XCTest
@testable import Shipeasy

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Environment-derived egress defaults: network + usage telemetry are ON in
/// production and OFF everywhere else, so an app embedding the SDK never phones
/// home from a dev machine or CI. Production is read from `SHIPEASY_ENV` /
/// `APP_ENV` / `ENV`, falling back to the `#if DEBUG` build flag, then to the
/// SDK's own `env` option (default "prod").
///
/// These tests manipulate the native env vars locally and restore them, so they
/// deliberately do NOT inherit the suite-wide `SHIPEASY_ENV=production` posture.
final class EnvDefaultsTests: XCTestCase {

    /// Snapshot + restore the three native env vars around each test.
    private var saved: [String: String?] = [:]
    private let vars = ["SHIPEASY_ENV", "APP_ENV", "ENV"]

    override func setUp() {
        super.setUp()
        for k in vars { saved[k] = ProcessInfo.processInfo.environment[k] }
        for k in vars { unsetenv(k) }
    }

    override func tearDown() {
        for k in vars {
            if let v = saved[k] ?? nil { setenv(k, v, 1) } else { unsetenv(k) }
        }
        super.tearDown()
    }

    // Records requests + replies 200 to /sdk/evaluate and /collect.
    final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requests: [URLRequest] = []
        func paths(_ suffix: String) -> [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return requests.filter { $0.url?.path.hasSuffix(suffix) ?? false }
        }
        var transport: ShipeasyClient.Transport {
            { [self] req in
                lock.lock(); requests.append(req); lock.unlock()
                let isEval = req.url?.path.hasSuffix("/sdk/evaluate") ?? false
                let body = isEval
                    ? try JSONSerialization.data(withJSONObject: ["flags": [:], "configs": [:], "experiments": [:], "killswitches": [:]])
                    : Data()
                return (body, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
    }

    final class MemStore: AnonymousStore, @unchecked Sendable {
        private let lock = NSLock(); private var map: [String: String] = [:]
        func get(_ key: String) -> String? { lock.lock(); defer { lock.unlock() }; return map[key] }
        func set(_ key: String, _ value: String) { lock.lock(); map[key] = value; lock.unlock() }
    }

    private func makeClient(_ stub: Stub, isNetworkEnabled: Bool? = nil, env: String = "prod") -> ShipeasyClient {
        ShipeasyClient(
            clientKey: "pk",
            baseURL: URL(string: "https://api.shipeasy.ai")!,
            env: env,
            isNetworkEnabled: isNetworkEnabled,
            store: MemStore(),
            transport: stub.transport
        )
    }

    // MARK: - isProductionEnv precedence

    func testProductionEnvVarWins() {
        setenv("SHIPEASY_ENV", "production", 1)
        setenv("APP_ENV", "development", 1)
        XCTAssertTrue(isProductionEnv("dev")) // native prod wins over configured "dev"

        setenv("SHIPEASY_ENV", "PROD", 1) // case-insensitive
        XCTAssertTrue(isProductionEnv())
    }

    func testNativeNonProdEnvIsNotProduction() {
        setenv("SHIPEASY_ENV", "development", 1)
        XCTAssertFalse(isProductionEnv("prod")) // configured prod cannot override a native dev signal

        setenv("SHIPEASY_ENV", "staging", 1)
        XCTAssertFalse(isProductionEnv("prod"))

        setenv("SHIPEASY_ENV", "test", 1)
        XCTAssertFalse(isProductionEnv("prod"))
    }

    func testPrecedenceOrderAcrossVars() {
        // ENV set but SHIPEASY_ENV/APP_ENV unset → ENV is consulted.
        setenv("ENV", "production", 1)
        XCTAssertTrue(isProductionEnv("dev"))
        // APP_ENV outranks ENV.
        setenv("APP_ENV", "development", 1)
        XCTAssertFalse(isProductionEnv("prod"))
        // SHIPEASY_ENV outranks both.
        setenv("SHIPEASY_ENV", "prod", 1)
        XCTAssertTrue(isProductionEnv("dev"))
    }

    func testFallsBackToBuildFlagAndConfiguredEnvWhenNoNativeVar() {
        // No native var set (setUp cleared them).
        #if DEBUG
        // DEBUG build with no native signal ⇒ not production, regardless of env option.
        XCTAssertFalse(isProductionEnv("prod"))
        XCTAssertFalse(isProductionEnv("dev"))
        #else
        // Release build with no native signal ⇒ production, unless the configured
        // env option is explicitly non-prod.
        XCTAssertTrue(isProductionEnv("prod"))
        XCTAssertTrue(isProductionEnv(nil)) // env option itself defaults to prod
        XCTAssertFalse(isProductionEnv("dev"))
        #endif
    }

    // MARK: - client egress honours the default

    /// Outside production (native dev signal) the client is offline by default:
    /// identify() never calls /sdk/evaluate and track() never calls /collect.
    func testOfflineByDefaultOutsideProduction() async {
        setenv("SHIPEASY_ENV", "development", 1)
        let stub = Stub()
        let client = makeClient(stub)
        await client.identify(["user_id": "u1"])
        await client.track("evt")
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(stub.paths("/sdk/evaluate").isEmpty, "no evaluate fired in dev")
        XCTAssertTrue(stub.paths("/collect").isEmpty, "no collect fired in dev")
        // Reads fall back to the supplied default.
        let f = await client.getFlag("f", default: true)
        XCTAssertTrue(f)
    }

    /// An explicit `isNetworkEnabled: true` overrides the non-prod default.
    func testExplicitNetworkOnOverridesDevDefault() async {
        setenv("SHIPEASY_ENV", "development", 1)
        let stub = Stub()
        let client = makeClient(stub, isNetworkEnabled: true)
        await client.identify(["user_id": "u1"])
        XCTAssertFalse(stub.paths("/sdk/evaluate").isEmpty, "explicit network-on fires evaluate")
    }

    /// In production the client is online by default.
    func testOnlineByDefaultInProduction() async {
        setenv("SHIPEASY_ENV", "production", 1)
        let stub = Stub()
        let client = makeClient(stub)
        await client.identify(["user_id": "u1"])
        XCTAssertFalse(stub.paths("/sdk/evaluate").isEmpty, "evaluate fires by default in prod")
    }

    /// An explicit `isNetworkEnabled: false` forces offline even in production.
    func testExplicitNetworkOffForcesOfflineInProduction() async {
        setenv("SHIPEASY_ENV", "production", 1)
        let stub = Stub()
        let client = makeClient(stub, isNetworkEnabled: false)
        await client.identify(["user_id": "u1"])
        await client.track("evt")
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(stub.paths("/sdk/evaluate").isEmpty)
        XCTAssertTrue(stub.paths("/collect").isEmpty)
    }
}
