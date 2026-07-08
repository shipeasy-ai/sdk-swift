import Foundation

/// Anonymous bucketing identity — the cross-SDK `__se_anon_id` cookie.
///
/// Gates and experiments bucket a unit with `murmur3(salt:unit)`. For a
/// logged-out visitor the unit is a stable anonymous id carried in a single
/// first-party cookie that EVERY Shipeasy SDK (server + browser) reads and
/// writes, so a server render and the browser bucket a fractional rollout
/// identically. The cookie name and format are frozen across every language;
/// see `experiment-platform/18-identity-bucketing.md`.
///
/// This SDK is framework-agnostic (it runs on Apple platforms and server-side
/// Swift alike), so it ships the cookie *primitives* rather than a middleware.
/// In a server handler (Vapor, Hummingbird, …), resolve the id off the request
/// `Cookie` header and echo `setCookieHeader` back on the response, then pass
/// the id as the bucketing unit:
///
/// ```swift
/// let resolved = AnonId.resolve(cookieHeader: req.headers["cookie"].first)
/// let on = await client.getFlag("new_checkout", user: ["anonymous_id": resolved.id])
/// if resolved.minted {
///     res.headers.add(name: "set-cookie", value: AnonId.setCookieHeader(resolved.id, secure: true))
/// }
/// ```
public enum AnonId {
    /// The first-party cookie carrying the stable anonymous bucketing unit.
    public static let cookie = "__se_anon_id"
    /// One year, in seconds.
    public static let maxAge = 31_536_000

    /// A fresh opaque bucketing id (UUIDv4).
    public static func mint() -> String {
        UUID().uuidString.lowercased()
    }

    /// The cookie value is client-controllable and feeds bucketing, so a
    /// tampered value is treated as absent. UUIDs satisfy this charset.
    public static func isValid(_ value: String?) -> Bool {
        guard let value, !value.isEmpty, value.count <= 64 else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    /// Read the `__se_anon_id` value out of a raw `Cookie` request-header
    /// string (e.g. `"a=1; __se_anon_id=xyz; b=2"`), or `nil` if absent.
    public static func read(cookieHeader: String?) -> String? {
        guard let cookieHeader else { return nil }
        for pair in cookieHeader.split(separator: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq])
            if key == cookie {
                return String(trimmed[trimmed.index(after: eq)...])
            }
        }
        return nil
    }

    public struct Resolved {
        /// The stable bucketing id for this request (existing cookie or minted).
        public let id: String
        /// True when there was no valid cookie and `id` was freshly minted
        /// (persist it with `setCookieHeader`).
        public let minted: Bool
    }

    /// Resolve the request's bucketing id — the existing valid cookie, or a
    /// freshly minted one.
    public static func resolve(cookieHeader: String?) -> Resolved {
        let raw = read(cookieHeader: cookieHeader)
        if isValid(raw), let raw {
            return Resolved(id: raw, minted: false)
        }
        return Resolved(id: mint(), minted: true)
    }

    /// Format a `Set-Cookie` header value per the cross-SDK contract. Non-HTTP
    /// only by design — the browser SDK reads it via `document.cookie` to bucket
    /// identically to the server. Pass `secure: true` on HTTPS.
    public static func setCookieHeader(_ id: String, secure: Bool) -> String {
        var parts = ["\(cookie)=\(id)", "Path=/", "Max-Age=\(maxAge)", "SameSite=Lax"]
        if secure { parts.append("Secure") }
        return parts.joined(separator: "; ")
    }
}
