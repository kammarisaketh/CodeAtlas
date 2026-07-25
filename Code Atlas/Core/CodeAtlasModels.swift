//
//  CodeAtlasModels.swift
//  Code Atlas
//

import Foundation

enum AppEnvironment: Sendable {
    case development
    case staging
    case production

    var apiBaseURL: URL {
        switch self {
        case .development:
            URL(string: "http://localhost:8000/api/v1")!
        case .staging:
            URL(string: "https://staging-api.codeatlas.dev/api/v1")!
        case .production:
            URL(string: "https://api.codeatlas.dev/api/v1")!
        }
    }
}

struct UserSession: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }
}

struct CodeRepository: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let provider: RepositoryProvider
    let fullName: String
    let defaultBranch: String
    let indexingStatus: RepositoryIndexingStatus
    let languages: [String: Int]
    let lastIndexedAt: Date?
}

enum RepositoryProvider: String, Codable, Sendable {
    case github
}

enum RepositoryIndexingStatus: String, Codable, Sendable {
    case notIndexed = "not_indexed"
    case queued
    case cloning
    case parsing
    case embedding
    case finalizing
    case completed
    case failed
}

struct IndexingStatus: Codable, Equatable, Sendable {
    let repositoryID: UUID
    let status: RepositoryIndexingStatus
    let progressPercent: Int
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case repositoryID = "repository_id"
        case status
        case progressPercent = "progress_percent"
        case errorMessage = "error_message"
    }
}

struct Citation: Identifiable, Codable, Equatable, Sendable {
    let id = UUID()
    let fileID: UUID
    let path: String
    let startLine: Int
    let endLine: Int
    let snippet: String?

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case path
        case startLine = "start_line"
        case endLine = "end_line"
        case snippet
    }
}

struct RepositorySearchResponse: Codable, Equatable, Sendable {
    let query: String
    let results: [RepositorySearchResult]
}

struct RepositorySearchResult: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(fileID.uuidString)-\(startLine)-\(endLine)" }
    let fileID: UUID
    let path: String
    let language: String?
    let startLine: Int
    let endLine: Int
    let snippet: String
    let matchType: String
    let score: Double

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case path
        case language
        case startLine = "start_line"
        case endLine = "end_line"
        case snippet
        case matchType = "match_type"
        case score
    }
}

struct RepositoryMap: Codable, Equatable, Sendable {
    let repositoryID: UUID
    let root: RepositoryMapNode
    let importantModules: [String]
    let entryPoints: [String]
    let edges: [RepositoryMapEdge]

    enum CodingKeys: String, CodingKey {
        case repositoryID = "repository_id"
        case root
        case importantModules = "important_modules"
        case entryPoints = "entry_points"
        case edges
    }
}

struct RepositoryMapNode: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let path: String
    let kind: String
    let language: String?
    let children: [RepositoryMapNode]
}

struct RepositoryMapEdge: Codable, Equatable, Sendable {
    let sourcePath: String
    let targetPath: String
    let relationship: String

    enum CodingKeys: String, CodingKey {
        case sourcePath = "source_path"
        case targetPath = "target_path"
        case relationship
    }
}

struct GitHubConnection: Codable, Equatable, Sendable {
    let connected: Bool
    let accountName: String?
    let scopes: [String]
}
