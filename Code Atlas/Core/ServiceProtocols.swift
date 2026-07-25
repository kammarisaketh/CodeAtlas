//
//  ServiceProtocols.swift
//  Code Atlas
//

import Foundation

protocol AuthenticationServicing: Sendable {
    func restoreSession() async throws -> UserSession?
    func authenticateWithApple(identityToken: String, authorizationCode: String?) async throws -> UserSession
    func logout() async throws
}

protocol RepositoryServicing: Sendable {
    func fetchRepositories() async throws -> [CodeRepository]
    func addRepository(fullName: String, provider: RepositoryProvider) async throws -> CodeRepository
    func startIndexing(repositoryID: UUID) async throws -> IndexingStatus
    func fetchIndexingStatus(repositoryID: UUID) async throws -> IndexingStatus
    func deleteRepository(repositoryID: UUID) async throws
    func searchRepository(repositoryID: UUID, query: String) async throws -> RepositorySearchResponse
    func fetchRepositoryMap(repositoryID: UUID) async throws -> RepositoryMap
    func fetchGitHubConnection() async throws -> GitHubConnection
    func connectGitHub(mockAccountName: String) async throws -> GitHubConnection
    func disconnectGitHub() async throws -> GitHubConnection
}

protocol ChatServicing: Sendable {
    func ask(question: String, repositoryID: UUID) async throws -> AsyncThrowingStream<String, Error>
}

protocol SearchServicing: Sendable {
    func search(query: String, repositoryID: UUID) async throws -> [Citation]
}

protocol KeychainServicing: Sendable {
    func save(_ value: String, for key: String) throws
    func readValue(for key: String) throws -> String?
    func deleteValue(for key: String) throws
}
