# Changelog

## 0.14.0 — 2026-07-08

### Added

- **Native mobile client (`ShipeasyClient`).** A first-class **client-key** SDK
  for shipped iOS / macOS / tvOS / watchOS apps, alongside the existing
  server-key `configure()` / `Client(user)` surface. It holds a **public client
  key** (safe to embed in an app binary — a server key never is), evaluates a
  single device user server-side over `POST /sdk/evaluate`, and caches the
  returned assignments for cheap local reads. Front door:

  ```swift
  configureClient(clientKey: "pk_live_…")            // once, at app launch
  await shipeasyClient()?.identify(["user_id": "u_123"])
  let on = await shipeasyClient()?.getFlag("new_checkout") ?? false
  ```

  `ShipeasyClient` exposes `identify(_:)` / `reset()` / `refreshAssignments()`,
  the reads `getFlag` / `getConfig` / `getExperiment` / `getKillswitch`, and
  `track(_:properties:)` / `logExposure(_:)`.

- **Persistent device `anonymous_id` (`AnonymousStore`).** The client resolves a
  stable anonymous bucketing id once and **persists it across app launches**, so
  a logged-out visitor buckets identically on every cold start (without this a
  fresh UUID per launch silently re-buckets every fractional rollout and
  experiment). Backed by `UserDefaults` by default; supply your own
  `AnonymousStore` to use the Keychain, an app-group container, or an in-memory
  map. Sticky-bucketing state returned by the edge is persisted and echoed back
  on each evaluation.

## 0.13.0 — 2026-07-08

### Added

- **SDK self-monitoring for internal errors.** When one of the SDK's last-resort
  guards (`safeRun`, wrapping the runtime reads `getFlag`/`getFlagDetail`/
  `getConfig`/`getKillswitch`/`getExperiment`) swallows an internal failure — a
  bug on Shipeasy's side, not the caller's — it now also reports that error to
  Shipeasy's own project so we can track and fix SDK bugs across every app the
  SDK runs in. This is a dedicated, baked-in destination (a public client-key
  ingest credential), entirely separate from your `see()` reporting: internal
  errors never land in your project or Errors tab. The report carries only the
  error itself plus a stable, deduped consequence (subject = the guarded
  operation, e.g. `flags.getDetail`) and is fire-and-forget — it can never slow
  down or break a read. On by default; opt out with
  `disableInternalErrorReporting: true` on `configure(apiKey:)`.

## 0.12.1 — 2026-07-07

### Fixed

- **Default API host now resolves.** The default `baseURL` pointed at the
  unregistered domain `https://edge.shipeasy.dev`, so every `configure()` fetch
  and every `getFlag`/`getConfig`/`getExperiment`/`track`/`see()` call failed
  with a DNS error unless `baseURL` was set explicitly. Corrected to the real
  edge origin `https://api.shipeasy.ai` — the host the docs, CLI, and curl
  snippets already use. Explicit `baseURL` overrides are unaffected.

## 0.12.0 — 2026-07-07

Fail-safe runtime reads + a leveled `logLevel` option (uniform cross-SDK
hardening, mirroring `@shipeasy/sdk`).

### Added

- **`LogLevel`** (`silent < error < warn < info < debug`) and a `logLevel:`
  parameter on `configure(...)` and `Engine.init(...)` (default `.warn`). It sets
  a process-global leveled logger that gates before writing to stderr; `.silent`
  mutes the SDK's own diagnostics entirely. Logging is best-effort and never
  throws or traps into caller code.

### Changed

- The two `see()`-before-a-client stderr writes now go through the leveled
  logger, and the previously-silent fire-and-forget dispatch failures in
  `track` / `logExposure` / `see()` are surfaced at `warn`.

### Fixed

- Hardened runtime reads against trapping on adversarial input: removed the
  force-unwrap in `AnonId.resolve` (`raw!` after `isValid`) and the
  `override!` force-unwrap in the SSR `cdnBase` helper. The bound `Client` reads
  (`getFlag` / `getFlagDetail` / `getConfig` / `getKillswitch` / `getExperiment`)
  and `track` / `logExposure` / `see()` remain `async`, non-throwing, and return
  safe defaults for any malformed rules blob. Setup/lifecycle throwing behaviour
  (`Client(_:)`, `configureForOffline`, `Engine.fromFile`, `initialize()`) is
  unchanged.

## 0.11.1

Linux build support (the SDK now compiles + tests on Linux, not just Apple).

### Fixed

- Replace the Apple-only `CryptoKit` SHA-256 with a dependency-free pure-Swift
  implementation (byte-identical output) so the SDK builds on Linux.
- Guard `URLSession`/`URLRequest` behind `#if canImport(FoundationNetworking)`
  and add a cross-platform `URLSession.data(for:)` (Linux swift-corelibs lacks the
  async form); guard the CoreFoundation `CFBooleanGetTypeID` extras check behind
  `#if canImport(Darwin)`.
- `ShipeasyAdmin`: fix the generated client's Linux build (MobileCoreServices /
  FoundationNetworking / CoreServices MIME guards).

## 0.11.0

Ship the generated OpenAPI **admin** client alongside the flags SDK.

### Added

- **`ShipeasyAdmin`** — a new SwiftPM library product exposing a generated
  (OpenAPI, URLSession, async/await) client for the Shipeasy **admin** API
  (flags / experiments / configs / kill switches / metrics / errors / ops — full
  CRUD + reads). Import with `import ShipeasyAdmin`; it is a separate module with
  zero external dependencies, so existing `import Shipeasy` (flags) consumers are
  unaffected unless they opt in. Generated from the admin OpenAPI spec via
  `openapi-generator` (see `apps/mobile` → `pnpm gen:clients swift`).

## 0.10.0

The uniform SDK DX standard (experiment-platform doc 23). The documented surface
is now exactly `configure()` (+ the test/offline siblings) and the bound
`try Client(user)`; the `Engine` actor stays public but undocumented.

### Added

- **`configureForTesting(...)`** (`async`) — no api key, zero network; seeds
  flags/configs/experiments overrides and registers the global engine so the bound
  `Client(user)` reads them. **Replaces** prior config (unlike `configure`'s
  first-config-wins) so a test suite can reconfigure between cases.
- **`configureForOffline(snapshot:path:...)`** (`async throws`) — evaluates the
  **real** rules from an in-memory snapshot or a JSON file, with overrides layered
  on top; also replaces prior config.
- **`configure(..., poll:)`** — `poll: true` starts the background poll internally
  (you never call `initialize()` yourself); `init` (default `true`) is the one-shot
  fetch.
- **Package-level helpers** so the docs never name the `Engine`: `overrideFlag`,
  `overrideConfig`, `overrideExperiment`, `clearOverrides`, `onChange`,
  `bootstrapScriptTag`, `i18nScriptTag` (all `async`) — delegating to the
  configured global engine.
- **`shipeasy-skill` executable** (`swift run shipeasy-skill install` / `print`) —
  the opt-in installer that copies the bundled agent skill into a consumer's
  project; the skill is a SwiftPM resource kept in sync by `gen-readme`.

### Changed

- `README.md` is now **generated** from `docs/` by the `gen-readme` executable
  (`swift run gen-readme`, which also syncs the embedded skill); CI enforces it.
  The docs were rewritten Engine-free around `configure()` + `Client`, with new
  `metrics/track` + `ops/see` snippet groups and specific placeholders.

## 0.9.0

- Add `track()`/`logExposure()` to the bound `Client` (experiments are now
  end-to-end Client-only; the Engine forms remain for advanced use).
  - `Client.track(_ event: String, properties: [String: Any] = [:])` records a
    conversion for the bound user — the unit is derived from the bound attribute
    map (`user_id`, else `anonymous_id`), so no id argument is needed. A no-op
    when the bound user has neither id.
  - `Client.logExposure(_ experiment: String)` emits an exposure for the bound
    user (re-evaluates and only emits when enrolled).
  - The unit-explicit `Engine.track(userId:eventName:properties:)` and
    `Engine.logExposure(userId:experiment:)` forms are unchanged.

## 0.8.0

- **BREAKING — `configure(...)` + user-bound `Client(user)`.** The two-part
  front door shared across every Shipeasy SDK (see
  `.agents/sdk-bound-client-spec.md`).
  - The heavyweight type that owns the API key, HTTP, the blob cache and the
    poll timer was **renamed `Client` → `Engine`** (still an `actor`; its full
    surface is unchanged — `forTesting()`, `fromSnapshot(...)`, `fromFile(_:)`,
    `override*`, `initialize()`/`initializeOnce()`, `track`, `logExposure`,
    `evaluate`, `bootstrapScriptTag`/`i18nScriptTag`, sticky bucketing, private
    attributes, and the `see()` instance methods). The `see()` default-client
    wiring now hooks off `Engine` construction / `configure(...)`.
  - The name **`Client` is now the lightweight, user-bound handle.** Configure
    once: `configure(apiKey:attributes:)` builds the single package-global
    `Engine`, stores the optional `attributes` transform, and fire-and-forgets
    the engine's one-shot fetch (pass `init: false` to skip it). Then construct
    one `Client` per user/request: `try Client(user)`. The `attributes`
    transform runs **once in the constructor** and the resulting attribute map
    is bound, so every method takes **NO user argument**:
    `await Client(["user_id": "u1"]).getFlag("new_checkout")`.
  - New public symbols: `func configure(apiKey:attributes:…) -> Engine`,
    `struct Client`, `typealias AttributesFn = (Any) -> [String: Any]`,
    `struct NotConfiguredError`, `func globalEngine() -> Engine?`,
    `func resetGlobalConfig()`, and `Engine.getKillswitch(_:switchKey:)`.
  - `Client` methods are `async` (they forward to the `Engine` actor):
    `getFlag(_:)`, `getFlag(_:default:)`, `getFlagDetail(_:)`, `getConfig(_:)`,
    `getConfig(_:default:)`, `getExperiment(_:defaultParams:)`,
    `getKillswitch(_:switchKey:)`. Construction is synchronous and **throws
    `NotConfiguredError`** when `configure(...)` was not called — a loud, local
    failure.
  - `configure(...)` is first-config-wins (idempotent), matching the
    default-engine `see()` idempotency.
  - Also aligns `SDK_VERSION` (was lagging at `0.6.0`) with the `VERSION` file.
  - **Migration:** rename your existing `Client(apiKey:)` heavyweight usage to
    `Engine(apiKey:)` (or adopt `configure(apiKey:)`), and rename
    `Client.forTesting()` / `Client.fromSnapshot(...)` / `Client.fromFile(...)`
    to `Engine.…`. The new `Client(user)` is the per-request handle.

## 0.7.0

- **SSR bootstrap script-tag helpers.** New `Client.evaluate(user)`
  batch-evaluate (every gate/config/experiment → a `["flags", "configs",
  "experiments", "killswitches"]` payload) plus `bootstrapScriptTag` and
  `i18nScriptTag`, which emit the cross-platform declarative `<script>` tags
  carrying the SSR payload as `data-*` attributes. The static `se-bootstrap.js`
  loader hydrates `window.__SE_BOOTSTRAP` and writes the `__se_anon_id` cookie so
  the browser buckets identically to the server. **No SDK key is embedded** in
  the bootstrap tag.

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
