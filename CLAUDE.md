# CLAUDE.md — Shipeasy (Swift)

Guidance for AI agents (and humans) working in this repository.

## What this is

The **server/edge** Swift SDK for [Shipeasy](https://shipeasy.ai): feature flags,
dynamic configs, kill switches, A/B experiments, metric tracking, `see()` error
reporting, and SSR/i18n helpers. Server-key only; never embed it in a shipped app
bundle. Library source under `Sources/Shipeasy/`; tests under
`Tests/ShipeasyTests/` (XCTest). `Engine` is a Swift `actor`, so reads are `async`.

There is **no OpenFeature provider** in Swift (the Swift OpenFeature ecosystem is
immature) — `getFlag` / `getFlagDetail` are the interop surface.

## The documented public surface (this is a contract)

Users are taught exactly **two** things, and the docs must never drift from them:

1. **`configure()`** — and its siblings `configureForTesting()` /
   `configureForOffline()` — for setup.
2. **`try Client(user)`** — the cheap, user-bound handle for *all* reads
   (`getFlag` / `getFlagDetail` / `getConfig` / `getKillswitch` / `getExperiment`
   / `logExposure` / `track`).

Plus the package-level helpers that let users avoid the heavyweight object (all
`async`): `overrideFlag` / `overrideConfig` / `overrideExperiment` /
`clearOverrides`, `onChange`, `bootstrapScriptTag` / `i18nScriptTag`, and the
`see()` family.

**The `Engine` actor is an internal detail. Do NOT document it.** It stays public
for advanced/back-compat use, but no page, snippet, skill, or the README should
tell a user to construct or call an `Engine`. New user-facing capability should
get a `configure`-style or package-level affordance, then be documented through it.

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
