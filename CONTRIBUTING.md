# Contributing to Dayloft

Build from `Dayloft.xcworkspace` using the Dayloft scheme. Install pinned dependencies with `bundle install` and `bundle exec pod install --project-directory=SelfControl`.

Run `./scripts/test.sh` before sending a pull request. The original `SCUtilityTests.m` is a compatibility contract; its checksum is verified by the test script. Add new regression tests alongside it rather than weakening its assertions.

Keep Home and Schedules simple. Firewall details belong in the engine, not in everyday user flows. Never show simulated focus totals as real data, optimistically mark a schedule saved before the helper acknowledges it, or add a way to shorten an active strict block.

New code is GPL-3.0-or-later. Preserve upstream copyright notices. Do not include signing keys, private certificates, local defaults, screenshots containing personal data, or generated build outputs in a pull request.

The public CI builds and runs tests without signing credentials. Only maintainers can produce a Developer ID-signed release. Local firewall tests should use a short block and harmless test destinations; never run them as part of unit tests.
