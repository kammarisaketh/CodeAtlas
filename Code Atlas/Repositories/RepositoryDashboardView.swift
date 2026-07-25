//
//  RepositoryDashboardView.swift
//  Code Atlas
//

import SwiftUI

struct RepositoryDashboardView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var viewModel: RepositoryDashboardViewModel
    @State private var isAddRepositoryPresented = false

    init(repositoryService: RepositoryServicing? = nil) {
        let service = repositoryService ?? RepositoryDashboardPreviewService()
        _viewModel = StateObject(wrappedValue: RepositoryDashboardViewModel(repositoryService: service))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("Loading repositories")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .loaded(let repositories):
                    repositoryList(repositories)

                case .failed(let message, let cached):
                    if cached.isEmpty {
                        ContentUnavailableView(
                            "Backend Not Available",
                            systemImage: "server.rack",
                            description: Text(message)
                        )
                    } else {
                        repositoryList(cached)
                            .safeAreaInset(edge: .bottom) {
                                errorBanner(message)
                            }
                    }
                }
            }
            .navigationTitle("Repositories")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddRepositoryPresented = true
                    } label: {
                        Label("Add Repository", systemImage: "plus")
                    }
                }

                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        Task { await viewModel.loadRepositories() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $isAddRepositoryPresented) {
                AddRepositorySheet(viewModel: viewModel)
                    .presentationDetents([.medium])
            }
            .task {
                await viewModel.loadRepositories()
            }
        }
        .environmentObject(container)
    }

    private func repositoryList(_ repositories: [CodeRepository]) -> some View {
        List {
            if repositories.isEmpty {
                ContentUnavailableView(
                    "No Repositories",
                    systemImage: "folder.badge.plus",
                    description: Text("Add a GitHub repository to begin indexing code, docs, and configuration files.")
                )
            } else {
                Section("Connected Repositories") {
                    ForEach(repositories) { repository in
                        NavigationLink {
                            RepositoryOverviewView(repository: repository, status: viewModel.status(for: repository)) {
                                Task { await viewModel.reindex(repository) }
                            }
                        } label: {
                            RepositoryRow(repository: repository, status: viewModel.status(for: repository))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(repository) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                Task { await viewModel.reindex(repository) }
                            } label: {
                                Label("Re-index", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .refreshable {
            await viewModel.loadRepositories()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08))
    }
}

private struct AddRepositorySheet: View {
    @ObservedObject var viewModel: RepositoryDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub Repository") {
                    TextField("owner/repository", text: $viewModel.repositoryName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Text("Phase 2 uses GitHub first. GitLab and Bitbucket can be added through the repository provider abstraction.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await viewModel.addRepository()
                            if case .loaded = viewModel.state {
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Add")
                        }
                    }
                    .disabled(viewModel.repositoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmitting)
                }
            }
        }
    }
}

private struct RepositoryRow: View {
    let repository: CodeRepository
    let status: IndexingStatus?

    private var effectiveStatus: RepositoryIndexingStatus {
        status?.status ?? repository.indexingStatus
    }

    private var progress: Double {
        Double(status?.progressPercent ?? (effectiveStatus == .completed ? 100 : 0)) / 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.fullName)
                        .font(.headline)

                    Text(repository.defaultBranch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusPill(
                    title: effectiveStatus.displayName,
                    systemImage: effectiveStatus == .completed ? "checkmark.circle" : "clock",
                    tint: effectiveStatus.tint
                )
            }

            if effectiveStatus.isActive {
                ProgressView(value: progress)
                    .tint(.teal)
            }

            if !repository.languages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(repository.languages.sorted(by: { $0.value > $1.value }).prefix(4), id: \.key) { language, count in
                            Text("\(language) \(count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct RepositoryOverviewView: View {
    let repository: CodeRepository
    let status: IndexingStatus?
    let onReindex: () -> Void

    private var effectiveStatus: RepositoryIndexingStatus {
        status?.status ?? repository.indexingStatus
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(repository.fullName)
                        .font(.title2.weight(.bold))
                        .textSelection(.enabled)

                    StatusPill(
                        title: effectiveStatus.displayName,
                        systemImage: effectiveStatus == .completed ? "checkmark.circle" : "clock",
                        tint: effectiveStatus.tint
                    )

                    ProgressView(value: Double(status?.progressPercent ?? (effectiveStatus == .completed ? 100 : 0)), total: 100)
                        .tint(.teal)
                }
                .padding(.vertical, 8)
            }

            Section("Metadata") {
                LabeledContent("Provider", value: repository.provider.rawValue.capitalized)
                LabeledContent("Branch", value: repository.defaultBranch)
                LabeledContent("Last indexed", value: repository.lastIndexedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
            }

            Section("Indexing Pipeline") {
                ForEach(IndexingStage.allCases) { stage in
                    HStack(spacing: 12) {
                        Image(systemName: stage.isReached(by: effectiveStatus) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(stage.isReached(by: effectiveStatus) ? .green : .secondary)
                        Text(stage.title)
                    }
                }
            }
        }
        .navigationTitle("Overview")
        .toolbar {
            Button(action: onReindex) {
                Label("Re-index", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }
}

private enum IndexingStage: String, CaseIterable, Identifiable {
    case cloning
    case parsing
    case embedding
    case finalizing
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cloning: "Securely fetch repository"
        case .parsing: "Parse source and docs"
        case .embedding: "Generate retrieval chunks"
        case .finalizing: "Store metadata and citations"
        case .completed: "Ready for repository chat"
        }
    }

    func isReached(by status: RepositoryIndexingStatus) -> Bool {
        let order: [RepositoryIndexingStatus] = [.queued, .cloning, .parsing, .embedding, .finalizing, .completed]
        guard let statusIndex = order.firstIndex(of: status) else { return false }

        switch self {
        case .cloning: return statusIndex >= 1
        case .parsing: return statusIndex >= 2
        case .embedding: return statusIndex >= 3
        case .finalizing: return statusIndex >= 4
        case .completed: return status == .completed
        }
    }
}

private extension RepositoryIndexingStatus {
    var tint: Color {
        switch self {
        case .completed: .green
        case .failed: .red
        case .notIndexed: .secondary
        case .queued, .cloning, .parsing, .embedding, .finalizing: .teal
        }
    }
}

private actor RepositoryDashboardPreviewService: RepositoryServicing {
    func fetchRepositories() async throws -> [CodeRepository] { [] }
    func addRepository(fullName: String, provider: RepositoryProvider) async throws -> CodeRepository {
        CodeRepository(
            id: UUID(),
            provider: provider,
            fullName: fullName,
            defaultBranch: "main",
            indexingStatus: .queued,
            languages: [:],
            lastIndexedAt: nil
        )
    }
    func startIndexing(repositoryID: UUID) async throws -> IndexingStatus {
        IndexingStatus(repositoryID: repositoryID, status: .queued, progressPercent: 0, errorMessage: nil)
    }
    func fetchIndexingStatus(repositoryID: UUID) async throws -> IndexingStatus {
        IndexingStatus(repositoryID: repositoryID, status: .completed, progressPercent: 100, errorMessage: nil)
    }
    func deleteRepository(repositoryID: UUID) async throws {}
}

#Preview {
    RepositoryDashboardView(repositoryService: RepositoryDashboardPreviewService())
        .environmentObject(AppContainer())
}
