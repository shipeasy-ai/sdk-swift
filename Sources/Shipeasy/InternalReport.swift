import Foundation

// URLSession/URLRequest live in FoundationNetworking on non-Apple platforms (Linux).
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Internal self-monitoring channel — SDK bugs that are "on our end"
//
// When the SDK swallows one of its OWN internal errors (the `safeRun` last-
// resort guard in Log.swift, which keeps a getFlag/getConfig/… from throwing or
// trapping into product code even when an internal invariant is violated), it
// ALSO ships a structured see event here — to Shipeasy's OWN project, NOT the
// consumer's — so the SDK team can track SDK-internal failures across every app
// the SDK runs in.
//
// This is deliberately distinct from the customer-facing `see()` path
// (`Engine.see` / the package-level `see()`), which authenticates with the
// consumer's key and lands in the consumer's dashboard. Internal errors must
// never pollute a customer's Errors tab, and the SDK team must see them
// centrally — so this channel has its own baked-in destination + credential.
//
// Guarantees (identical to telemetry/see): fire-and-forget, never blocks, never
// throws into product code, deduped/rate-limited. A failed send is swallowed
// silently — it must never log (that would risk recursion through safeRun).

/// The internal self-monitoring channel. A process-global `@unchecked Sendable`
/// singleton (mirrors how `Log` carries the process-global level): the server
/// SDK is a single bundle, so there is no cross-talk to guard against. Inert
/// until a real ingest key is baked in AND a context is set.
final class InternalReport: @unchecked Sendable {
    static let shared = InternalReport()

    // ---- Baked-in destination ----
    //
    // The main Shipeasy project (`.shipeasy`). The credential is a PUBLIC client
    // key — the same class of credential already embedded verbatim in every
    // browser bundle that ships the client SDK, and mirroring how the CLI bakes
    // Shipeasy's own public key for setup-bug self-reporting — so baking it into
    // the published package is safe. `/collect` treats it as a write-only ingest
    // key; it grants no read access. The canonical ingest host is api.shipeasy.ai
    // (the SDK default baseURL), which routes /collect to the edge worker.
    static let ingestURL = "https://api.shipeasy.ai/collect"

    // Sentinel used until the real key is minted + baked. While `ingestKey` is
    // still the placeholder the channel stays fully inert (see `report(_:_:)`),
    // so a build that ships before the key is provisioned never fires doomed
    // requests. Mint the key with:
    //   shipeasy keys create --type client --env prod \
    //     --name "SDK internal error self-reporting" --scopes events:write
    // then replace the `ingestKey` initializer below with the returned value.
    static let placeholderKey = "sdk_client_REPLACE_WITH_SHIPEASY_INTERNAL_ERROR_KEY"

    // Fixed consequence outcome. The guard `label` (e.g. "flags.get") is the
    // subject; the outcome is constant — no variable data — so occurrences of
    // the same internal bug fold into one issue on our dashboard. `sdk` marks
    // which language SDK reported it.
    static let outcome = "returned a safe default"
    static let sdkId = "swift"

    private let lock = NSLock()
    // The active ingest key. Starts inert; swap in the real minted key by
    // editing `placeholderKey`'s replacement below, or via a test seam.
    private var ingestKey = "sdk_client_00bd4608a03e4084922978f9522614d5"
    // Set once from the Engine initializer. Null until configured (a report
    // before configure is a no-op — nothing to attribute it to).
    private var side: String?
    private var sdkVersion: String?
    private var enabled = true
    // Bounds network chatter from a hot internal-error loop (30s dedup window +
    // a hard per-process cap). The backend dedupes by fingerprint anyway.
    private var limiter = SeeLimiter()
    // Test seam: when set, the built event is handed here instead of the POST.
    private var sink: (@Sendable ([String: Any]) -> Void)?
    private let session: URLSession = .shared

    /// True once a real key has been baked in (not the placeholder sentinel).
    private func keyConfigured() -> Bool {
        !ingestKey.isEmpty && ingestKey != InternalReport.placeholderKey
    }

    /// Wire the self-monitoring channel. Called from the Engine initializer with
    /// the bundle's side + version. `enabled` defaults on; it is forced off in
    /// test mode (no network) and when the caller opts out via
    /// `disableInternalErrorReporting`.
    func setContext(side: String, sdkVersion: String, enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        self.side = side
        self.sdkVersion = sdkVersion
        self.enabled = enabled
    }

    /// Report an SDK-internal error to Shipeasy's own project. Called from
    /// `safeRun`'s catch. `label` is the swallowed operation (e.g. "flags.get")
    /// and becomes the stable issue subject. Never throws.
    func report(_ label: String, _ error: Error) {
        // The whole body is wrapped so any failure — serialization, network — is
        // swallowed. It must never surface into product code, and must never log
        // (that would risk recursion through the guard).
        let (s, v, on, ok): (String?, String?, Bool, Bool) = {
            lock.lock(); defer { lock.unlock() }
            return (side, sdkVersion, enabled, keyConfigured())
        }()
        guard let s, let v, on, ok else { return }
        let built = buildSeeEvent(
            .error(error),
            subject: label,
            outcome: InternalReport.outcome,
            extras: ["sdk": InternalReport.sdkId],
            side: s,
            sdkVersion: v,
            env: nil
        )
        let (allow, key, testSink) = { () -> (Bool, String, (@Sendable ([String: Any]) -> Void)?) in
            lock.lock(); defer { lock.unlock() }
            return (limiter.shouldSend(built), ingestKey, sink)
        }()
        guard allow else { return }
        if let testSink {
            testSink(built)
            return
        }
        Self.post(session, InternalReport.ingestURL, key, built)
    }

    // Fire-and-forget POST to /collect. text/plain matches the SDK's existing
    // /collect posts (the worker reads the raw body as JSON). Any error is
    // swallowed silently — never logged, to avoid recursion through the guard.
    private static func post(_ session: URLSession, _ url: String, _ key: String, _ ev: [String: Any]) {
        let body: [String: Any] = ["events": [ev]]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let u = URL(string: url) else { return }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.httpBody = data
        req.setValue(key, forHTTPHeaderField: "X-SDK-Key")
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        let request = req
        Task {
            _ = try? await session.seData(for: request)
        }
    }

    // MARK: Test seams

    /// Reset module state (context + rate limiter + key + sink) so a spec starts
    /// from a clean, inert channel. Test-only.
    func resetForTest() {
        lock.lock(); defer { lock.unlock() }
        side = nil
        sdkVersion = nil
        enabled = true
        limiter = SeeLimiter()
        ingestKey = InternalReport.placeholderKey
        sink = nil
    }

    /// Stand in a real-looking key so specs can exercise the (non-network) path
    /// without the deliberately inert placeholder blocking it. Test-only.
    func setIngestKeyForTest(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        ingestKey = key
    }

    /// Install a sink that receives the built event instead of the network POST.
    /// Test-only; pass nil to restore the network path.
    func setSinkForTest(_ sink: (@Sendable ([String: Any]) -> Void)?) {
        lock.lock(); defer { lock.unlock() }
        self.sink = sink
    }
}

/// Report an SDK-internal error to Shipeasy's own project via the process-global
/// channel. The `safeRun` catch calls this after logging locally. Fire-and-
/// forget; never throws. `label` doubles as the stable issue subject.
func reportInternalError(_ label: String, _ error: Error) {
    InternalReport.shared.report(label, error)
}
