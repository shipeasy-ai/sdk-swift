# Changelog

## 0.6.0

- **`see()` structured error reporting.** New fluent grammar for reporting
  handled errors with their *product consequence*, mirroring `@shipeasy/sdk`
  and the other server SDKs. Instance methods on `Client`
  (`see(_:)`, `seeViolation(_:)`, `controlFlowException(_:)`) and package-level
  functions (`see`, `seeViolation`, `controlFlowException`) backed by a default
  client registered when a `Client` is constructed (last wins; override with
  `setDefaultClient(_:)`). A global `see()` before any client logs a warning and
  no-ops — it never crashes. The chain reads synchronously —
  `client.see(error).causesThe("checkout").to("use cached prices")` — because
  `see`/`seeViolation`/`controlFlowException` are `nonisolated` and return a
  plain (non-actor) `SeeChain`; `to(_:)` is the terminal that builds the event
  and fire-and-forgets the POST to `/collect` via a detached `Task` onto the
  actor. `causesThe(_:)` and `extras(_:)` are chainable setters callable in any
  order before `to(_:)`; `to(_:)` is idempotent and a chain that never calls
  `to(_:)` sends nothing. Events carry `type:"error"`, `kind`
  (`caught`/`violation`), `error_type`, `message`, optional `stack` (current
  call stack, best-effort — Swift has no per-throw stack), `subject`, `outcome`,
  sanitized `extras`, `side:"server"`, `env`, the new `sdk_version`, and `ts`.
  Extras are sanitized (≤20 keys, 200-char string values, only
  String/number/Bool, nil/NSNull dropped) and the client's private attributes
  are stripped. A per-process spam limiter (30s dedup, 25-send cap) bounds
  network chatter. `controlFlowException(_:).because(_:)` marks an exception as
  expected and reports **nothing** (its `.extras()` are local-debug only). No-op
  in local/`forTesting()` mode, like `track()`.

## Unreleased

- **Private attributes.** New `privateAttributes: [String]` client option. The
  server evaluates locally, so private attrs never leave for evaluation; the
  only egress is `/collect`, where the listed keys are now stripped from every
  outbound `track()` payload. Matches the TS reference SDK (LD/Statsig parity).
- **Manual server exposure.** Added `logExposure(userId:experiment:)`. The
  server never auto-logs; this re-evaluates the experiment for the user and, if
  enrolled, POSTs a single `{type:"exposure", experiment, group, user_id, ts}`
  to `/collect`. No-op in local mode or when the user isn't enrolled.
- **Sticky bucketing.** New `StickyBucketStore` protocol
  (`get(_:) -> [String: StickyEntry]?`, `set(_:_:_:)`), `StickyEntry`
  (`group` + `salt8`), and a built-in `InMemoryStickyBucketStore`. Supply a
  store via the `Client(... stickyStore:)` initializer or
  `Client.fromSnapshot(... stickyStore:)`. When present, experiment eval — after
  the holdout, before allocation — honors a stored assignment whose `salt8`
  still matches the experiment salt prefix (skipping the allocation gate and
  returning the stored group without re-picking), and persists every fresh pick.
  A salt-prefix mismatch or a vanished group re-buckets and overwrites the
  entry. Absent ⇒ deterministic (fully backward compatible). Matches doc 20 §2
  and the TS reference SDK.
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
