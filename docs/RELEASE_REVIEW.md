# Dayloft 4.2.1 release review

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

The shared daemon lock also now uses thread-safe initialization, start timers run after unlocking, and mutation methods return persistence failures instead of silently reporting success.

## Validation

- 51 local XCTest tests pass, including the original three tests unchanged byte-for-byte.
- Universal Release compilation passes; all nine bundled executable/framework binaries contain arm64 and x86_64.
- Workflow syntax passes actionlint; shell syntax and the public-source audit pass.
- Sparkle signature generation/verification rejects tampered payloads and mismatched keys. The previous feed-generation smoke test remains documented in VALIDATION.md; this review does not replace a real installed-app update test.
- The [public review-fix CI run](https://github.com/hatish2001/dayloft/actions/runs/34670738757) passed all tests, both Release architectures, signature checks, and the source audit. Its Node 20 deprecation annotation prompted an additional upgrade of checkout/upload to pinned v7.0.1 Node 24 actions. The [final Node 24 pipeline run](https://github.com/hatish2001/dayloft/actions/runs/34670926296) also passed every step for `91af9a4`, without that annotation.

## Remaining launch gates

- Configure Developer ID signing/notarization credentials and the production Sparkle signing key. These are absent; the release job has not produced a notarized package.
- On a dedicated test Mac, verify Instagram's parent and endpoints in Safari/Chromium during a live block, a full break/resume and natural expiry, reboot/sleep/wake, and app-closed recurring starts.
- Verify cleanup with another PF-using application present, and run on Intel hardware.
- Install a notarized download on a clean Mac; exercise the full signed update, relaunch, preserved schedules/history, helper upgrade, and rejected-tampered-download paths.

Until these pass, ship source and development builds only. The reviewed workflow creates a draft, so finishing a workflow does not announce or publish a release automatically.
