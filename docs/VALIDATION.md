# Validation status

Validated locally on Apple silicon with macOS 26 and Xcode 26.6 in September 2026.

## Automated checks

- 60 XCTest tests pass: the 3 unchanged original tests, 6 calendar/schedule tests, 14 Swift model tests, 4 settings-isolation/history tests, 16 website-rule/enforcement-result tests, 3 update-policy tests, 3 authentication-policy tests, and 11 daemon lifecycle tests.
- The original test file matches its recorded SHA-256 checksum.
- A fresh public-source copy with newly installed, pinned CocoaPods dependencies builds and passes tests.
- Both unsigned test bundles and the locally Apple Development-signed app pass resource and embedded-helper identity checks.
- GitHub Actions workflow syntax passes actionlint. The [first public CI run](https://github.com/hatish2001/dayloft/actions/runs/34645315052) passed dependency installation, the test suite, signed-update rejection checks, and the source audit for commit `d3c9710`.
- The public file-set audit excludes generated builds, nested Git metadata, local user state, and signing material; it checks credential patterns and required license/build files.

## Manual checks performed

- Launched the native Home and Schedules interface; inspected website, schedule, and start-session sheets.
- Verified a locally signed session installed Dayloft-specific hosts/PF rules. A selected website failed to connect while an unrelated control site returned HTTP 200.

During validation, the inherited settings broadcaster let a test process affect a running development session, ending it early. This was fixed before delivery: tests now use isolated memory-only settings, the privileged writer rejects notification payloads, and new regression tests cover file access, broadcasting, forged updates, and history cleanup. The originally observed session is not evidence of successful full-duration expiry.

## Not yet verified

- A complete break/resume cycle, natural session expiry, reboot, sleep/wake, and app-closed recurring starts on a dedicated test Mac.
- Intel hardware behavior. The universal Release build passes locally, with both architectures verified in all nine Mach-O binaries.
- Developer ID signing, Apple notarization, Gatekeeper installation on a clean Mac, and an actual public GitHub release run. Public build/test CI passed as recorded above.

The provided app is a local development build. Follow [the release checklist](RELEASING.md) before distributing a public installer. The updated helper is installed through the app's normal macOS authorization flow on the next block or enabled schedule.

## Instagram repair (4.1.2)

The saved `www.instagram.com` entry expanded common endpoints under `www` (for example `api.www.instagram.com`). Expansion now uses the parent of `www`; Instagram subdomain entries also include `instagram.com`, `www.instagram.com`, `i.instagram.com`, `b.i.instagram.com`, `api.instagram.com`, and `graph.instagram.com`. Matching respects DNS label boundaries and does not broaden an API-only allowlist to the Instagram parent. YouTube aliases remain covered.

IPv6 address entries now reach PF alongside IPv4. DNS caches are invalidated before rebuilding rules and after changes, independently of optional browser-cache removal. The start path checks hosts-write and PF-load results; failed starts report an error, and failed restorations remain visible and retryable.

The signed 4.1.2 build and all 28 tests pass locally. Before-block checks reached Instagram's parent, www, and API hosts and YouTube; an ego-browser page loaded Instagram. The 4.1.2 helper is now installed and a short session was recorded between turns. Requests captured while authorization was pending remain pre-block observations; browser enforcement during that session was not captured and still needs verification.

This engine expands explicit hostnames and known endpoints; a hosts file is not a general wildcard-domain filter. Arbitrary subdomains, independently resolved alternate addresses, proxies, and cached offline content are not proven covered by these checks.

## Streak and interface update

Nine additional tests cover overlapping breaks, duplicate sessions, the exact one-minute streak threshold, yesterday's grace period and reset, midnight splitting, paused time, daylight saving, user ownership, and stopped-session history. The weekly activity indicators and streak badge derive from the same activity calculation. The Home and Schedules structure is retained with a new slate/green visual treatment, original animated horizon artwork, a streak-details popover, and real seven-day activity replacing the Screen Time placeholder. The animation respects Reduce Motion.

Manually verified the redesigned Home and Schedules screens in the signed app, the streak popover, seven-day labels and earned-day indicators, and opening/cancelling a schedule editor. The displayed two-day streak agrees with the two qualifying days in the recorded activity.

## Release preparation (4.2.0)

Sparkle 2.9.6 is pinned and bundled. Update-policy tests reject invalid feed/key configuration and defer checks during focus or pending changes. The app includes a quiet update indicator, native Sparkle prompts, automatic-check settings, and a relaunch deferral for a session that begins during download. No production update-signing key or public installer has been configured yet.

Firewall setup now propagates failed configuration writes before loading PF. Appending websites verifies hosts/PF results, isolates append state per manager, and preserves previously blocked entries in the stored list. Three new regression tests cover these failure paths and instance isolation. The lower-left promotional message and dot were removed.

The 4.2.0 local Apple Development-signed app builds and launches. The sidebar tagline and dot are absent; the version and disabled-unconfigured update button are visible. The universal Release build passes and its nine app/helper/CLI/framework binaries contain both arm64 and x86_64. A disposable-key test verifies signatures and rejects a modified payload and mismatched key. A local DMG made from the universal build also passes Sparkle appcast generation and version/size/URL/signature-shape validation. This test uses an ad-hoc signature and is not notarization or an installed-app update test.

## Final code and pipeline review (4.2.1)

See [the release review](RELEASE_REVIEW.md) for findings, fixes, and remaining launch checks. The new lifecycle suite links an inert daemon double and intercepts network-rule operations, persistence, cache clearing, and notifications; tests never start the real daemon. All 51 local tests and the universal Release build pass.

The [final public pipeline run](https://github.com/hatish2001/dayloft/actions/runs/34670926296) passed the 51 tests, universal Release build, version agreement, signed-update rejection, and source audit with the current Node 24 actions. A local Apple Development-signed 4.2.1 app also passes bundle/signature verification. No new live blocking or public notarization result is claimed.

## Authentication and schedule synchronization repair (4.2.2)

The inherited authorization policy supplied only the UI authentication mechanism. Local authd diagnostics reported that it failed to return a valid UID, explaining the repeating password dialog. The app now delegates mechanism selection to macOS and migrates only the exact defective Dayloft-owned version-1 rule, preserving custom administrator policies. Three isolated tests cover the default rule and migration boundaries. Runtime migration still requires normal macOS authorization; an end-to-end password retry remains pending.

Schedules refresh from the helper alongside Home, display the same session/break countdown, and disable creation, editing, deletion, and switches during an active or starting session. The helper rejects recurring-schedule mutations while a block exists, including breaks and pending cleanup. Tests verify unchanged schedules/session on rejection, editing after successful expiry cleanup, and rollback on a failed save. A persistent configured marker distinguishes an intentionally empty schedule list from initial local drafts.

X/Twitter and TikTok entries include their parent domains and known aliases; allowlists and unrelated DNS suffixes are not broadened. Adding sites during a break saves additions for normal resume and preserves existing entries without reinstalling rules early. These paths are covered by isolated tests; adding the sites to the user's live block and checking live enforcement remain pending authorization.

All 61 tests, original-test checksum, version agreement, source audit, signed app build, and update-signature rejection checks pass locally. Live UI and helper-upgrade verification are tracked separately from these results.

## Website persistence repair (4.2.3)

Adding a distraction during focus now saves it in three durable places: the live block, the selected mode for future manual sessions, and every future denylist schedule. Allowlist schedules remain unchanged because adding a blocked site would weaken them. The helper merges the active set without removing schedule-specific sites, including when a break is active, and rolls back both saved lists if the break-path settings write fails. A regression test confirms additions survive into future denylist schedules while allowlist schedules and the active break remain intact.
