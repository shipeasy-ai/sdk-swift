# CLAUDE.md — Shipeasy (Swift)

Guidance for AI agents (and humans) working in this repository.

## What this is

The **native client** Swift SDK for [Shipeasy](https://shipeasy.ai) — for shipped
**iOS / macOS / tvOS / watchOS** apps only. Feature flags, dynamic configs, kill
switches, A/B experiments, metric tracking, and `see()` error reporting, using the
**public client key** (`pk_…`, safe to embed). `ShipeasyClient` evaluates the
device user server-side over `POST /sdk/evaluate`, caches the assignments for cheap
local reads, and **persists the device `anonymous_id` across launches**. There is
**no server surface** — a backend uses a server SDK (TS / Python / Go / …). Library
source under `Sources/Shipeasy/`; tests under `Tests/ShipeasyTests/` (XCTest).
`ShipeasyClient` is a Swift `actor`, so reads are `async`.

There is **no OpenFeature provider** in Swift (the Swift OpenFeature ecosystem is
immature) — `getFlag` is the interop surface. There is **no i18n** in the native
client (i18n was a browser/SSR feature; a native app localizes with the platform's
own tooling).

## The documented public surface (this is a contract)

Users are taught exactly **two** things, and the docs must never drift from them:

1. **`configureClient(clientKey:)`** — call once at app launch (idempotent,
   first-config-wins). Returns the process-global `ShipeasyClient`; fetch it later
   with `shipeasyClient()`.
2. **`ShipeasyClient`** — the actor for *everything*: `identify(_:)` / `reset()` /
   `refreshAssignments()`, the reads `getFlag` / `getConfig` / `getKillswitch`,
   universe assignment via `universe(_:).assign()`, and `track(_:properties:)`. All `async`.

Plus the package-level `see()` / `seeViolation()` / `controlFlowException()` error
reporting (dispatched by the configured client), the `AnonymousStore` protocol +
`UserDefaultsAnonymousStore` (pluggable persistence), and `resetClientConfig()`
(tests only).

**Never reintroduce a server surface.** No `configure(apiKey:)`, `Client(user)`,
`Engine`, local rule evaluation, SSR/bootstrap tags, or server framework wiring —
those were removed at 1.0.0. New capability gets a `ShipeasyClient` method or a
package-level client affordance, then is documented through it.

## HARD RULE: change the SDK → update the docs in the SAME change

`docs/` is the published, user-facing source of truth (rendered at
<https://shipeasy-ai.github.io/sdk-swift/> and ingested by the Shipeasy CLI/MCP
`docs` tooling and the central docs portal). Any change to the SDK's **public API
or behaviour** updates the relevant `docs/pages/*.md`, the matching
`docs/snippets/**`, and `docs/skill/SKILL.md` in the same commit; new
page/snippet/placeholder → also `docs/manifest.json`. See
[`docs/CLAUDE.md`](docs/CLAUDE.md).

**`README.md` is generated — do not hand-edit it.** It is assembled from the docs
by the `gen-readme` executable (which also re-syncs the embedded
`Sources/shipeasy-skill/SKILL.md`). After editing `docs/`, run:

```bash
swift run gen-readme
```

CI (`.github/workflows/tests.yml`) re-runs it and fails if `README.md` or the
embedded skill drifts.

## Versioning & release

- Bump **both** the `VERSION` file and `SDK_VERSION` in `Sources/Shipeasy/See.swift`
  (kept in sync — `SDK_VERSION` is sent on every `see()` event), and add a
  `CHANGELOG.md` entry.
- Publishing is **push-to-`main`**: the publish workflow self-tags `v$VERSION` and
  SwiftPM serves the tag. A version-bumped push to `main` IS the release.

## Checks before you commit

- `swift build` and `swift test` (the suite is hermetic — no network). `swift test`
  needs XCTest (full Xcode on macOS, or the Linux toolchain); CI runs both macOS +
  Linux. New public behaviour ships with a test.
- Docs updated per the hard rule; `docs/manifest.json` stays valid JSON and every
  path it lists exists.
- `swift run gen-readme` and commit the result (CI checks it's in sync).
