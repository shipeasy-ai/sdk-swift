import Foundation
import XCTest

// Global test-suite egress posture.
//
// As of the environment-derived egress defaults, the SDK is QUIET outside
// production: with no `SHIPEASY_ENV` / `APP_ENV` / `ENV` set and a DEBUG build,
// `isProductionEnv` returns false and the client goes fully offline (no
// /sdk/evaluate, no /collect). The test suite exercises those real network
// paths against stub transports, so it must declare itself production-equivalent
// for egress — mirroring what sdk-ts does in `src/__tests__/setup.ts`.
//
// `SHIPEASY_ENV=production` is set once, as early as possible, via this file's
// top-level side effect (the runner links every test file, so this executes
// before any test method). Individual env-branching tests in `EnvDefaultsTests`
// override the vars locally and restore them.
private let _installProductionEnv: Void = {
    setenv("SHIPEASY_ENV", "production", 1)
}()

/// Base class that forces the production egress posture in `setUp`, in case the
/// top-level installer above is optimised away or a prior test left the vars in
/// a non-prod state. Network-dependent test cases subclass this.
class ShipeasyProdEnvTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = _installProductionEnv
        setenv("SHIPEASY_ENV", "production", 1)
    }
}
