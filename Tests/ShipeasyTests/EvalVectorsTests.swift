import XCTest
@testable import Shipeasy

/// Cross-language eval-parity golden-vector test.
///
/// Loads the canonical fixture (copied byte-identically from
/// `packages/core/src/eval/__fixtures__/eval-vectors.json`) and asserts that
/// this SDK's Murmur3 + gate/experiment bucketing reproduce every vector.
/// If any vector fails here, bucketing has drifted from the platform's
/// canonical implementation — do NOT "fix" the test, fix the SDK (or the
/// fixture, at its source in packages/core).
final class EvalVectorsTests: XCTestCase {
    // MARK: - Fixture loading

    private struct Fixture {
        let bucketModulo: UInt32
        let hash: [[String: Any]]
        let gate: [[String: Any]]
        let experiment: [[String: Any]]
    }

    private func loadFixture() throws -> Fixture {
        guard let url = Bundle.module.url(forResource: "eval-vectors", withExtension: "json") else {
            throw XCTSkip("eval-vectors.json not bundled in test resources")
        }
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "EvalVectorsTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "fixture root is not an object"])
        }
        let modulo = (root["bucketModulo"] as? Int) ?? 10000
        return Fixture(
            bucketModulo: UInt32(modulo),
            hash: root["hash"] as? [[String: Any]] ?? [],
            gate: root["gate"] as? [[String: Any]] ?? [],
            experiment: root["experiment"] as? [[String: Any]] ?? []
        )
    }

    // MARK: - (a) hash vectors

    func testHashVectors() throws {
        let fixture = try loadFixture()
        XCTAssertFalse(fixture.hash.isEmpty, "no hash vectors loaded")
        for vec in fixture.hash {
            guard let input = vec["input"] as? String else {
                XCTFail("hash vector missing string `input`: \(vec)")
                continue
            }
            // hash is a uint32 decimal; JSONSerialization yields NSNumber → read as UInt32.
            guard let expected = (vec["hash"] as? NSNumber)?.uint32Value else {
                XCTFail("hash vector missing uint32 `hash` for input \(input)")
                continue
            }
            XCTAssertEqual(
                Murmur3.hash32(input), expected,
                "hash32(\(String(reflecting: input))) drifted: got \(Murmur3.hash32(input)), want \(expected)"
            )
        }
    }

    // MARK: - (b) gate vectors

    func testGateVectors() throws {
        let fixture = try loadFixture()
        XCTAssertFalse(fixture.gate.isEmpty, "no gate vectors loaded")
        for vec in fixture.gate {
            let note = vec["note"] as? String ?? ""
            guard let gate = vec["gate"] as? [String: Any],
                  let user = vec["user"] as? [String: Any],
                  let expected = vec["pass"] as? Bool else {
                XCTFail("malformed gate vector: \(vec)")
                continue
            }
            XCTAssertEqual(Eval.evalGate(gate, user), expected, "gate vector failed: \(note)")
        }
    }

    // MARK: - (c) experiment vectors

    func testExperimentVectors() throws {
        let fixture = try loadFixture()
        XCTAssertFalse(fixture.experiment.isEmpty, "no experiment vectors loaded")
        for vec in fixture.experiment {
            let note = vec["note"] as? String ?? ""
            guard let exp = vec["experiment"] as? [String: Any],
                  let user = vec["user"] as? [String: Any],
                  let result = vec["result"] as? [String: Any],
                  let expectedIn = result["inExperiment"] as? Bool else {
                XCTFail("malformed experiment vector: \(vec)")
                continue
            }
            let expectedGroup = result["group"] as? String  // null → nil

            // The fixture expresses targeting as a flat `flags: {gateName: bool}`
            // map; this SDK's evalExperiment consumes a flags blob shaped
            // `{ gates: { name: <gate> } }` and re-evaluates the targeting gate.
            // Lower a boolean flag to a synthetic gate that evaluates to that
            // boolean for any unit (enabled+100% → true, disabled → false).
            let flagsMap = vec["flags"] as? [String: Any] ?? [:]
            var gates: [String: Any] = [:]
            for (name, raw) in flagsMap {
                let on = (raw as? Bool) ?? false
                gates[name] = [
                    "enabled": on,
                    "rolloutPct": 10000,
                    "salt": "",
                    "rules": [[String: Any]](),
                ] as [String: Any]
            }
            let flagsBlob: [String: Any] = ["gates": gates]

            // The fixture expresses the universe holdout as a per-vector
            // `holdoutRange: [lo,hi] | null`; this SDK reads it from the exps
            // blob at `universes.<name>.holdout_range`.
            var expsBlob: [String: Any] = [:]
            if let holdout = vec["holdoutRange"] as? [Int],
               let universe = exp["universe"] as? String {
                expsBlob = ["universes": [universe: ["holdout_range": holdout]]]
            }

            let r = Eval.evalExperiment(exp, flagsBlob, expsBlob, user)

            XCTAssertEqual(r.inExperiment, expectedIn, "experiment inExperiment failed: \(note)")
            if expectedIn {
                XCTAssertEqual(r.group, expectedGroup, "experiment group failed: \(note)")
            }
        }
    }
}
