# Attribution and license notices

Dayloft is an independently maintained, modified version of SelfControl. It is distributed under GNU GPL version 3 or, at your option, any later version. See LICENSE. There is no warranty.

The supplied engine is based on SelfControlApp/selfcontrol commit `34774c413013f903dce00c4f5cb17bc8d3a3c273`, with existing local changes for URL normalization, strict blocking, scheduling, and break budgets. The original project credits Charlie Stigler, Steve Lambert, Eyebeam, and its contributors. Original source copyright and licensing notices are preserved.

Dayloft changes made in September 2026 include the native SwiftUI interface, recurring schedule evaluation, focus-session accounting, app identity and artwork, removal of upstream telemetry/update services, and public build/release tooling. New code and artwork are copyright 2026 Dayloft contributors, licensed GPL-3.0-or-later.

The interface uses platform controls, typography, and original code-drawn artwork. No Bloom screenshots, logo artwork, app code, or other bundled Bloom assets are included. Dayloft is not affiliated with Bloom or with the SelfControl maintainers.

Third-party dependencies:

| Component | Version or revision | License |
| --- | --- | --- |
| ArgumentParser | `fdf684fa2d9e89f40067217e615f7e54a8267c28` | Dual BSD/MIT; see `docs/licenses/ArgumentParser.md` |
| MASPreferences | 1.1.4 | BSD 2-Clause; see `docs/licenses/MASPreferences.md` |
| TransformerKit | 1.1.1 | MIT; see `docs/licenses/TransformerKit.md` |
| FormatterKit | 1.8.2 | MIT; see `docs/licenses/FormatterKit.txt` |
| Sparkle | 2.9.6 | MIT; see `docs/licenses/Sparkle.txt` |
| LetsMove | 1.25 | Public domain; see `docs/licenses/LetsMove.txt` |

ArgumentParser source is included. CocoaPods dependencies are pinned in `SelfControl/Podfile.lock`. The release source archive includes the resolved dependency source and its license notices so it accompanies the binary it was built from.
