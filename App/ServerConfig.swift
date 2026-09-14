import Foundation

/// Where the app talks to Barry, and how it authenticates.
///
/// Reaching the Mac:
///  - Simulator: straight to the barry.works proxy on localhost.
///  - Device: over Tailscale to the Mac, with a Host header so Caddy routes
///    the request to the barry.works site block (which injects the API secret
///    for trusted-network callers).
struct ServerConfig: Equatable {
    var baseURL: String
    var hostHeader: String
    var secret: String

    static let defaultsKeyBase = "server.baseURL"
    static let defaultsKeyHost = "server.hostHeader"
    static let keychainSecretKey = "rocks.barry.secret"

    static var platformDefault: ServerConfig {
        #if targetEnvironment(simulator)
        ServerConfig(baseURL: "http://127.0.0.1:9429", hostHeader: "", secret: "")
        #else
        ServerConfig(baseURL: "http://100.101.38.91", hostHeader: "barry.lan", secret: "")
        #endif
    }

    static func load() -> ServerConfig {
        // UI-test hook: `-barryBaseURL <url>` overrides everything else and
        // skips the keychain, so a test can point the app at an unreachable
        // server (to exercise the error state) without touching real
        // persisted settings. Never wired to anything but launch arguments.
        let args = ProcessInfo.processInfo.arguments
        if let flagIndex = args.firstIndex(of: "-barryBaseURL"), args.count > flagIndex + 1 {
            return ServerConfig(baseURL: args[flagIndex + 1], hostHeader: "", secret: "")
        }

        let d = UserDefaults.standard
        var c = platformDefault
        if let base = d.string(forKey: defaultsKeyBase), !base.isEmpty { c.baseURL = base }
        if let host = d.string(forKey: defaultsKeyHost) { c.hostHeader = host }
        c.secret = Keychain.read(key: keychainSecretKey) ?? ""
        return c
    }

    func save() {
        let d = UserDefaults.standard
        d.set(baseURL, forKey: Self.defaultsKeyBase)
        d.set(hostHeader, forKey: Self.defaultsKeyHost)
        if secret.isEmpty {
            Keychain.delete(key: Self.keychainSecretKey)
        } else {
            Keychain.write(key: Self.keychainSecretKey, value: secret)
        }
    }

    /// Build a request for an API path, applying host header and secret.
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
        if !hostHeader.isEmpty { req.setValue(hostHeader, forHTTPHeaderField: "Host") }
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
