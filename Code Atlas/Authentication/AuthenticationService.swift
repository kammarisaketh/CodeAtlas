//
//  AuthenticationService.swift
//  Code Atlas
//

import Foundation

actor AuthenticationService: AuthenticationServicing {
    private enum Key {
        static let accessToken = "accessToken"
        static let refreshToken = "refreshToken"
        static let expiresAt = "expiresAt"
    }

    private let keychain: KeychainServicing
    private let apiClient: APIClient

    init(keychain: KeychainServicing, apiClient: APIClient) {
        self.keychain = keychain
        self.apiClient = apiClient
    }

    func restoreSession() async throws -> UserSession? {
        guard
            let accessToken = try keychain.readValue(for: Key.accessToken),
            let refreshToken = try keychain.readValue(for: Key.refreshToken),
            let expiresAtValue = try keychain.readValue(for: Key.expiresAt),
            let expiresAt = ISO8601DateFormatter().date(from: expiresAtValue)
        else {
            return nil
        }

        return UserSession(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    func authenticateWithApple(identityToken: String, authorizationCode: String?) async throws -> UserSession {
        let request = AppleAuthPayload(identityToken: identityToken, authorizationCode: authorizationCode)
        let response: TokenResponse = try await apiClient.send("auth/apple", method: "POST", body: request)
        let session = UserSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
        try persist(session)
        return session
    }

    func logout() async throws {
        try keychain.deleteValue(for: Key.accessToken)
        try keychain.deleteValue(for: Key.refreshToken)
        try keychain.deleteValue(for: Key.expiresAt)
    }

    private func persist(_ session: UserSession) throws {
        try keychain.save(session.accessToken, for: Key.accessToken)
        try keychain.save(session.refreshToken, for: Key.refreshToken)
        try keychain.save(ISO8601DateFormatter().string(from: session.expiresAt), for: Key.expiresAt)
    }
}

private struct AppleAuthPayload: Encodable {
    let identityToken: String
    let authorizationCode: String?
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}
