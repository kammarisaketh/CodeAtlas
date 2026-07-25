//
//  AppContainer.swift
//  Code Atlas
//

import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let environment: AppEnvironment
    let apiClient: APIClient
    let keychainService: KeychainServicing
    let authenticationService: AuthenticationServicing
    let repositoryService: RepositoryServicing

    init(environment: AppEnvironment = .development) {
        self.environment = environment
        let keychain = KeychainService()
        self.keychainService = keychain

        let tokenStore = AccessTokenStore(keychain: keychain)
        self.apiClient = APIClient(baseURL: environment.apiBaseURL) {
            try? tokenStore.accessToken()
        }
        self.authenticationService = AuthenticationService(keychain: keychain, apiClient: apiClient)
        self.repositoryService = RepositoryService(apiClient: apiClient)
    }
}

private struct AccessTokenStore: Sendable {
    let keychain: KeychainServicing

    func accessToken() throws -> String? {
        try keychain.readValue(for: "accessToken")
    }
}
