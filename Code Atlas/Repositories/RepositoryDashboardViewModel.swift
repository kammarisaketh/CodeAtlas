//
//  RepositoryDashboardViewModel.swift
//  Code Atlas
//

import Foundation

@MainActor
final class RepositoryDashboardViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded([CodeRepository])
        case failed(String, cached: [CodeRepository])
    }

    @Published private(set) var state: State = .idle
    @Published var repositoryName = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var indexingStatuses: [UUID: IndexingStatus] = [:]

    private let repositoryService: RepositoryServicing
    private var repositories: [CodeRepository] = []
    private var pollingTasks: [UUID: Task<Void, Never>] = [:]

    init(repositoryService: RepositoryServicing) {
        self.repositoryService = repositoryService
    }

    deinit {
        pollingTasks.values.forEach { $0.cancel() }
    }

    func loadRepositories() async {
        state = .loading
        do {
            repositories = try await repositoryService.fetchRepositories()
            state = .loaded(repositories)
            startPollingActiveRepositories()
        } catch {
            state = .failed(error.localizedDescription, cached: repositories)
        }
    }

    func addRepository() async {
        let fullName = normalizedRepositoryName
        guard isValidRepositoryName(fullName) else {
            state = .failed("Use the GitHub owner/repository format, for example apple/swift.", cached: repositories)
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let repository = try await repositoryService.addRepository(fullName: fullName, provider: .github)
            repositoryName = ""
            repositories.insert(repository, at: 0)
            state = .loaded(repositories)
            _ = try await repositoryService.startIndexing(repositoryID: repository.id)
            pollIndexingStatus(for: repository.id)
        } catch {
            state = .failed(error.localizedDescription, cached: repositories)
        }
    }

    func reindex(_ repository: CodeRepository) async {
        do {
            let status = try await repositoryService.startIndexing(repositoryID: repository.id)
            indexingStatuses[repository.id] = status
            pollIndexingStatus(for: repository.id)
        } catch {
            state = .failed(error.localizedDescription, cached: repositories)
        }
    }

    func delete(_ repository: CodeRepository) async {
        do {
            try await repositoryService.deleteRepository(repositoryID: repository.id)
            pollingTasks[repository.id]?.cancel()
            pollingTasks[repository.id] = nil
            indexingStatuses[repository.id] = nil
            repositories.removeAll { $0.id == repository.id }
            state = .loaded(repositories)
        } catch {
            state = .failed(error.localizedDescription, cached: repositories)
        }
    }

    func status(for repository: CodeRepository) -> IndexingStatus? {
        indexingStatuses[repository.id]
    }

    func currentRepositories() -> [CodeRepository] {
        switch state {
        case .loaded(let repositories): repositories
        case .failed(_, let cached): cached
        case .idle, .loading: repositories
        }
    }

    private var normalizedRepositoryName: String {
        repositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isValidRepositoryName(_ value: String) -> Bool {
        let parts = value.split(separator: "/")
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty }
    }

    private func startPollingActiveRepositories() {
        for repository in repositories where repository.indexingStatus.isActive {
            pollIndexingStatus(for: repository.id)
        }
    }

    private func pollIndexingStatus(for repositoryID: UUID) {
        pollingTasks[repositoryID]?.cancel()
        pollingTasks[repositoryID] = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    let status = try await repositoryService.fetchIndexingStatus(repositoryID: repositoryID)
                    indexingStatuses[repositoryID] = status

                    if !status.status.isActive {
                        pollingTasks[repositoryID] = nil
                        return
                    }
                } catch {
                    state = .failed(error.localizedDescription, cached: repositories)
                    return
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

extension RepositoryIndexingStatus {
    var isActive: Bool {
        switch self {
        case .queued, .cloning, .parsing, .embedding, .finalizing:
            true
        case .notIndexed, .completed, .failed:
            false
        }
    }

    var displayName: String {
        switch self {
        case .notIndexed: "Not indexed"
        case .queued: "Queued"
        case .cloning: "Cloning"
        case .parsing: "Parsing"
        case .embedding: "Embedding"
        case .finalizing: "Finalizing"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}
