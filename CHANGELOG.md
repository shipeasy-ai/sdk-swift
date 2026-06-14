# Changelog

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
