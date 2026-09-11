# Architecture

`SelfControl/Dayloft` contains the SwiftUI app shell, model, pure value types, original icon, and narrow Objective-C bridge. The product is `Dayloft.app`; the inherited Xcode app target and Swift module retain the internal name `SelfControl`.

The existing Objective-C engine remains in `Common`, `Daemon`, and `Block Management`. AppController continues to own the existing start-block path and macOS authorization. The new UI never edits firewall files itself.

The recurring-schedule bridge installs/connects to the privileged helper, then submits an authenticated XPC request. The helper validates the payload, persists it, and acknowledges success. UI changes are committed after that reply. Inactive, never-enabled drafts can be saved locally without authorization.

The daemon evaluates enabled routines against the current local calendar. An overnight interval belongs to its starting weekday. Start is inclusive, end exclusive. Wake does not add time to a missed routine. A running manual or scheduled block is never shortened. Occurrence IDs avoid restarting the same window; markers are written after a start attempt, so a crash before rule installation leaves the window retryable.

Focus history stores absolute session and break intervals after a block starts. Daily totals clip at midnight and at now, excluding breaks. Only the current user’s history contributes to the displayed totals. History is bounded to 2,000 sessions. Screen Time integration is not implemented; Home instead displays real seven-day focus activity. Session intervals are merged so duplicate or overlapping records cannot inflate totals, and overlapping breaks are subtracted once. The weekly indicators and streak share a one-minute-per-local-day qualification rule. Yesterday has a grace period until today ends. Missing user ownership and invalid/future records do not contribute.

Runtime isolation:

- App: `org.dayloft.Dayloft`
- Helper / Mach service: `org.dayloft.focusd`
- CLI: `org.dayloft.cli`
- PF anchor: `org.dayloft`
- Hosts markers: `BEGIN DAYLOFT BLOCK` / `END DAYLOFT BLOCK`
- Protected settings: existing root-owned settings mechanism with a Dayloft-specific filename seed

The inherited recovery helper and support views are retained because the engine still references them. The standalone legacy recovery application, old marketing files, outdated updater framework, telemetry SDK, nested Git metadata, and generated application copies were removed from the public source tree. The new everyday flow uses native sheets for websites, schedules, breaks, and extending a session.

A first launch copies selected website preferences from SelfControl if present. It does not adopt, cancel, or remove another product’s block. Avoid running multiple firewall-based blockers at once; coexistence still needs explicit integration testing.

The privileged settings writer rejects distributed setting-change notifications. Readers use notifications only as hints to reload the root-owned file; payloads are never applied as authoritative changes. Test builds define `TESTING=1` in both configurations and use memory-only stores with disk access, timers, and distributed observation/broadcast disabled. The original test source is unchanged. Additional regression tests intercept notification delivery and trap protected-file access so a regression cannot reach a running app.

## Updates

Dayloft uses pinned Sparkle 2.9.6 for signed updates from the dedicated GitHub repository. Release builds embed an Ed25519 public key; a missing key disables updates in development builds. Checks defer during active focus or pending changes, and installation requires user interaction. Scheduled discoveries appear in the sidebar. Updates do not enable system-profile reporting. See RELEASING.md for signing and feed publication.
