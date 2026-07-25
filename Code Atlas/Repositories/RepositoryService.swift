//
//  RepositoryService.swift
//  Code Atlas
//

import Foundation

actor RepositoryService: RepositoryServicing {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchRepositories() async throws -> [CodeRepository] {
        try await apiClient.send("repositories", responseType: [CodeRepository].self)
    }

    func addRepository(fullName: String, provider: RepositoryProvider) async throws -> CodeRepository {
        let payload = RepositoryCreatePayload(provider: provider.rawValue, fullName: fullName, defaultBranch: "main")
        return try await apiClient.send("repositories", method: "POST", body: payload, responseType: CodeRepository.self)
    }

    func startIndexing(repositoryID: UUID) async throws -> IndexingStatus {
        try await apiClient.send("repositories/\(repositoryID.uuidString)/index", method: "POST", responseType: IndexingStatus.self)
    }

    func fetchIndexingStatus(repositoryID: UUID) async throws -> IndexingStatus {
        try await apiClient.send("repositories/\(repositoryID.uuidString)/index-status", responseType: IndexingStatus.self)
    }

    func deleteRepository(repositoryID: UUID) async throws {
        try await apiClient.sendWithoutResponse("repositories/\(repositoryID.uuidString)", method: "DELETE")
    }

    func searchRepository(repositoryID: UUID, query: String) async throws -> RepositorySearchResponse {
        try await apiClient.send(
            "repositories/\(repositoryID.uuidString)/search?q=\(query.urlQueryEscaped)",
            responseType: RepositorySearchResponse.self
        )
    }

    func fetchRepositoryMap(repositoryID: UUID) async throws -> RepositoryMap {
        try await apiClient.send("repositories/\(repositoryID.uuidString)/map", responseType: RepositoryMap.self)
    }

    func fetchGitHubConnection() async throws -> GitHubConnection {
        try await apiClient.send("repositories/github/connection", responseType: GitHubConnection.self)
    }

    func connectGitHub(mockAccountName: String) async throws -> GitHubConnection {
        let payload = GitHubConnectPayload(mockAccountName: mockAccountName)
        return try await apiClient.send("repositories/github/connect", method: "POST", body: payload, responseType: GitHubConnection.self)
    }

    func disconnectGitHub() async throws -> GitHubConnection {
        try await apiClient.send("repositories/github/connection", method: "DELETE", responseType: GitHubConnection.self)
    }
}

private struct RepositoryCreatePayload: Encodable {
    let provider: String
    let fullName: String
    let defaultBranch: String
}

private struct GitHubConnectPayload: Encodable {
    let mockAccountName: String
}

private extension String {
    var urlQueryEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
