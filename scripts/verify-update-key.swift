// Copyright 2026 Dayloft contributors. GPL-3.0-or-later.
// Validate release key pairing without logging either key.
import Foundation
import CryptoKit

guard let path = ProcessInfo.processInfo.environment["DAYLOFT_UPDATE_PRIVATE_KEY_FILE"],
      let expected = ProcessInfo.processInfo.environment["DAYLOFT_UPDATE_PUBLIC_KEY"],
      let encoded = try? String(contentsOfFile: path, encoding: .utf8),
      let data = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data),
      key.publicKey.rawRepresentation.base64EncodedString() == expected else {
    fputs("Update signing key is missing, invalid, or does not match the embedded public key.\n", stderr)
    exit(1)
}
print("Update signing key pair verified.")
