# Changelog

## Unreleased

- **`bucketBy` in experiment evaluation.** Experiments now honor an optional
  `bucketBy` attribute (e.g. `company_id`) so a whole org buckets together:
  when set and present on the user it drives the holdout, allocation, AND group
  hashes (a non-empty string is used as-is, a number is stringified); when
  absent it falls back to `user_id ?? anonymous_id`, matching the canonical
  TS/core implementation and gate bucketing.
- **Default values on `getFlag`/`getConfig`.** Added optional `default:`
  parameters: `getFlag(_:user:default:)` returns the default only when the flag
  cannot be evaluated (client not ready or flag not found) — never when it
  evaluates to `false`. `getConfig(_:default:)` returns the default when the key
  is absent. The original two-argument forms are unchanged.
- **Flag evaluation detail.** Added `FlagDetail { value, reason }`, the
  `FlagReason` enum (`OVERRIDE`, `CLIENT_NOT_READY`, `FLAG_NOT_FOUND`, `OFF`,
  `RULE_MATCH`, `DEFAULT`), and `getFlagDetail(_:user:)`. The reason is computed
  at the SDK boundary without changing the canonical eval; `getFlag` now
  delegates to it. The usage beacon is emitted exactly once per non-override
  evaluation.
- **Change listeners.** `onChange(_:)` registers a `@Sendable` listener fired
  after a fetch applies new data (HTTP 200, not 304) and returns an unsubscribe
  closure. Listeners never fire in local (test/snapshot) mode.
- **Offline snapshot data source.** `Client.fromFile(_:)` and
  `Client.fromSnapshot(flags:experiments:)` build a no-network, immediately-ready
  client from JSON blobs (telemetry off, `initialize`/`initializeOnce`/`track`
  no-op). Evaluations run the real eval against the snapshot; overrides apply on
  top.
- **Local-override test utility.** `Client.forTesting()` builds a no-network,
  no-key, immediately-ready client (`initialize()`/`initializeOnce()` and
  `track(...)` are no-ops, telemetry disabled). New override setters —
  `overrideFlag(_:_:)`, `overrideConfig(_:_:)`,
  `overrideExperiment(_:group:params:)`, and `clearOverrides()` — let tests seed
  deterministic values; an override always wins over live evaluation. The
  setters also work on a normal network-backed client. See the README "Testing"
  section.

## 0.3.0

- **Anonymous bucketing (`__se_anon_id`).** Added `AnonId` — Foundation-only
  primitives (`mint`, `isValid`, `read(cookieHeader:)`, `resolve(cookieHeader:)`,
  `setCookieHeader(_:secure:)`) for the shared `__se_anon_id` first-party cookie.
  This SDK is framework-agnostic (Apple platforms + server-side Swift), so it
  ships helpers rather than a middleware. Implements the cross-SDK contract in
  `18-identity-bucketing.md`.
- **Eval fix (no-unit gate rule).** A request with no `user_id`/`anonymous_id`
  now resolves a fully-rolled (100%) gate as **on** instead of always off; a
  fractional gate is still off until a stable unit exists. Matches the
  TypeScript reference SDK. Targeting rules are still evaluated first.

## 0.2.0

- Per-evaluation usage telemetry (fire-and-forget, on by default).

## 0.1.0

- Initial release: feature flags, configs, experiments, metric tracking.
