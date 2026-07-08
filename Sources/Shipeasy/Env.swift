import Foundation

// Native runtime-environment detection.
//
// Used ONLY to pick the DEFAULT for outbound egress when the caller does not set
// it explicitly:
//   - is the client allowed to make network requests at all (`isNetworkEnabled`)?
//   - is usage telemetry / logging allowed (`disableTelemetry`)?
//
// Both default to ON in production and OFF everywhere else, so a local/dev/CI run
// of an app that embeds the SDK never phones home unless it explicitly opts in.
//
// Precedence for the production decision (mirrors the TypeScript reference SDK's
// `src/env.ts`, adapted to Swift):
//   1. A native runtime env var — `SHIPEASY_ENV`, then `APP_ENV`, then `ENV`. A
//      value of "production"/"prod" (case-insensitive) ⇒ prod; any other present
//      value ("development"/"staging"/"test"/…) ⇒ not prod.
//   2. When NO native env var is set (the common case on iOS / macOS apps, which
//      rarely export a shell env), fall back to the `#if DEBUG` compile flag: a
//      DEBUG build ⇒ NOT production, a release build ⇒ production. This keeps a
//      shipped App Store / release build "on" while a debug run stays quiet.
//   3. If the compile flag is somehow inconclusive, fall back to the SDK's own
//      configured `env` option (dev/staging/prod), which itself defaults to
//      "prod". The env option is always present, so the decision is always
//      inferable — the SDK never has to make a field required.

/// True when the host runtime looks like a production deployment. `configuredEnv`
/// is the SDK's own `env` option (dev/staging/prod); it is consulted only when no
/// native runtime env var is set and the compile flag is inconclusive.
func isProductionEnv(_ configuredEnv: String? = nil) -> Bool {
    if let native = readNativeEnv() {
        return native == "production" || native == "prod"
    }
    // No native env var (typical for a shipped app): use the build configuration.
    #if DEBUG
    return false
    #else
    // Release build with no native signal ⇒ production, but still let an explicit
    // non-prod `env` option quiet the SDK if the caller set one.
    return (configuredEnv ?? "prod").lowercased() == "prod"
    #endif
}

/// Read the native runtime environment string (lowercased, trimmed), or `nil`
/// when none of the recognised vars are set. Checked in precedence order:
/// `SHIPEASY_ENV`, `APP_ENV`, `ENV`.
private func readNativeEnv() -> String? {
    let env = ProcessInfo.processInfo.environment
    for name in ["SHIPEASY_ENV", "APP_ENV", "ENV"] {
        if let raw = env[name] {
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !v.isEmpty { return v }
        }
    }
    return nil
}
