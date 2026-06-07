import Foundation
import CryptoKit

/// Per-evaluation usage telemetry. Fires one fire-and-forget HTTP beacon per
/// evaluation so usage is counted by Cloudflare's native per-path analytics.
/// Mirrors the contract in the TypeScript reference SDK and
/// experiment-platform/15-usage-metering.md. The path carries sha256(apiKey) --
/// never the raw key -- plus side/env, then feature/resource. The 2s dedup
/// window bounds volume under loops.
final class Telemetry: @unchecked Sendable {
    static let defaultURL = "https://t.shipeasy.ai"

    private let disabled: Bool
    private let dedupeMs: Double = 2000
    private let prefix: String
    private let session: URLSession
    // Test seam: when set, receives the beacon URL instead of the real HTTP send.
    private let sender: (@Sendable (String) -> Void)?
    private let lock = NSLock()
    private var last: [String: Double] = [:]

    init(
        endpoint: String,
        sdkKey: String,
        side: String = "server",
        env: String = "prod",
        disabled: Bool = false,
        session: URLSession = .shared,
        sender: (@Sendable (String) -> Void)? = nil
    ) {
        let ep = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        self.disabled = disabled || sdkKey.isEmpty || ep.isEmpty
        self.session = session
        self.sender = sender
        self.prefix = self.disabled
            ? ""
            : "\(ep)/t/\(Telemetry.sha256Hex(sdkKey))/\(side)/\(Telemetry.enc(env))"
    }

    /// Best-effort usage beacon for one evaluation. Never blocks the caller.
    func emit(_ feature: String, _ resource: String) {
        if disabled { return }
        if dedupeMs > 0 {
            let key = "\(feature)/\(resource)"
            let now = Date().timeIntervalSince1970 * 1000
            lock.lock()
            if let prev = last[key], now - prev < dedupeMs {
                lock.unlock()
                return
            }
            last[key] = now
            lock.unlock()
        }
        let urlString = "\(prefix)/\(feature)/\(Telemetry.enc(resource))"
        if let sender = sender {
            sender(urlString)
            return
        }
        guard let url = URL(string: urlString) else { return }
        let session = self.session
        Task {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            _ = try? await session.data(for: req)
        }
    }

    // encodeURIComponent-equivalent: %20 for space, %2F for slash.
    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
