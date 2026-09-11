# Releasing Dayloft

## Current release state

The source, CI workflow, and release scripts are prepared. A public binary has not been published or notarized. The locally available signing identity is Apple Development, which is suitable for development on this Mac, not a normal downloadable public release.

Apple requires a Developer ID-signed app and notarization for the normal direct-download installation experience. See [Apple’s distribution documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Before the first release

1. Use the dedicated public repository [hatish2001/dayloft](https://github.com/hatish2001/dayloft). Keep LICENSE, NOTICE.md, dependency licenses, and matching source available with every binary.
2. Enable private vulnerability reporting. Configure a `release` Actions environment with required reviewers.
3. Provide a **Developer ID Application** signing identity and notarization credentials. No private keys or credentials belong in the repository.
4. Complete the manual verification below on a test Mac, including an Intel Mac if advertising Intel support.
5. Commit and tag the version represented by `SelfControl/Info.plist`. Confirm CI succeeds on the actual public repository.

## Local release

Install the pinned dependencies, then store your notarization credentials using `xcrun notarytool store-credentials`. The tool prompts for the credential values; do not put passwords in source files.

```sh
export DAYLOFT_TEAM_ID=YOUR_TEAM_ID
export DAYLOFT_SIGN_IDENTITY='Developer ID Application: Your Name (YOUR_TEAM_ID)'
export DAYLOFT_NOTARY_PROFILE=your-stored-keychain-profile
export DAYLOFT_UPDATE_PUBLIC_KEY=YOUR_BASE64_PUBLIC_KEY
export DAYLOFT_UPDATE_PRIVATE_KEY_FILE=/secure/location/dayloft-update.key
./scripts/release.sh
```

The script builds a universal app, checks its signature and architectures, notarizes and staples the app, creates a drag-to-Applications DMG, notarizes/staples that DMG, and produces a corresponding-source archive with resolved dependencies plus a signed Sparkle appcast and SHA256SUMS. It requires a clean committed tree. It does not publish automatically.

Upload the DMG, source archive, appcast.xml, and checksums together as a GitHub release tagged `v<version>`. Test the downloaded package on a separate Mac before announcing it. Do not distribute an Apple Development-signed or unsigned CI build as the public installer.

## GitHub Actions

The manual `Prepare notarized release` workflow builds the same files and uploads them as a workflow artifact and creates a GitHub release draft for review. Set these environment secrets:

- `DAYLOFT_TEAM_ID`
- `DAYLOFT_SIGN_IDENTITY` (the full Developer ID Application identity name)
- `DAYLOFT_CERTIFICATE_BASE64` (exported Developer ID Application certificate plus private key, encoded as base64)
- `DAYLOFT_CERTIFICATE_PASSWORD`
- `DAYLOFT_NOTARY_APPLE_ID`
- `DAYLOFT_NOTARY_PASSWORD` (an app-specific password)
- `DAYLOFT_UPDATE_PRIVATE_KEY` (the exported Sparkle private key)

Also set environment variable `DAYLOFT_UPDATE_PUBLIC_KEY` to the matching public key.

Credentials are loaded only into the isolated release runner. PR CI has no signing credentials. Review and publish the resulting GitHub release draft after the distribution checks. Ordinary source pushes run CI; they do not publish a binary or force an update.

## Manual enforcement verification

Use a dedicated test account/Mac and a harmless test destination. Do not use a normal work block for destructive or failure testing.

- First launch: website selection works, inactive schedule drafts save without authorization, cancellation leaves state unchanged.
- Authorization: cancelling helper installation does not report a saved schedule or an active block.
- A short block: the selected destination is blocked in Safari and Chromium, including a typed URL and a link from a search result; unrelated sites still work.
- Breaks: a permitted five-minute break unlocks the target and relocks automatically; the budget cannot be exceeded.
- Expiry: the rule is removed and the site works without manual cleanup.
- Quit/relaunch and reboot: an active block continues and ends at its saved end time.
- Recurrence: a schedule starts with the app closed, skips fully missed windows, uses the remainder on wake, and handles an overnight weekday boundary.
- Overlap: a new routine never shortens the current block. Disabling a routine only stops future occurrences.
- Restart the helper during a due window: it does not lose or duplicate the occurrence.
- Distribution: verify Gatekeeper assessment and the downloaded/stapled DMG on a clean Mac.

Unit tests do not install the helper or modify hosts/PF. Passing those tests is not evidence that the items above have passed.

## Update signing and delivery

Run `SelfControl/Pods/Sparkle/bin/generate_keys --account org.dayloft.Dayloft` once on a secure maintainer Mac. It stores the private key in Keychain. Use `-p` with that account to obtain the public key and `-x /secure/location/dayloft-update.key` to export the private key for the release process. Protect the export with file permissions and keep a secure backup. Never commit the private key. The script checks that it matches the public key before building.

Release builds embed the public key and the feed URL `https://github.com/hatish2001/dayloft/releases/latest/download/appcast.xml`. The feed points to the versioned notarized DMG and carries its Ed25519 signature. Publishing the draft as the latest stable release makes it discoverable to installed apps. Keep all four release assets together. Increment both the display version and numeric build version in the app/helper plists and Xcode settings for each release.

Users can enable automatic checks or choose **Check for Updates…**. Quiet discoveries light up the sidebar download button. Sparkle presents the download and installation prompt; installation is never automatic. Checks defer during focus and pending changes, and a session that starts during download postpones relaunch. Development builds without a configured key keep the updater disabled.

Before release, install the previous signed version on a clean Mac, publish a test feed with a newer signed build, and verify discovery, download, installation, relaunch, preserved schedules/history, and helper replacement on the next authorized operation. Verify that a tampered installer is rejected and that an active session survives without being shortened. Local policy tests and signing-tool checks do not replace this end-to-end test.
