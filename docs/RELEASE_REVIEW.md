# Dayloft 4.2.9 release review

The source is public. No installer has been published. This review found and fixed release-relevant defects; it does not establish that the app is bug-free or ready for public binary distribution.

## Findings fixed

| Priority | Problem | Result and verification |
| --- | --- | --- |
| P1 | Rejected end-date changes fell through after unlocking, allowing a rejected shortening/oversized extension and a second reply/unlock. | Invalid dates return immediately. A persistence failure restores the previous end and session ledger. Regression tests assert one reply, unchanged end, and a released lock. |
| P1 | A hosts-file watcher could call integrity repair during an intentional break and reinstall rules early. | Integrity repair skips paused, expired, and idle sessions. Periodic checkup exclusively owns resume/expiry. Tests trap any attempted rule inspection/installation in these states. |
| P1 | A new block installed persistent rules before its recovery end time was saved. | The active end time is saved first. A simulated disk failure aborts before network operations. Failed partial installations retain cleanup state. |
| P1 | Cleanup could treat removal of the PF configuration marker as successful unloading, discard state, and stop retrying even when pfctl failed. | Normal and recovery cleanup check command results. Failed expiry remains visible with its original list and an active retry timer; backup hosts data is retained until successful cleanup. Tests exercise failure followed by successful retry. |
| P1 | Missing/stale PF-token recovery could disable the entire system firewall. | Recovery reloads configuration with Dayloft's anchor removed; it never uses the global disable flag. Unreadable/unwritable PF configuration returns an error. Live coexistence with other PF users still needs verification. |
| P1 | A failed recurring start consumed its occurrence, skipping the remaining window. | Only successful starts consume occurrences; transient failures remain retryable and successful retry clears the error. Regression tests cover failure, retry, and deduplication. |
| P2 | Accepted XPC authorization data was included in logs. | The log records only the command name. |
| P2 | CI covered the current Debug architecture but could miss Release/Intel problems and mismatched app/helper versions. | CI builds both Release architectures and verifies every bundled Mach-O binary plus app/helper/runtime version agreement. |
| P2 | Mutable action tags, overlapping release runs, and dispatches outside main weakened release reproducibility and credential boundaries. | Actions are pinned to verified commits; checkout credentials are not persisted. Releases are serialized, the workflow permits main only, and the actual GitHub release environment enforces a main-only branch policy. Built artifacts are retained before attempting draft creation. Raw update-key and keychain files are ignored and rejected by the source audit. |
| P1 | Mode and schedule copies could restore an old three-site list over the user's five-site configuration. | One authoritative website profile now owns manual and scheduled starts. Active additions update it atomically, and stale schedule copies are migration-only fallbacks. |
| P1 | Safari could keep X working through an established WebKit connection and cached page even after correct hosts rules were installed. | The helper records the authenticated user, resets that user's WebKit network/page processes at rule transitions, blocks X/Twitter short-link and media hosts, and rebuilds active rules immediately after a helper upgrade. Live checks show the X family resolving only to `0.0.0.0`/`::`, no WebKit connection to X's public addresses, failed X/media requests, and a successful unrelated Google request. |
| P1 | Safari launched after a scheduled start could restore Instagram through a fresh WebKit process that the start-time reset never saw. | During strict denylist sessions, the daemon detects a previously unseen WebKit networking process, resets it once, and trusts the clean replacement. Tests cover late launch and prove the replacement does not enter a reset loop. |
| P1 | Browser state could remain blocked after a break or natural cleanup. | Break and removal paths flush DNS and restart the same user's WebKit services after rules are removed. Tests verify the reset occurs only when enforcement actually changes. |

The shared daemon lock also now uses thread-safe initialization, start timers run after unlocking, and mutation methods return persistence failures instead of silently reporting success.

## Validation

- 75 local XCTest tests pass, including the original three tests unchanged byte-for-byte.
- Universal Release compilation passes; all nine bundled executable/framework binaries contain arm64 and x86_64.
- Workflow syntax passes actionlint; shell syntax and the public-source audit pass.
- Sparkle signature generation/verification rejects tampered payloads and mismatched keys. The previous feed-generation smoke test remains documented in VALIDATION.md; this review does not replace a real installed-app update test.
- The [latest published pipeline run](https://github.com/hatish2001/dayloft/actions/runs/34767439716) passed all checks for 4.2.6. The exact release commit must receive the same successful public run before release packaging begins.

## Remaining launch gates

- Configure Developer ID signing and notarization credentials. The Sparkle key pair is configured and verified; the Developer ID certificate, certificate password, signing identity, notarization Apple ID, and app-specific password are absent, so the release job cannot produce a notarized package.
- On a dedicated test Mac, verify a full break/resume and natural expiry, reboot/sleep/wake, and app-closed recurring starts.
- Verify cleanup with another PF-using application present, and run on Intel hardware.
- Install a notarized download on a clean Mac; exercise the full signed update, relaunch, preserved schedules/history, helper upgrade, and rejected-tampered-download paths.

Until these pass, ship source and development builds only. The reviewed workflow creates a draft, so finishing a workflow does not announce or publish a release automatically.
