# Dayloft

Dayloft is a native macOS website blocker with a quiet SwiftUI interface. Choose your distractions, set a rhythm, and leave the rest to your Mac.

- **Home:** focus modes, a live countdown, daily focus time, and a streak built from actual sessions.
- **Schedules:** recurring days and times, including overnight sessions.
- **Breaks:** choose zero to three five-minute breaks for each session.
- **Persistent blocking:** the privileged macOS helper keeps a started block running after you close the app or restart your Mac.
- **Updates:** signed update checks, a download button when a release is available, and user-controlled installation.
- **Local data:** no account, analytics SDK, cloud service, or subscription.

Dayloft is an independent GPL-licensed derivative of [SelfControl](https://github.com/SelfControlApp/selfcontrol). Its Objective-C blocking engine is native macOS code; the new interface is SwiftUI. See [attribution and licenses](NOTICE.md).

## Install

Requires **macOS 13 Ventura or later**. The app supports Apple silicon and Intel builds.

**Public binary release: not published yet.** This repository includes the build and notarization pipeline. Until a signed, notarized release is available, use the source-build instructions below. An unsigned CI artifact is for development and cannot install the privileged helper.

When an official release is published:

1. Download `Dayloft-<version>.dmg` from [Releases](https://github.com/hatish2001/dayloft/releases) page.
2. Drag **Dayloft** into **Applications**, then open it.
3. Choose the websites to block. The first block or enabled schedule asks macOS for administrator authorization to install the helper.

A started block cannot be cancelled early. Choose a short first session and a break budget that suits you. Quitting or deleting the app does not remove an active block.

## Build from source

Install Xcode, its command-line tools, and Ruby 3.3 or later. From this repository:

```sh
bundle install
bundle exec pod install --project-directory=SelfControl
./scripts/test.sh
./scripts/build-dayloft.sh
open build/Dayloft.app
```

The default build is unsigned and lets you inspect the interface. To use real website blocking, sign the app and its helper with your own Apple Development identity:

```sh
DAYLOFT_TEAM_ID=YOUR_TEAM_ID ./scripts/build-dayloft.sh
```

Alternatively open `Dayloft.xcworkspace` in Xcode and select the **Dayloft** scheme. Supply your development team for the app and helper targets. Do not open the `.xcodeproj` alone; dependencies are provided by the workspace.

The inherited engine retains internal `SelfControl` target and class names. Runtime app identifiers, settings, hosts-file markers, authorization rights, and firewall anchors belong to Dayloft. Existing SelfControl website preferences can be imported on first launch; its active blocks and schedules are not transferred or removed.

## Everyday use

**Choose a mode.** Edit the websites for Living, Deep Work, or Offline. Paste full URLs or domains; Dayloft normalizes them using the existing engine. An optional allowlist blocks everything except the listed destinations.

**Block now.** Choose a duration and a break budget. While focusing, take an available break, add a website to the block, or extend your time.

**Set a schedule.** Pick days, start/end times, websites, and breaks. Starter routines are disabled until you enable them. Enabled routines are stored by the helper and run with the app closed. On wake, a routine runs only for the remaining part of its window; a fully missed window is skipped. Existing focus sessions take precedence. If routines overlap, the first row gets the first opportunity, and a later routine can run for the remainder after it ends. Disabling a routine affects future starts, not a block already in progress.

## Current scope

Dayloft blocks internet destinations, not native application launches. Focus totals exclude breaks and count only recorded sessions. Home shows a seven-day focus history instead of an unconnected Screen Time counter. A streak day requires at least one minute of recorded focus, excluding breaks. Yesterday’s streak remains available until the end of today; a missed day resets it. Days follow the Mac’s current time zone.

The original three backend tests are retained byte-for-byte. Additional tests cover recurring schedule validation, calendar boundaries, daylight saving, and focus accounting. A local signed build has been checked for website enforcement. Break/resume, restart/wake, and distribution checks still need the manual release verification described in [releasing](docs/RELEASING.md). See [validation results](docs/VALIDATION.md) for the exact limits.

## Contribute

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [the architecture notes](docs/ARCHITECTURE.md). For a security-sensitive issue, see [SECURITY.md](SECURITY.md).

## License

GPL-3.0-or-later. Distributed without warranty. Original copyright and third-party notices are retained in [LICENSE](LICENSE), [NOTICE.md](NOTICE.md), and the source files. Dayloft is not affiliated with the Bloom product or the SelfControl maintainers.
