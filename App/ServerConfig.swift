import Foundation

/// Where the app talks to Barry, and how it authenticates.
///
///  - Simulator: straight to the barry.works proxy on localhost, which injects
///    the API secret for loopback callers. Nothing to configure.
///  - Device: HTTPS over the personal tailnet to a userspace `tailscaled`
///    sidecar, which terminates TLS and proxies to the API on `127.0.0.1:4854`.
///
/// The device host is a real tailnet DNS name with a real Let's Encrypt
/// certificate, so there is no certificate prompt and no pinning to do. It
/// replaces the old `http://<tailscale-ip>` + `Host: barry.lan` Caddy route:
/// that shape shipped a hardcoded IP that went stale within a day, and the
/// sidecar's stable name removes the reason to edit an address at all.
///
/// The secret is REQUIRED on the device path. `:4854` rejects an unauthenticated
/// caller with 403 even from loopback — only `/health` is open — so unlike the
/// old proxy route there is nothing upstream filling the secret in.
struct ServerConfig: Equatable {
    var baseURL: String
    var secret: String

    static let defaultsKeyBase = "server.baseURL"
    static let keychainSecretKey = "rocks.barry.secret"

    static let defaultDeviceURL = "https://barry-mac.tail5cb2f2.ts.net:8443"
    static let simulatorURL = "http://127.0.0.1:9429"

    /// The one route on the API that answers without a secret. The probe uses
    /// it to tell "the server is not there" apart from "the secret is wrong".
    static let healthPath = "/health"

    static var platformDefault: ServerConfig {
        #if targetEnvironment(simulator)
        ServerConfig(baseURL: simulatorURL, secret: "")
        #else
        ServerConfig(baseURL: defaultDeviceURL, secret: "")
        #endif
    }

    static func load() -> ServerConfig {
        // UI-test hook: `-barryBaseURL <url>` overrides everything else and
        // skips the keychain, so a test can point the app at an unreachable
        // server (to exercise the error state) without touching real
        // persisted settings. Never wired to anything but launch arguments.
        let args = ProcessInfo.processInfo.arguments
        if let flagIndex = args.firstIndex(of: "-barryBaseURL"), args.count > flagIndex + 1 {
            return ServerConfig(baseURL: args[flagIndex + 1], secret: "")
        }

        let d = UserDefaults.standard
        var c = platformDefault
        if let base = d.string(forKey: defaultsKeyBase), !base.isEmpty { c.baseURL = base }
        c.secret = Keychain.read(key: keychainSecretKey) ?? ""
        return c
    }

    func save() {
        UserDefaults.standard.set(baseURL, forKey: Self.defaultsKeyBase)
        if secret.isEmpty {
            Keychain.delete(key: Self.keychainSecretKey)
        } else {
            Keychain.write(key: Self.keychainSecretKey, value: secret)
        }
    }

    /// Build a request for an API path, applying auth.
    func request(path: String, query: [URLQueryItem] = []) -> URLRequest? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return nil }
        var req = URLRequest(url: url)
        apply(to: &req)
        return req
    }

    func apply(to req: inout URLRequest) {
        if !secret.isEmpty { req.setValue(secret, forHTTPHeaderField: "x-barry-secret") }
    }

    var webSocketURL: URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/api/v1/ws"
        return components.url
    }
}

/// Minimal keychain wrapper for the one secret the app stores.
enum Keychain {
    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(key: String, value: String) {
        delete(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
