import Foundation
import Security

enum TokenError: LocalizedError {
    case keychain(OSStatus)
    case invalidToken
    case invalidHost

    var errorDescription: String? {
        switch self {
        case .keychain(let status): return "Keychain error (\(status))."
        case .invalidToken: return "Enter a token without spaces or line breaks."
        case .invalidHost: return "Invalid Lichess API address."
        }
    }
}

private func tokenQuery() -> [String: Any] {
    return [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "cz.lichesswatch.api-token",
            kSecAttrAccount as String: "lichess"]
}

func readLichessToken() throws -> String? {
    var query = tokenQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw TokenError.keychain(status) }
    guard let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else { throw TokenError.invalidToken }
    return token
}

func saveLichessToken(_ token: String) throws {
    guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw TokenError.invalidToken }
    let query = tokenQuery()
    let value = Data(token.utf8)
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
    if status == errSecItemNotFound {
        var item = query
        item[kSecValueData as String] = value
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw TokenError.keychain(addStatus) }
    } else if status != errSecSuccess { throw TokenError.keychain(status) }
}

func deleteLichessToken() throws {
    let status = SecItemDelete(tokenQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw TokenError.keychain(status) }
}

func lichessRequest(_ url: URL, useToken: Bool = true) throws -> URLRequest {
    guard url.scheme == "https", url.host?.lowercased() == "lichess.org" else { throw TokenError.invalidHost }
    var request = URLRequest(url: url)
    request.setValue("ChessBroadcastWidget/1.0", forHTTPHeaderField: "User-Agent")
    if useToken, let token = try readLichessToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    return request
}

struct TokenDetails: Decodable {
    let userId: String
    let scopes: String
}

func checkLichessToken() async throws -> TokenDetails? {
    guard let token = try readLichessToken() else { return nil }
    var request = URLRequest(url: URL(string: "https://lichess.org/api/token/test")!)
    request.httpMethod = "POST"
    request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
    request.setValue("ChessBroadcastWidget/1.0", forHTTPHeaderField: "User-Agent")
    request.httpBody = Data(token.utf8)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    guard (200..<300).contains(response.statusCode) else { throw LichessHTTPError(status: response.statusCode) }
    let result = try JSONDecoder().decode([String: TokenDetails?].self, from: data)
    return result[token] ?? nil
}
