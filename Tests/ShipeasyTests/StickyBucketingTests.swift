import XCTest
@testable import Shipeasy

/// Feature C — sticky bucketing. With a store supplied, a unit locks to its
/// first-assigned variant; the allocation gate is skipped on subsequent evals as
/// long as the stored salt8 still matches. Salt rotation re-buckets and
/// overwrites. Absent store ⇒ deterministic (unchanged) behaviour.
final class StickyBucketingTests: XCTestCase {
    // A 2-group experiment fully allocated, deterministic salt.
    private func snapshotExps(salt: String = "salt12345", alloc: Int = 10000) -> [String: Any] {
        [
            "experiments": [
                "price_test": [
                    "status": "running", "salt": salt, "allocationPct": alloc, "universe": "u",
                    "groups": [
                        ["name": "control", "weight": 5000, "params": ["price": 10]],
                        ["name": "treatment", "weight": 5000, "params": ["price": 9]],
                    ],
                ]
            ],
            "universes": ["u": [:]],
        ]
    }

    // In-memory store wired in → an enrolled unit is persisted, and a second eval
    // returns the SAME group from the store.
    func testFreshPickIsPersistedAndReused() async {
        let store = InMemoryStickyBucketStore()
        let client = Engine.fromSnapshot(flags: [:], experiments: snapshotExps(), stickyStore: store)

        let first = await client.getExperiment("price_test", user: ["user_id": "u1"], defaultParams: nil)
        XCTAssertTrue(first.inExperiment)

        // The store now holds the assignment under (unit, exp).
        let entry = store.get("u1")?["price_test"]
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.group, first.group)
        XCTAssertEqual(entry?.salt8, String("salt12345".prefix(8)))

        let second = await client.getExperiment("price_test", user: ["user_id": "u1"], defaultParams: nil)
        XCTAssertEqual(second.group, first.group)
    }

    // A pre-seeded entry whose salt8 matches is honored even when allocation has
    // shrunk to 0% — the sticky short-circuit skips the allocation gate.
    func testStoredEntrySkipsAllocationGate() async {
        let store = InMemoryStickyBucketStore(seed: [
            "u1": ["price_test": StickyEntry(group: "treatment", salt8: "salt1234")]
        ])
        // allocationPct 0 would exclude everyone without stickiness.
        let client = Engine.fromSnapshot(
            flags: [:], experiments: snapshotExps(alloc: 0), stickyStore: store
        )
        let r = await client.getExperiment("price_test", user: ["user_id": "u1"], defaultParams: nil)
        XCTAssertTrue(r.inExperiment)
        XCTAssertEqual(r.group, "treatment")
    }

    // A stored entry with a STALE salt8 (experiment salt rotated) is ignored:
    // the unit re-buckets and the store is overwritten with the new salt8.
    func testSaltMismatchRebucketsAndOverwrites() async {
        let store = InMemoryStickyBucketStore(seed: [
            "u1": ["price_test": StickyEntry(group: "treatment", salt8: "OLDSALT0")]
        ])
        let client = Engine.fromSnapshot(
            flags: [:], experiments: snapshotExps(salt: "salt12345"), stickyStore: store
        )
        let r = await client.getExperiment("price_test", user: ["user_id": "u1"], defaultParams: nil)
        XCTAssertTrue(r.inExperiment)
        // Store overwritten with the current salt8.
        XCTAssertEqual(store.get("u1")?["price_test"]?.salt8, String("salt12345".prefix(8)))
    }

    // No store ⇒ deterministic: same input gives the same group, nothing
    // persisted (there is no store to persist to).
    func testNoStoreIsDeterministic() async {
        let client = Engine.fromSnapshot(flags: [:], experiments: snapshotExps())
        let a = await client.getExperiment("price_test", user: ["user_id": "u1"], defaultParams: nil)
        let b = await client.getExperiment("price_test", user: ["user_id": "u1"], defaultParams: nil)
        XCTAssertEqual(a.group, b.group)
    }

    // A stored entry whose group no longer exists falls through to a re-bucket.
    func testVanishedGroupRebuckets() async {
        let store = InMemoryStickyBucketStore(seed: [
            "u1": ["price_test": StickyEntry(group: "deleted_group", salt8: "salt1234")]
        ])
        let client = Engine.fromSnapshot(flags: [:], experiments: snapshotExps(), stickyStore: store)
        let r = await client.getExperiment("price_test", user: ["user_id": "u1"], defaultParams: nil)
        XCTAssertTrue(r.inExperiment)
        XCTAssertTrue(["control", "treatment"].contains(r.group))
    }

    // The in-memory store get/set round-trips.
    func testInMemoryStoreRoundTrip() {
        let store = InMemoryStickyBucketStore()
        XCTAssertNil(store.get("u1"))
        store.set("u1", "exp", StickyEntry(group: "g", salt8: "abcdef12"))
        XCTAssertEqual(store.get("u1")?["exp"]?.group, "g")
        XCTAssertEqual(store.get("u1")?["exp"]?.salt8, "abcdef12")
        // A second exp under the same unit coexists.
        store.set("u1", "exp2", StickyEntry(group: "h", salt8: "00000000"))
        XCTAssertEqual(store.get("u1")?.count, 2)
    }
}
