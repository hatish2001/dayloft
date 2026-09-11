// Copyright 2026 Dayloft contributors. GPL-3.0-or-later.
import Foundation

enum DayloftUpdatePolicy {
    static func isConfigured(feed: String, publicKey: String) -> Bool {
        guard let url = URLComponents(string: feed), url.scheme == "https",
              let host = url.host, host.contains("."), !host.hasSuffix(".example"),
              host != "example.com", host != "127.0.0.1", url.user == nil, url.password == nil,
              url.fragment == nil, let key = Data(base64Encoded: publicKey), key.count == 32,
              key.contains(where: { $0 != 0 }) else { return false }
        return true
    }
    static func canRequestUpdate(configured: Bool, canCheck: Bool, focusActive: Bool, busy: Bool) -> Bool {
        configured && canCheck && !focusActive && !busy
    }
}
