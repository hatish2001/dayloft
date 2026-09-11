# Security

Dayloft has a privileged helper that edits the hosts file and packet-filter rules. Treat changes to XPC authorization, client signing checks, rule installation, persistence, and recovery as security-sensitive.

Report vulnerabilities using this repository’s private vulnerability reporting feature when the public repository enables it. If it is unavailable, ask the maintainer for a private reporting channel before posting exploit details, credentials, or personal logs. Do not file security reports against upstream SelfControl for Dayloft-specific changes.

The helper accepts only the expected Dayloft application/CLI identifiers signed by the same Apple development team as the helper. Mutating XPC methods also require macOS authorization. Unsigned builds cannot satisfy the helper-installation requirements.

No support process should ask you to disclose your administrator password, private signing key, or Apple account credentials. A release must not ask users to disable Gatekeeper or run an undocumented root shell command.
