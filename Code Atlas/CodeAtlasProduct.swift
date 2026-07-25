//
//  CodeAtlasProduct.swift
//  Code Atlas
//

import AuthenticationServices
import Combine
import Security
import SwiftData
import SwiftUI
import UIKit

struct CodeAtlasProductRootView: View {
    @AppStorage("codeAtlasMockSignedIn") private var isSignedIn = false
    @AppStorage("codeAtlasAppearanceMode") private var appearanceModeRawValue = AccountAppearanceMode.system.rawValue
    @StateObject private var authViewModel = CodeAtlasAuthViewModel()

    private var appearanceMode: AccountAppearanceMode {
        AccountAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    var body: some View {
        Group {
            if isSignedIn {
                TabView {
                    CodeAtlasHomeScreen()
                        .tabItem {
                            Label("Home", systemImage: "house")
                        }

                    BackendRepositoriesScreen(viewModel: BackendRepositoriesViewModel())
                        .tabItem {
                            Label("Repos", systemImage: "folder")
                        }

                    AskYourCodeScreen(viewModel: AskYourCodeViewModel())
                        .tabItem {
                            Label("Ask", systemImage: "bubble.left.and.text.bubble.right")
                        }

                    ArchitectureExplorerScreen(viewModel: ArchitectureExplorerViewModel())
                        .tabItem {
                            Label("Explore", systemImage: "point.3.connected.trianglepath.dotted")
                        }

                    AccountScreen(viewModel: AccountViewModel())
                        .tabItem {
                            Label("Account", systemImage: "person.crop.circle")
                        }
                }
            } else {
                CodeAtlasSignInScreen(
                    viewModel: authViewModel,
                    onSignedIn: {
                        withAnimation(.snappy) {
                            isSignedIn = true
                        }
                    },
                    onMockSignedIn: {
                        withAnimation(.snappy) {
                            isSignedIn = true
                        }
                    }
                )
            }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
        .task {
            if await authViewModel.restoreSession() {
                isSignedIn = true
            }
        }
    }
}

@MainActor
final class CodeAtlasAuthViewModel: ObservableObject {
    @Published private(set) var isAuthenticating = false
    @Published private(set) var errorMessage: String?

    private let backendClient = AccountBackendClient()
    private let tokenStore = CodeAtlasTokenStore()

    func restoreSession() async -> Bool {
        do {
            return try tokenStore.readAccessToken() != nil
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signInWithApple(result: Result<ASAuthorization, Error>) async -> Bool {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                errorMessage = "Apple did not return an identity token. Try again."
                return false
            }
            let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let tokens = try await backendClient.authenticateWithApple(identityToken: identityToken, authorizationCode: authorizationCode)
            try tokenStore.save(tokens)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct CodeAtlasSignInScreen: View {
    @ObservedObject var viewModel: CodeAtlasAuthViewModel
    let onSignedIn: () -> Void
    let onMockSignedIn: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image("CodeAtlasLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 86, height: 86)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(radius: 18, y: 10)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("CodeAtlas")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                        Text("AI code intelligence for engineers who need to understand, review, and navigate large codebases with confidence.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Label("Repository-grounded AI answers", systemImage: "quote.bubble")
                        Label("Code review, refactoring, and PR risk analysis", systemImage: "checkmark.seal")
                        Label("Architecture maps and source citations", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .font(.headline)

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task {
                            if await viewModel.signInWithApple(result: result) {
                                onSignedIn()
                            }
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(viewModel.isAuthenticating)

                    if viewModel.isAuthenticating {
                        ProgressView("Signing in securely")
                            .font(.callout)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Continue with Mock Session", action: onMockSignedIn)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("continueMockSessionButton")
                }
                .padding(28)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("signInScrollView")
            .navigationTitle("Welcome")
        }
    }
}

// MARK: - Services

protocol CodeAtlasIntelligenceServicing: Actor {
    func analyzeCode() async throws -> CodeReviewSummary
    func streamAnswer(for question: String) async -> AsyncThrowingStream<String, Error>
    func loadArchitecture() async throws -> ArchitectureSnapshot
    func generateRefactorPlan() async throws -> [RefactorRecommendation]
    func reviewPullRequest() async throws -> PullRequestSummary
}

actor MockCodeAtlasIntelligenceService: CodeAtlasIntelligenceServicing {
    func analyzeCode() async throws -> CodeReviewSummary {
        try await Task.sleep(for: .milliseconds(700))
        return CodeReviewSummary(
            score: 82,
            repositoryName: "codeatlas/mobile-app",
            filePath: "Sources/Auth/SessionManager.swift",
            analyzedLines: 248,
            issues: [
                CodeIssue(severity: .critical, title: "Refresh token is retained longer than needed", detail: "The token is read into memory and reused across multiple awaits. Keep it scoped to the refresh request and clear temporary state after the call.", filePath: "Sources/Auth/SessionManager.swift", lineRange: "42-61", category: "Security"),
                CodeIssue(severity: .warning, title: "Network retry has no backoff", detail: "Three immediate retries can amplify load during an outage. Add exponential backoff and cancellation checks.", filePath: "Sources/Networking/APIClient.swift", lineRange: "88-107", category: "Performance"),
                CodeIssue(severity: .info, title: "Parsing can move out of the view model", detail: "Response mapping is testable business logic. Move it into a mapper so the view model only coordinates state.", filePath: "Sources/Repositories/RepositoryViewModel.swift", lineRange: "130-151", category: "Maintainability")
            ],
            snippet: "func refreshSession() async throws {\n    let refreshToken = try keychain.readValue(for: Key.refreshToken)\n    let response = try await api.refresh(refreshToken)\n    try keychain.save(response.accessToken, for: Key.accessToken)\n}"
        )
    }

    func streamAnswer(for question: String) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let chunks = [
                    "JWT authentication is implemented in `Sources/Auth/SessionManager.swift`, ",
                    "where the access token is loaded from Keychain and attached to authenticated requests. ",
                    "The backend refresh path is represented by `POST /auth/refresh`, and the iOS client calls it before retrying a protected endpoint.\n\n",
                    "Evidence:\n- `Sources/Auth/SessionManager.swift:42-61` refreshes tokens.\n- `Sources/Networking/APIClient.swift:74-93` attaches the bearer token.\n\n",
                    "Confidence: High, based on matching auth symbols and request flow citations."
                ]

                for chunk in chunks {
                    try await Task.sleep(for: .milliseconds(260))
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    func loadArchitecture() async throws -> ArchitectureSnapshot {
        try await Task.sleep(for: .milliseconds(450))
        let appFile = ArchitectureFile(
            name: "CodeAtlasApp.swift",
            path: "Sources/App/CodeAtlasApp.swift",
            language: "Swift",
            purpose: "Creates the SwiftUI application, owns the SwiftData container, and injects shared services into the root view.",
            dependencies: ["AppContainer", "SwiftData", "ContentView"],
            relatedFiles: ["Sources/Core/AppContainer.swift", "Sources/App/ContentView.swift"],
            sampleCode: """
            @main
            struct CodeAtlasApp: App {
                var body: some Scene {
                    WindowGroup { CodeAtlasProductRootView() }
                        .modelContainer(for: AtlasProgress.self)
                }
            }
            """
        )
        let chatFile = ArchitectureFile(
            name: "ChatViewModel.swift",
            path: "Sources/Chat/ChatViewModel.swift",
            language: "Swift",
            purpose: "Coordinates repository-grounded questions, streamed mock answers, citation state, and cancellation when the user leaves chat.",
            dependencies: ["CodeAtlasIntelligenceServicing", "CitationNavigator", "SavedItemsStore"],
            relatedFiles: ["Sources/Chat/ChatView.swift", "Sources/SourceViewer/SourceViewer.swift"],
            sampleCode: """
            @MainActor
            final class ChatViewModel: ObservableObject {
                func ask(_ question: String) async {
                    for try await token in service.streamAnswer(for: question) {
                        answer += token
                    }
                }
            }
            """
        )
        let repositoryFile = ArchitectureFile(
            name: "RepositoryDashboardViewModel.swift",
            path: "Sources/Repositories/RepositoryDashboardViewModel.swift",
            language: "Swift",
            purpose: "Loads connected repositories, exposes indexing progress, and keeps dashboard filtering outside SwiftUI views.",
            dependencies: ["RepositoryServicing", "IndexingStatus", "SwiftData cache"],
            relatedFiles: ["Sources/Repositories/RepositoryDashboardView.swift", "Sources/Networking/APIClient.swift"],
            sampleCode: """
            @MainActor
            final class RepositoryDashboardViewModel: ObservableObject {
                @Published private(set) var repositories: [RepositorySummary] = []
                func refresh() async { repositories = await service.repositories() }
            }
            """
        )
        let sourceFile = ArchitectureFile(
            name: "SourceViewer.swift",
            path: "Sources/SourceViewer/SourceViewer.swift",
            language: "Swift",
            purpose: "Displays cited source files with line numbers, search matches, copy actions, and jump-to-line navigation.",
            dependencies: ["SyntaxHighlighter", "Citation", "DesignSystem"],
            relatedFiles: ["Sources/Chat/CitationView.swift", "Sources/Search/SearchResultsView.swift"],
            sampleCode: """
            ScrollViewReader { proxy in
                LazyVStack(alignment: .leading) {
                    ForEach(file.lines) { CodeLineView(line: $0) }
                }
                .onAppear { proxy.scrollTo(targetLine, anchor: .center) }
            }
            """
        )

        return ArchitectureSnapshot(
            modules: [
                ArchitectureModule(name: "App", symbol: "app.connected.to.app.below.fill", responsibility: "Composition root, navigation shell, dependency container", files: 6, dependencies: ["Core", "DesignSystem"]),
                ArchitectureModule(name: "Authentication", symbol: "person.badge.key", responsibility: "Apple sign-in, token refresh, Keychain storage", files: 8, dependencies: ["Networking", "Core"]),
                ArchitectureModule(name: "Repositories", symbol: "folder", responsibility: "Repository connection, indexing progress, metadata", files: 12, dependencies: ["Networking", "SourceViewer"]),
                ArchitectureModule(name: "Chat", symbol: "bubble.left.and.text.bubble.right", responsibility: "Repository questions, streamed answers, citations", files: 10, dependencies: ["Networking", "SavedItems"]),
                ArchitectureModule(name: "SourceViewer", symbol: "curlybraces", responsibility: "Syntax highlighted files and citation line jumps", files: 7, dependencies: ["DesignSystem"])
            ],
            entryPoints: ["Code_AtlasApp.swift", "AppContainer.swift", "RepositoryDashboardView.swift"],
            riskNotes: ["Authentication and Networking are correctly separated.", "Chat should depend on citation models rather than raw markdown strings.", "SourceViewer should use incremental rendering for large files."],
            architectureNotes: [
                "The App module owns dependency creation, while feature modules receive services through view models.",
                "Repository indexing feeds Search, Chat, SourceViewer, and SavedItems through shared citation models.",
                "Networking remains below feature modules so tests can replace services with deterministic mocks."
            ],
            folders: [
                ArchitectureFolder(name: "Sources", symbol: "folder", folders: [
                    ArchitectureFolder(name: "App", symbol: "app", files: [appFile]),
                    ArchitectureFolder(name: "Repositories", symbol: "folder", files: [repositoryFile]),
                    ArchitectureFolder(name: "Chat", symbol: "bubble.left.and.text.bubble.right", files: [chatFile]),
                    ArchitectureFolder(name: "SourceViewer", symbol: "curlybraces", files: [sourceFile])
                ]),
                ArchitectureFolder(name: "Tests", symbol: "checkmark.seal", files: [
                    ArchitectureFile(
                        name: "ChatStreamingTests.swift",
                        path: "Tests/ChatStreamingTests.swift",
                        language: "Swift",
                        purpose: "Verifies streamed answer assembly, cancellation, and citation navigation against mock repository content.",
                        dependencies: ["Testing", "MockCodeAtlasIntelligenceService"],
                        relatedFiles: ["Sources/Chat/ChatViewModel.swift"],
                        sampleCode: """
                        @Test func streamStopsWhenCancelled() async throws {
                            let model = ChatViewModel(service: mock)
                            await model.cancelCurrentAnswer()
                            #expect(model.isStreaming == false)
                        }
                        """
                    )
                ])
            ]
        )
    }

    func generateRefactorPlan() async throws -> [RefactorRecommendation] {
        try await Task.sleep(for: .milliseconds(650))
        return [
            RefactorRecommendation(
                priority: .high,
                title: "Extract token refresh policy",
                problem: "Duplicate token refresh handling appears in APIClient and SessionManager.",
                whyItMatters: "Two refresh paths can diverge and create flaky session-expiration behavior under poor network conditions.",
                suggestedSolution: "Introduce a TokenRefreshPolicy service owned by Authentication and inject it into networking clients.",
                beforeCode: """
                if response.statusCode == 401 {
                    try await refreshToken()
                    return try await send(request)
                }
                """,
                afterCode: """
                if await refreshPolicy.shouldRefresh(after: response) {
                    try await refreshPolicy.refreshSession()
                    return try await send(request)
                }
                """,
                impacts: [.readability, .maintainability],
                files: ["Sources/Auth/SessionManager.swift", "Sources/Networking/APIClient.swift"],
                maintainabilityScore: 64,
                estimatedComplexity: "Medium"
            ),
            RefactorRecommendation(
                priority: .medium,
                title: "Split long chat response method",
                problem: "ChatViewModel.ask handles validation, stream creation, token assembly, and error formatting in one method.",
                whyItMatters: "Long async methods are harder to cancel safely and make streaming regressions difficult to isolate in tests.",
                suggestedSolution: "Move stream consumption into a private consumeAnswerStream method and keep ask focused on user intent.",
                beforeCode: """
                func ask() async {
                    messages.append(.user(question))
                    for try await chunk in service.streamAnswer(for: question) {
                        messages[index].content += chunk
                    }
                }
                """,
                afterCode: """
                func ask() async {
                    let request = makeQuestionRequest()
                    await consumeAnswerStream(for: request)
                }
                """,
                impacts: [.readability, .maintainability],
                files: ["Sources/Chat/ChatViewModel.swift"],
                maintainabilityScore: 72,
                estimatedComplexity: "Low"
            ),
            RefactorRecommendation(
                priority: .medium,
                title: "Introduce CitationNavigator",
                problem: "Citation tap handling is coupled to chat rendering instead of being shared by search, saved answers, and PR comments.",
                whyItMatters: "Every feature that opens source context will otherwise duplicate file lookup and line-jump behavior.",
                suggestedSolution: "Create a small navigator object that accepts Citation values and returns a SourceViewerRoute.",
                beforeCode: """
                Button(citation.filePath) {
                    selectedFile = citation.filePath
                    selectedLine = citation.startLine
                }
                """,
                afterCode: """
                Button(citation.filePath) {
                    route = citationNavigator.route(for: citation)
                }
                """,
                impacts: [.readability, .maintainability],
                files: ["Sources/Chat/ChatView.swift", "Sources/SourceViewer/SourceViewer.swift"],
                maintainabilityScore: 69,
                estimatedComplexity: "Medium"
            ),
            RefactorRecommendation(
                priority: .medium,
                title: "Cache repeated repository map transforms",
                problem: "Repository map rows are transformed every time the Explore screen refreshes.",
                whyItMatters: "Repeated tree reconstruction can make large repositories feel slower on older iPhones.",
                suggestedSolution: "Cache the normalized tree snapshot by repository ID and invalidate it only after indexing completes.",
                beforeCode: """
                let tree = files.reduce(into: Tree()) { tree, file in
                    tree.insert(file.path)
                }
                """,
                afterCode: """
                let tree = try await architectureCache.tree(
                    for: repositoryID,
                    files: files
                )
                """,
                impacts: [.performance, .maintainability],
                files: ["Sources/Explore/ArchitectureExplorerViewModel.swift"],
                maintainabilityScore: 74,
                estimatedComplexity: "Medium"
            ),
            RefactorRecommendation(
                priority: .low,
                title: "Rename abbreviated PR risk labels",
                problem: "Short labels like PRRisk and sev are clear to the author but less readable in shared models.",
                whyItMatters: "Domain models are used across UI tests, screenshots, and future API contracts where explicit names age better.",
                suggestedSolution: "Prefer PullRequestRisk and severity throughout model and view code.",
                beforeCode: "let sev: FindingSeverity",
                afterCode: "let severity: FindingSeverity",
                impacts: [.readability],
                files: ["Sources/PullRequests/PullRequestModels.swift"],
                maintainabilityScore: 88,
                estimatedComplexity: "Low"
            )
        ]
    }

    func reviewPullRequest() async throws -> PullRequestSummary {
        try await Task.sleep(for: .milliseconds(800))
        return PullRequestSummary(
            title: "PR #128: Add repository chat streaming",
            riskScore: 68,
            summary: "This change adds repository-grounded streaming answers and citation navigation. The implementation is directionally sound, but merge risk is medium-high until cancellation and logging behavior are tightened.",
            approvalStatus: .changesRequested,
            changedFiles: [
                PullRequestFile(path: "Sources/Chat/ChatService.swift", additions: 88, deletions: 12, risk: .high, diffLines: [
                    PullRequestDiffLine(kind: .context, number: 42, text: "func streamAnswer(for question: String) async throws -> AsyncThrowingStream<String, Error> {"),
                    PullRequestDiffLine(kind: .removed, number: 49, text: "print(\"chunk: \\(chunk)\")"),
                    PullRequestDiffLine(kind: .added, number: 49, text: "logger.debug(\"received streamed answer chunk\")"),
                    PullRequestDiffLine(kind: .added, number: 55, text: "try Task.checkCancellation()")
                ]),
                PullRequestFile(path: "Sources/Networking/SSEClient.swift", additions: 141, deletions: 0, risk: .high, diffLines: [
                    PullRequestDiffLine(kind: .added, number: 18, text: "struct SSEClient {"),
                    PullRequestDiffLine(kind: .added, number: 52, text: "for try await line in bytes.lines {"),
                    PullRequestDiffLine(kind: .added, number: 71, text: "continuation.yield(event.data)")
                ]),
                PullRequestFile(path: "Sources/Chat/CitationView.swift", additions: 42, deletions: 6, risk: .medium, diffLines: [
                    PullRequestDiffLine(kind: .removed, number: 21, text: "Text(citation.filePath)"),
                    PullRequestDiffLine(kind: .added, number: 21, text: "Button(citation.filePath) { openCitation(citation) }")
                ]),
                PullRequestFile(path: "Tests/ChatStreamingTests.swift", additions: 64, deletions: 0, risk: .low, diffLines: [
                    PullRequestDiffLine(kind: .added, number: 12, text: "@Test func streamedAnswerIncludesCitations() async throws {"),
                    PullRequestDiffLine(kind: .added, number: 31, text: "#expect(answer.citations.count == 2)")
                ])
            ],
            comments: [
                PullRequestComment(filePath: "Sources/Chat/ChatService.swift", line: 55, severity: .warning, message: "Good cancellation checkpoint. Add a UI test that navigates away while the stream is active."),
                PullRequestComment(filePath: "Sources/Networking/SSEClient.swift", line: 52, severity: .critical, message: "Bound retry attempts and surface a typed error after repeated disconnects."),
                PullRequestComment(filePath: "Sources/Chat/CitationView.swift", line: 21, severity: .info, message: "Citation buttons now route to source context. Reuse this path from saved answers too.")
            ],
            securityConcerns: [
                "Do not log raw streamed chunks because answers can contain private repository snippets.",
                "Ensure citation file paths are authorized for the selected repository before opening them."
            ],
            performanceSuggestions: [
                "Buffer small token chunks before publishing to SwiftUI to reduce view invalidations.",
                "Move large diff rendering into LazyVStack rows for long pull requests."
            ]
        )
    }
}

// MARK: - View Models

@MainActor
final class AICodeReviewViewModel: ObservableObject {
    @Published private(set) var summary: CodeReviewSummary?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let backendClient = AccountBackendClient()

    func analyze() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let backendSummary = try await backendClient.reviewLatestRepository()
            summary = CodeReviewSummary(backend: backendSummary)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class AskYourCodeViewModel: ObservableObject {
    @Published var question = "Where is JWT authentication implemented?"
    @Published private(set) var messages: [CodeChatMessage] = [
        CodeChatMessage(role: .assistant, content: "Ask a repository-specific question. CodeAtlas answers only from indexed code and shows citations.")
    ]
    @Published private(set) var isStreaming = false

    private let backendClient = AccountBackendClient()

    func ask() async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        messages.append(CodeChatMessage(role: .user, content: trimmed))
        question = ""
        isStreaming = true
        messages.append(CodeChatMessage(role: .assistant, content: ""))
        let assistantIndex = messages.count - 1

        do {
            let stream = try await backendClient.streamChat(question: trimmed)
            for try await chunk in stream {
                messages[assistantIndex].content += chunk
            }
        } catch {
            messages[assistantIndex].content += "\n\nUnable to stream response: \(error.localizedDescription)"
        }

        isStreaming = false
    }
}

@MainActor
private final class BackendRepositoriesViewModel: ObservableObject {
    @Published private(set) var repositories: [BackendRepository] = []
    @Published private(set) var indexingStatuses: [UUID: BackendIndexingStatus] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var repositoryName = "pypa/sampleproject"

    private let backendClient = AccountBackendClient()

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            repositories = try await backendClient.fetchRepositories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addRepository() async {
        let name = repositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.split(separator: "/").count == 2 else {
            errorMessage = "Use owner/repository format, for example openai/example."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let repository = try await backendClient.createRepository(fullName: name)
            withAnimation(.snappy) {
                repositories.insert(repository, at: 0)
            }
            repositoryName = ""
            await startIndexing(repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startIndexing(_ repository: BackendRepository) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let status = try await backendClient.startIndexing(repositoryID: repository.id)
            indexingStatuses[repository.id] = status
            repositories = try await backendClient.fetchRepositories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRepository(_ repository: BackendRepository) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await backendClient.deleteRepository(repositoryID: repository.id)
            indexingStatuses.removeValue(forKey: repository.id)
            withAnimation(.snappy) {
                repositories.removeAll { $0.id == repository.id }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class ArchitectureExplorerViewModel: ObservableObject {
    @Published private(set) var snapshot: ArchitectureSnapshot?
    @Published private(set) var selectedFile: ArchitectureFile?
    @Published private(set) var selectedFileContent: String?
    @Published var searchText = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingFile = false

    private let service: any CodeAtlasIntelligenceServicing
    private let backendClient = AccountBackendClient()
    private var backendRepositoryID: UUID?

    var filteredSnapshot: ArchitectureSnapshot? {
        guard let snapshot else { return nil }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return snapshot }
        return snapshot.filtered(matching: query)
    }

    init(service: (any CodeAtlasIntelligenceServicing)? = nil) {
        self.service = service ?? MockCodeAtlasIntelligenceService()
    }

    func load() async {
        guard snapshot == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let repositories = try await backendClient.fetchRepositories()
            if let repository = repositories.first {
                backendRepositoryID = repository.id
                let map = try await backendClient.fetchRepositoryMap(repositoryID: repository.id)
                snapshot = ArchitectureSnapshot(backendMap: map, repository: repository)
            } else {
                snapshot = try await service.loadArchitecture()
            }
        } catch {
            snapshot = try? await service.loadArchitecture()
        }

        selectedFile = snapshot?.folders.firstFile
    }

    func select(_ file: ArchitectureFile) {
        withAnimation(.snappy) {
            selectedFile = file
            selectedFileContent = nil
        }

        guard let backendRepositoryID, let backendFileID = file.backendFileID else { return }
        Task {
            await loadFileContent(repositoryID: backendRepositoryID, fileID: backendFileID)
        }
    }

    private func loadFileContent(repositoryID: UUID, fileID: UUID) async {
        isLoadingFile = true
        defer { isLoadingFile = false }
        do {
            let content = try await backendClient.fetchRepositoryFile(repositoryID: repositoryID, fileID: fileID)
            selectedFileContent = content.content
        } catch {
            selectedFileContent = "Could not load file content: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class RefactoringAssistantViewModel: ObservableObject {
    @Published private(set) var recommendations: [RefactorRecommendation] = []
    @Published private(set) var appliedRecommendationIDs: Set<UUID> = []
    @Published var selectedFilter: RefactorFilter = .all
    @Published private(set) var isLoading = false

    private let service: any CodeAtlasIntelligenceServicing

    var filteredRecommendations: [RefactorRecommendation] {
        recommendations.filter { selectedFilter.matches($0) }
    }

    var highPriorityCount: Int {
        recommendations.filter { $0.priority == .high }.count
    }

    var averageMaintainabilityScore: Int {
        guard !recommendations.isEmpty else { return 100 }
        let total = recommendations.reduce(0) { $0 + $1.maintainabilityScore }
        return total / recommendations.count
    }

    var appliedCount: Int {
        appliedRecommendationIDs.count
    }

    init(service: (any CodeAtlasIntelligenceServicing)? = nil) {
        self.service = service ?? MockCodeAtlasIntelligenceService()
    }

    func load() async {
        guard recommendations.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        recommendations = (try? await service.generateRefactorPlan()) ?? []
        appliedRecommendationIDs.removeAll()
    }

    func toggleApplied(_ recommendation: RefactorRecommendation) {
        withAnimation(.snappy) {
            if appliedRecommendationIDs.contains(recommendation.id) {
                appliedRecommendationIDs.remove(recommendation.id)
            } else {
                appliedRecommendationIDs.insert(recommendation.id)
            }
        }
    }
}

@MainActor
final class PullRequestReviewViewModel: ObservableObject {
    @Published private(set) var summary: PullRequestSummary?
    @Published private(set) var decisionOverride: PullRequestApprovalStatus?
    @Published var selectedRiskFilter: PullRequestRiskFilter = .all
    @Published private(set) var isLoading = false

    private let service: any CodeAtlasIntelligenceServicing

    var displayedApprovalStatus: PullRequestApprovalStatus? {
        decisionOverride ?? summary?.approvalStatus
    }

    var filteredFiles: [PullRequestFile] {
        guard let summary else { return [] }
        return summary.changedFiles.filter { selectedRiskFilter.matches($0) }
    }

    var highRiskFileCount: Int {
        summary?.changedFiles.filter { $0.risk == .high }.count ?? 0
    }

    var totalLineDelta: Int {
        summary?.changedFiles.reduce(0) { $0 + $1.additions + $1.deletions } ?? 0
    }

    var reviewCommentCount: Int {
        summary?.comments.count ?? 0
    }

    init(service: (any CodeAtlasIntelligenceServicing)? = nil) {
        self.service = service ?? MockCodeAtlasIntelligenceService()
    }

    func load() async {
        guard summary == nil else { return }
        isLoading = true
        defer { isLoading = false }
        summary = try? await service.reviewPullRequest()
    }

    func approve() {
        withAnimation(.snappy) {
            decisionOverride = .approved
        }
    }

    func requestChanges() {
        withAnimation(.snappy) {
            decisionOverride = .changesRequested
        }
    }
}

@MainActor
final class AccountViewModel: ObservableObject {
    @Published private(set) var profile = AccountProfile.mock
    @Published private(set) var isGitHubConnected = false
    @Published private(set) var isUpdatingGitHub = false
    @Published private(set) var backendStatusMessage: String?

    private let backendClient = AccountBackendClient()
    private let tokenStore = CodeAtlasTokenStore()

    func loadGitHubConnection() async {
        guard !isUpdatingGitHub else { return }
        do {
            let connection = try await backendClient.fetchGitHubConnection()
            apply(connection)
            backendStatusMessage = "Backend connected"
        } catch {
            backendStatusMessage = "Backend unavailable: \(error.localizedDescription)"
        }
    }

    func connectGitHub() async {
        guard !isGitHubConnected, !isUpdatingGitHub else { return }
        isUpdatingGitHub = true
        defer { isUpdatingGitHub = false }

        do {
            let oauth = try await backendClient.startGitHubOAuth()
            if oauth.configured, let urlString = oauth.authorizationURL, let url = URL(string: urlString) {
                await UIApplication.shared.open(url)
                backendStatusMessage = "GitHub opened in Safari. After approving access, return here and tap Refresh."
            } else {
                let connection = try await backendClient.connectGitHub(mockAccountName: "codeatlas-demo")
                apply(connection)
                backendStatusMessage = oauth.message + " Using demo GitHub connection for now."
            }
        } catch {
            backendStatusMessage = "Could not connect GitHub: \(error.localizedDescription)"
        }
    }

    func disconnectGitHub() async {
        guard isGitHubConnected, !isUpdatingGitHub else { return }
        isUpdatingGitHub = true
        defer { isUpdatingGitHub = false }

        do {
            let connection = try await backendClient.disconnectGitHub()
            apply(connection)
            backendStatusMessage = "Disconnected through backend"
        } catch {
            backendStatusMessage = "Could not disconnect GitHub: \(error.localizedDescription)"
        }
    }

    func signOut() {
        do {
            try tokenStore.clear()
            backendStatusMessage = "Signed out and cleared saved tokens."
        } catch {
            backendStatusMessage = "Signed out, but token cleanup failed: \(error.localizedDescription)"
        }
    }

    private func apply(_ connection: AccountGitHubConnection) {
        withAnimation(.snappy) {
            isGitHubConnected = connection.connected
            profile = profile.updated(gitHubStatus: connection.connected ? .connected : .notConnected)
        }
    }
}

private struct BackendTokenResponse: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

private struct BackendAppleAuthPayload: Encodable {
    let identityToken: String
    let authorizationCode: String?
}

private struct CodeAtlasTokenStore {
    private let service = "com.codeatlas.tokens"
    private enum Key {
        static let accessToken = "accessToken"
        static let refreshToken = "refreshToken"
        static let expiresAt = "expiresAt"
    }

    func save(_ tokens: BackendTokenResponse) throws {
        try save(tokens.accessToken, for: Key.accessToken)
        try save(tokens.refreshToken, for: Key.refreshToken)
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        try save(ISO8601DateFormatter().string(from: expiresAt), for: Key.expiresAt)
    }

    func readAccessToken() throws -> String? {
        try readValue(for: Key.accessToken)
    }

    func clear() throws {
        try deleteValue(for: Key.accessToken)
        try deleteValue(for: Key.refreshToken)
        try deleteValue(for: Key.expiresAt)
    }

    private func save(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AccountBackendError.server("Keychain save failed with status \(status).")
        }
    }

    private func deleteValue(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccountBackendError.server("Keychain delete failed with status \(status).")
        }
    }

    private func readValue(for key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw AccountBackendError.server("Keychain read failed with status \(status).")
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct AccountGitHubConnection: Codable, Equatable {
    let connected: Bool
    let accountName: String?
    let scopes: [String]

    enum CodingKeys: String, CodingKey {
        case connected
        case accountName = "account_name"
        case scopes
    }
}

private struct AccountGitHubConnectPayload: Encodable {
    let mockAccountName: String
}

private struct GitHubOAuthStartResponse: Codable, Equatable {
    let configured: Bool
    let authorizationURL: String?
    let state: String?
    let message: String

    enum CodingKeys: String, CodingKey {
        case configured
        case authorizationURL = "authorization_url"
        case state
        case message
    }
}

private struct BackendRepository: Identifiable, Codable, Equatable {
    let id: UUID
    let provider: String
    let fullName: String
    let defaultBranch: String
    let indexingStatus: String
    let languages: [String: Int]
    let lastIndexedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case fullName = "full_name"
        case defaultBranch = "default_branch"
        case indexingStatus = "indexing_status"
        case languages
        case lastIndexedAt = "last_indexed_at"
    }
}

private struct BackendIndexingStatus: Codable, Equatable {
    let repositoryID: UUID
    let status: String
    let progressPercent: Int
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case repositoryID = "repository_id"
        case status
        case progressPercent = "progress_percent"
        case errorMessage = "error_message"
    }
}

private struct BackendRepositoryMap: Codable, Equatable {
    let repositoryID: UUID
    let root: BackendRepositoryMapNode
    let importantModules: [String]
    let entryPoints: [String]
    let edges: [BackendRepositoryMapEdge]

    enum CodingKeys: String, CodingKey {
        case repositoryID = "repository_id"
        case root
        case importantModules = "important_modules"
        case entryPoints = "entry_points"
        case edges
    }
}

private struct BackendRepositoryMapNode: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let path: String
    let kind: String
    let language: String?
    let children: [BackendRepositoryMapNode]
}

private struct BackendRepositoryMapEdge: Codable, Equatable {
    let sourcePath: String
    let targetPath: String
    let relationship: String

    enum CodingKeys: String, CodingKey {
        case sourcePath = "source_path"
        case targetPath = "target_path"
        case relationship
    }
}

private struct BackendRepositoryFileContent: Codable, Equatable {
    let id: UUID
    let path: String
    let language: String?
    let lineCount: Int
    let content: String

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case language
        case lineCount = "line_count"
        case content
    }
}

private struct BackendCodeReviewSummary: Codable, Equatable {
    let repositoryID: UUID
    let repositoryName: String
    let score: Int
    let analyzedFiles: Int
    let analyzedLines: Int
    let primaryFilePath: String
    let summary: String
    let snippet: String
    let issues: [BackendCodeReviewIssue]

    enum CodingKeys: String, CodingKey {
        case repositoryID = "repository_id"
        case repositoryName = "repository_name"
        case score
        case analyzedFiles = "analyzed_files"
        case analyzedLines = "analyzed_lines"
        case primaryFilePath = "primary_file_path"
        case summary
        case snippet
        case issues
    }
}

private struct BackendCodeReviewIssue: Codable, Equatable {
    let severity: String
    let title: String
    let detail: String
    let filePath: String
    let lineRange: String
    let category: String
    let snippet: String?

    enum CodingKeys: String, CodingKey {
        case severity
        case title
        case detail
        case filePath = "file_path"
        case lineRange = "line_range"
        case category
        case snippet
    }
}

private struct BackendRepositoryCreatePayload: Encodable {
    let provider: String
    let fullName: String
    let defaultBranch: String
}

private struct BackendChatPayload: Encodable {
    let question: String
}

private struct BackendErrorPayload: Decodable {
    let detail: String?
}

enum AccountBackendError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): message
        }
    }
}

private struct AccountBackendClient {
    private let baseURL = URL(string: "http://127.0.0.1:8000/api/v1")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func authenticateWithApple(identityToken: String, authorizationCode: String?) async throws -> BackendTokenResponse {
        try await send(
            "auth/apple",
            method: "POST",
            body: BackendAppleAuthPayload(identityToken: identityToken, authorizationCode: authorizationCode)
        )
    }

    func fetchRepositories() async throws -> [BackendRepository] {
        try await send("repositories", method: "GET", body: Optional<AccountGitHubConnectPayload>.none)
    }

    func createRepository(fullName: String) async throws -> BackendRepository {
        try await send(
            "repositories",
            method: "POST",
            body: BackendRepositoryCreatePayload(provider: "github", fullName: fullName, defaultBranch: "main")
        )
    }

    func deleteRepository(repositoryID: UUID) async throws {
        _ = try await perform("repositories/\(repositoryID.uuidString)", method: "DELETE", body: Optional<AccountGitHubConnectPayload>.none)
    }

    func startIndexing(repositoryID: UUID) async throws -> BackendIndexingStatus {
        let data = try await perform("repositories/\(repositoryID.uuidString)/index", method: "POST", body: Optional<AccountGitHubConnectPayload>.none)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AccountBackendError.server("Backend returned an invalid indexing response.")
        }

        let status = object["status"] as? String ?? "completed"
        let progress = object["progress_percent"] as? Int ?? 100
        let errorMessage = object["error_message"] as? String
        let responseRepositoryID = (object["repository_id"] as? String).flatMap(UUID.init(uuidString:)) ?? repositoryID
        return BackendIndexingStatus(
            repositoryID: responseRepositoryID,
            status: status,
            progressPercent: progress,
            errorMessage: errorMessage
        )
    }

    func fetchRepositoryMap(repositoryID: UUID) async throws -> BackendRepositoryMap {
        try await send("repositories/\(repositoryID.uuidString)/map", method: "GET", body: Optional<AccountGitHubConnectPayload>.none)
    }

    func fetchRepositoryFile(repositoryID: UUID, fileID: UUID) async throws -> BackendRepositoryFileContent {
        try await send("repositories/\(repositoryID.uuidString)/files/\(fileID.uuidString)", method: "GET", body: Optional<AccountGitHubConnectPayload>.none)
    }

    func reviewLatestRepository() async throws -> BackendCodeReviewSummary {
        let repositories = try await fetchRepositories()
        guard var repository = repositories.last else {
            throw AccountBackendError.server("Add a public GitHub repository in Repos first, then tap Start Indexing or run Review again.")
        }

        if repository.indexingStatus != "completed" {
            let status = try await startIndexing(repositoryID: repository.id)
            guard status.status == "completed" else {
                throw AccountBackendError.server(status.errorMessage ?? "Repository indexing did not complete yet. Try Review again after indexing finishes.")
            }
            repository = try await fetchRepositories().last ?? repository
        }

        return try await send("repositories/\(repository.id.uuidString)/review", method: "POST", body: Optional<AccountGitHubConnectPayload>.none)
    }

    func streamChat(question: String) async throws -> AsyncThrowingStream<String, Error> {
        let repositories = try await fetchRepositories()
        let repository: BackendRepository
        if let existingRepository = repositories.first {
            repository = existingRepository
        } else {
            repository = try await createRepository(fullName: "openai/example")
        }
        var request = URLRequest(url: baseURL.appending(path: "repositories/\(repository.id.uuidString)/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(BackendChatPayload(question: question))

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if let data = payload.data(using: .utf8), let token = try? JSONDecoder().decode(String.self, from: data) {
                            continuation.yield(token)
                        } else if payload.contains("citations") {
                            continuation.yield("\n\nBackend returned citations for this answer.")
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func fetchGitHubConnection() async throws -> AccountGitHubConnection {
        try await send("repositories/github/connection", method: "GET", body: Optional<AccountGitHubConnectPayload>.none)
    }

    func startGitHubOAuth() async throws -> GitHubOAuthStartResponse {
        try await send("repositories/github/oauth/start", method: "GET", body: Optional<AccountGitHubConnectPayload>.none)
    }

    func connectGitHub(mockAccountName: String) async throws -> AccountGitHubConnection {
        try await send(
            "repositories/github/connect",
            method: "POST",
            body: AccountGitHubConnectPayload(mockAccountName: mockAccountName)
        )
    }

    func disconnectGitHub() async throws -> AccountGitHubConnection {
        try await send("repositories/github/connection", method: "DELETE", body: Optional<AccountGitHubConnectPayload>.none)
    }

    private func send<Body: Encodable, Response: Decodable>(_ path: String, method: String, body: Body?) async throws -> Response {
        let data = try await perform(path, method: method, body: body)
        let decoder = JSONDecoder()
        return try decoder.decode(Response.self, from: data)
    }

    private func perform<Body: Encodable>(_ path: String, method: String, body: Body?) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let payload = try? JSONDecoder().decode(BackendErrorPayload.self, from: data), let detail = payload.detail {
                throw AccountBackendError.server(detail)
            }
            let message = String(data: data, encoding: .utf8) ?? "Backend request failed."
            throw AccountBackendError.server(message)
        }
        return data
    }
}

// MARK: - Screens

private struct CodeAtlasHomeScreen: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ProductHero(
                        title: "CodeAtlas",
                        subtitle: "Add a public GitHub repository, index its real files, then ask questions or explore the project structure.",
                        symbol: "map"
                    )

                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "How It Works", symbol: "list.number")
                        HomeStepCard(number: "1", title: "Add a repository", detail: "Go to Repos and enter a public GitHub project like pypa/sampleproject.", symbol: "folder.badge.plus")
                        HomeStepCard(number: "2", title: "Start indexing", detail: "CodeAtlas asks the backend to clone the repo and read supported source and documentation files.", symbol: "arrow.triangle.2.circlepath")
                        HomeStepCard(number: "3", title: "Ask or explore", detail: "Use Ask for questions and Explore for the file tree. Both use backend-indexed repository data.", symbol: "sparkle.magnifyingglass")
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "What Works Now", symbol: "checkmark.seal")
                        HomeCapabilityCard(title: "Public GitHub repos", detail: "Public repositories can be cloned and indexed. Private repos need OAuth in a later phase.", symbol: "chevron.left.forwardslash.chevron.right", tint: .green)
                        HomeCapabilityCard(title: "Repository chat", detail: "Ask uses the local backend and returns repository-grounded answers with citation metadata.", symbol: "bubble.left.and.text.bubble.right", tint: .blue)
                        HomeCapabilityCard(title: "Architecture map", detail: "Explore reads the backend repository map and displays a navigable file tree.", symbol: "point.3.connected.trianglepath.dotted", tint: .purple)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Advanced Tools", symbol: "wrench.and.screwdriver")
                        NavigationLink {
                            AICodeReviewScreen(viewModel: AICodeReviewViewModel())
                        } label: {
                            HomeToolRow(title: "AI Code Review", detail: "Reviews the indexed GitHub repository for security, reliability, and maintainability risks.", symbol: "checkmark.seal")
                        }
                        NavigationLink {
                            RefactoringAssistantScreen(viewModel: RefactoringAssistantViewModel())
                        } label: {
                            HomeToolRow(title: "Refactoring Assistant", detail: "Mock suggestions for cleaner architecture and readability.", symbol: "wand.and.sparkles")
                        }
                        NavigationLink {
                            PullRequestReviewScreen(viewModel: PullRequestReviewViewModel())
                        } label: {
                            HomeToolRow(title: "Pull Request Review", detail: "Mock PR risk summary, comments, and approval state.", symbol: "arrow.triangle.pull")
                        }
                    }
                }
                .screenPadding()
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("homeScrollView")
            .navigationTitle("Home")
        }
    }
}

struct AICodeReviewScreen: View {
    @StateObject var viewModel: AICodeReviewViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ProductHero(title: "AI Code Review", subtitle: "CodeAtlas pulls the indexed GitHub repository from the backend and reviews it for security, reliability, and maintainability risks.", symbol: "checkmark.seal")

                    if viewModel.isLoading {
                        LoadingPanel(title: "Reviewing indexed repository", detail: "Scanning real source files for secrets, crash-prone code, broad error handling, test gaps, and architecture risks.")
                    } else if let summary = viewModel.summary {
                        ReviewSummaryView(summary: summary)
                    } else {
                        if let errorMessage = viewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .panelStyle()
                        }

                        EmptyActionPanel(title: "Review your repository", detail: "Add a public GitHub repository in Repos, then run this review. If it is not indexed yet, CodeAtlas will index it first.", buttonTitle: "Review Indexed Repo", symbol: "play.circle") {
                            Task { await viewModel.analyze() }
                        }
                    }
                }
                .screenPadding()
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("reviewScrollView")
            .navigationTitle("Review")
            .toolbar {
                Button {
                    Task { await viewModel.analyze() }
                } label: {
                    Label("Analyze", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

struct AskYourCodeScreen: View {
    @StateObject var viewModel: AskYourCodeViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ProductHero(title: "Ask Your Code", subtitle: "Ask natural-language questions and get repository-grounded answers with file citations.", symbol: "sparkle.magnifyingglass")

                            ForEach(viewModel.messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .screenPadding()
                    }
                    .scrollIndicators(.visible)
                    .accessibilityIdentifier("askScrollView")
                    .onChange(of: viewModel.messages) { _, messages in
                        if let last = messages.last {
                            withAnimation(.snappy) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                AskInputBar(question: $viewModel.question, isStreaming: viewModel.isStreaming) {
                    Task { await viewModel.ask() }
                }
            }
            .navigationTitle("Ask")
        }
    }
}

private struct BackendRepositoriesScreen: View {
    @StateObject var viewModel: BackendRepositoriesViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ProductHero(title: "Repositories", subtitle: "This is where CodeAtlas learns about a project. Add a public GitHub repo, then index it so Ask and Explore can use its real files.", symbol: "folder.badge.gearshape")

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Step 1: Add a public GitHub repo", systemImage: "1.circle")
                            .font(.headline)
                        Text("Use the short GitHub name, not the full URL. Example: pypa/sampleproject")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        TextField("owner/repository", text: $viewModel.repositoryName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("backendRepositoryNameField")

                        HStack {
                            Button {
                                Task { await viewModel.addRepository() }
                            } label: {
                                Label("Add Repository", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isLoading)
                            .accessibilityIdentifier("backendAddRepositoryButton")

                            Button {
                                Task { await viewModel.load() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isLoading)
                        }

                        if viewModel.isLoading {
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView("Indexing repository")
                                Text("CodeAtlas is asking the backend to clone the public GitHub repo and read supported files. Small repos usually finish in a few seconds.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let errorMessage = viewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    .panelStyle()

                    if viewModel.repositories.isEmpty, !viewModel.isLoading {
                        EmptyActionPanel(title: "No repositories yet", detail: "Try pypa/sampleproject. It is a small public GitHub repo that CodeAtlas can clone and index.", buttonTitle: "Add Sample Repository", symbol: "folder.badge.plus") {
                            Task { await viewModel.addRepository() }
                        }
                    } else {
                        ForEach(viewModel.repositories) { repository in
                            BackendRepositoryCard(
                                repository: repository,
                                status: viewModel.indexingStatuses[repository.id],
                                reindex: {
                                    Task { await viewModel.startIndexing(repository) }
                                },
                                delete: {
                                    Task { await viewModel.deleteRepository(repository) }
                                }
                            )
                        }
                    }
                }
                .screenPadding()
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("backendRepositoriesScrollView")
            .navigationTitle("Repos")
            .task { await viewModel.load() }
        }
    }
}

struct ArchitectureExplorerScreen: View {
    @StateObject var viewModel: ArchitectureExplorerViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ProductHero(title: "Architecture Explorer", subtitle: "Visualize modules, entry points, dependencies, and file relationships in a codebase.", symbol: "point.3.connected.trianglepath.dotted")

                    if viewModel.isLoading {
                        LoadingPanel(title: "Mapping repository", detail: "Finding modules, entry points, and dependency edges.")
                    } else if let snapshot = viewModel.filteredSnapshot {
                        ArchitectureSearchField(text: $viewModel.searchText)
                        ArchitectureSnapshotView(
                            snapshot: snapshot,
                            selectedFile: viewModel.selectedFile,
                            selectedFileContent: viewModel.selectedFileContent,
                            isLoadingFile: viewModel.isLoadingFile,
                            selectFile: viewModel.select
                        )
                    }
                }
                .screenPadding()
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("exploreScrollView")
            .navigationTitle("Explore")
            .task { await viewModel.load() }
        }
    }
}

struct RefactoringAssistantScreen: View {
    @StateObject var viewModel: RefactoringAssistantViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ProductHero(title: "Refactoring Assistant", subtitle: "Find cleaner boundaries, duplicate logic, missing patterns, and readability improvements.", symbol: "wand.and.sparkles")

                    if viewModel.isLoading {
                        LoadingPanel(title: "Generating refactor plan", detail: "Checking duplication, coupling, naming, and maintainability risks.")
                    } else {
                        RefactorSummaryPanel(
                            totalCount: viewModel.recommendations.count,
                            highPriorityCount: viewModel.highPriorityCount,
                            appliedCount: viewModel.appliedCount,
                            maintainabilityScore: viewModel.averageMaintainabilityScore
                        )
                        RefactorFilterPicker(selection: $viewModel.selectedFilter)
                        RefactorSampleFilePanel()
                        if viewModel.filteredRecommendations.isEmpty {
                            ContentUnavailableView("No matching recommendations", systemImage: "line.3.horizontal.decrease.circle", description: Text("Choose a different filter to see more refactoring opportunities."))
                                .panelStyle()
                        } else {
                            ForEach(viewModel.filteredRecommendations) { recommendation in
                                RefactorRecommendationCard(
                                    recommendation: recommendation,
                                    isApplied: viewModel.appliedRecommendationIDs.contains(recommendation.id)
                                ) {
                                    viewModel.toggleApplied(recommendation)
                                }
                            }
                        }
                    }
                }
                .screenPadding()
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("refactorScrollView")
            .navigationTitle("Refactor")
            .toolbar {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Re-run Analysis", systemImage: "arrow.clockwise")
                }
            }
            .task { await viewModel.load() }
        }
    }
}

struct PullRequestReviewScreen: View {
    @StateObject var viewModel: PullRequestReviewViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ProductHero(title: "Pull Request Review", subtitle: "Summarize changes, highlight risky files, and generate review comments before merge.", symbol: "arrow.triangle.pull")

                    if viewModel.isLoading {
                        LoadingPanel(title: "Reviewing pull request", detail: "Comparing changed files and evaluating merge risk.")
                    } else if let summary = viewModel.summary {
                        PullRequestSummaryView(
                            summary: summary,
                            approvalStatus: viewModel.displayedApprovalStatus,
                            filteredFiles: viewModel.filteredFiles,
                            selectedRiskFilter: $viewModel.selectedRiskFilter,
                            highRiskFileCount: viewModel.highRiskFileCount,
                            totalLineDelta: viewModel.totalLineDelta,
                            reviewCommentCount: viewModel.reviewCommentCount,
                            approve: viewModel.approve,
                            requestChanges: viewModel.requestChanges
                        )
                    }
                }
                .screenPadding()
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("pullRequestScrollView")
            .navigationTitle("PR Review")
            .task { await viewModel.load() }
        }
    }
}

struct AccountScreen: View {
    @StateObject var viewModel: AccountViewModel
    @AppStorage("codeAtlasMockSignedIn") private var isSignedIn = true
    @AppStorage("codeAtlasAppearanceMode") private var appearanceModeRawValue = AccountAppearanceMode.system.rawValue
    @State private var showsSignOutConfirmation = false

    private var appearanceMode: Binding<AccountAppearanceMode> {
        Binding {
            AccountAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
        } set: { newValue in
            withAnimation(.snappy) {
                appearanceModeRawValue = newValue.rawValue
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AccountHeaderCard(profile: viewModel.profile)
                    AccountStatusGrid(profile: viewModel.profile)
                    GitHubConnectionCard(
                        isConnected: viewModel.isGitHubConnected,
                        isUpdating: viewModel.isUpdatingGitHub,
                        backendStatusMessage: viewModel.backendStatusMessage,
                        connect: { Task { await viewModel.connectGitHub() } },
                        disconnect: { Task { await viewModel.disconnectGitHub() } }
                    )

                    AccountSection(title: "Account", symbol: "person.crop.circle") {
                        AccountNavigationRow(destination: .manageAccount, title: "Manage Account", subtitle: "Name, email, and mock membership", symbol: "person.text.rectangle")
                        AccountNavigationRow(destination: .privacySecurity, title: "Privacy & Security", subtitle: "Repository data, tokens, and retention", symbol: "lock.shield")
                    }

                    AccountSection(title: "Preferences", symbol: "slider.horizontal.3") {
                        AppearancePicker(selection: appearanceMode)
                        AccountNavigationRow(destination: .about, title: "About CodeAtlas", subtitle: "Version, roadmap, and credits", symbol: "info.circle")
                        AccountNavigationRow(destination: .feedback, title: "Send Feedback", subtitle: "Share bugs, ideas, or App Store notes", symbol: "paperplane")
                    }

                    Button(role: .destructive) {
                        showsSignOutConfirmation = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("accountSignOutButton")
                }
                .screenPadding()
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("accountScrollView")
            .navigationTitle("Account")
            .task { await viewModel.loadGitHubConnection() }
            .navigationDestination(for: AccountDestination.self) { destination in
                AccountDetailScreen(destination: destination, profile: viewModel.profile)
            }
            .confirmationDialog("Sign out of CodeAtlas?", isPresented: $showsSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    viewModel.signOut()
                    withAnimation(.snappy) {
                        isSignedIn = false
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Version 1 uses a mock session. Signing out returns you to the welcome screen.")
            }
        }
    }
}

// MARK: - Components

private struct ProductHero: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                    Text("CodeAtlas")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LoadingPanel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}

private struct EmptyActionPanel: View {
    let title: String
    let detail: String
    let buttonTitle: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
            Button(action: action) {
                Label(buttonTitle, systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("primaryCardActionButton")
        }
        .panelStyle()
        .accessibilityIdentifier("emptyActionCard")
    }
}

private struct HomeStepCard: View {
    let number: String
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                Text(number)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panelStyle()
    }
}

private struct HomeCapabilityCard: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

private struct HomeToolRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
    }
}

private struct BackendRepositoryCard: View {
    let repository: BackendRepository
    let status: BackendIndexingStatus?
    let reindex: () -> Void
    let delete: () -> Void
    @State private var isShowingDeleteConfirmation = false

    private var displayStatus: String {
        status?.status ?? repository.indexingStatus.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var progress: Double {
        Double(status?.progressPercent ?? (repository.indexingStatus == "completed" ? 100 : 0)) / 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.fullName)
                        .font(.headline)
                    Text("Branch: \(repository.defaultBranch)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(displayStatus)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12), in: Capsule())
                    .foregroundStyle(.blue)
            }

            ProgressView(value: progress)
                .tint(.blue)

            if !repository.languages.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(repository.languages.sorted(by: { $0.value > $1.value }), id: \.key) { language, count in
                        Text("\(language) \(count)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
            }

            HStack(spacing: 12) {
                Button(action: reindex) {
                    Label("Start Indexing", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("backendStartIndexingButton")

                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("backendRemoveRepositoryButton")
            }
        }
        .panelStyle()
        .confirmationDialog(
            "Remove repository?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove \(repository.fullName)", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the repository and all indexed data from CodeAtlas. It does not delete anything from GitHub.")
        }
    }
}

private struct AccountHeaderCard: View {
    let profile: AccountProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.gradient)
                    Text(profile.initials)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 74, height: 74)
                .accessibilityLabel("Profile photo placeholder for \(profile.fullName)")

                VStack(alignment: .leading, spacing: 5) {
                    Text(profile.fullName)
                        .font(.title2.weight(.semibold))
                    Text(profile.email)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Label(profile.appleStatus.title, systemImage: profile.appleStatus.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(profile.appleStatus.tint)
                }
                Spacer()
            }

            Text("CodeAtlas keeps repository intelligence focused on the codebases you choose to index. V1 account data is local mock data for product QA.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
        .accessibilityIdentifier("accountHeaderCard")
    }
}

private struct AccountStatusGrid: View {
    let profile: AccountProfile

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            AccountMetricCard(title: "GitHub", value: profile.gitHubStatus.title, symbol: profile.gitHubStatus.symbol, tint: profile.gitHubStatus.tint)
            AccountMetricCard(title: "Member Since", value: profile.memberSince, symbol: "calendar", tint: .blue)
            AccountMetricCard(title: "App Version", value: profile.appVersion, symbol: "app.badge", tint: .purple)
            AccountMetricCard(title: "Health Score", value: "\(profile.projectHealthScore)/100", symbol: "heart.text.square", tint: .green)
        }
    }
}

private struct AccountMetricCard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .panelStyle()
        .accessibilityElement(children: .combine)
    }
}

private struct GitHubConnectionCard: View {
    let isConnected: Bool
    let isUpdating: Bool
    let backendStatusMessage: String?
    let connect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Label("GitHub Connection", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.headline)
                Spacer()
                Text(isConnected ? "Connected" : "Not Connected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isConnected ? .green : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((isConnected ? Color.green : Color.orange).opacity(0.14), in: Capsule())
            }

            Text(isConnected ? "GitHub access is connected through the backend for repository selection and indexing." : "Connect GitHub through the backend. If OAuth credentials are not configured yet, CodeAtlas uses a demo connection and shows the missing setup step.")
                .foregroundStyle(.secondary)

            if let backendStatusMessage {
                Label(backendStatusMessage, systemImage: backendStatusMessage.localizedCaseInsensitiveContains("unavailable") || backendStatusMessage.localizedCaseInsensitiveContains("could not") ? "wifi.exclamationmark" : "server.rack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(backendStatusMessage.localizedCaseInsensitiveContains("unavailable") || backendStatusMessage.localizedCaseInsensitiveContains("could not") ? .orange : .secondary)
                    .accessibilityIdentifier("accountBackendStatusLabel")
            }

            if isUpdating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(isConnected ? "Disconnecting GitHub" : "Connecting GitHub")
                        .font(.callout.weight(.medium))
                }
            } else {
                HStack {
                    Button(action: connect) {
                        Label("Connect GitHub", systemImage: "link.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConnected)
                    .accessibilityIdentifier("connectGitHubButton")

                    Button(role: .destructive, action: disconnect) {
                        Label("Disconnect GitHub", systemImage: "link.badge.minus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isConnected)
                    .accessibilityIdentifier("disconnectGitHubButton")
                }
            }
        }
        .panelStyle()
    }
}

private struct AccountSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, symbol: symbol)
            VStack(spacing: 0) {
                content
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

private struct AccountNavigationRow: View {
    let destination: AccountDestination
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("accountRow_\(destination.rawValue)")
    }
}

private struct AppearancePicker: View {
    @Binding var selection: AccountAppearanceMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Appearance", systemImage: "circle.lefthalf.filled")
                .font(.headline)
            Picker("Appearance", selection: $selection) {
                ForEach(AccountAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("appearancePicker")
        }
        .padding(16)
    }
}

private struct AccountDetailScreen: View {
    let destination: AccountDestination
    let profile: AccountProfile
    @State private var isLoading = true
    @State private var feedbackText = "CodeAtlas helped me understand the repository faster."
    @State private var feedbackSent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProductHero(title: destination.title, subtitle: destination.subtitle, symbol: destination.symbol)

                if isLoading {
                    LoadingPanel(title: "Loading \(destination.title)", detail: "Preparing secure mock account details.")
                } else {
                    detailContent
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .screenPadding()
        }
        .scrollIndicators(.visible)
        .navigationTitle(destination.shortTitle)
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.snappy) {
                isLoading = false
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch destination {
        case .manageAccount:
            VStack(alignment: .leading, spacing: 12) {
                AccountInfoRow(title: "Full Name", value: profile.fullName, symbol: "person")
                AccountInfoRow(title: "Email", value: profile.email, symbol: "envelope")
                AccountInfoRow(title: "Membership", value: "Member since \(profile.memberSince)", symbol: "calendar")
                Button {
                    feedbackSent = true
                } label: {
                    Label(feedbackSent ? "Mock Account Updated" : "Update Mock Account", systemImage: feedbackSent ? "checkmark.circle.fill" : "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
            }
            .panelStyle()
        case .privacySecurity:
            VStack(alignment: .leading, spacing: 12) {
                AccountInfoRow(title: "Repository Content", value: "Indexed only after explicit user action", symbol: "folder.badge.gearshape")
                AccountInfoRow(title: "Tokens", value: "Stored in Keychain in production", symbol: "key")
                AccountInfoRow(title: "Prompt Safety", value: "Repository files are treated as untrusted input", symbol: "shield.lefthalf.filled")
                AccountInfoRow(title: "Deletion", value: "Repository and account deletion controls planned for backend V2", symbol: "trash")
            }
            .panelStyle()
        case .about:
            VStack(alignment: .leading, spacing: 12) {
                AccountInfoRow(title: "Version", value: profile.appVersion, symbol: "app.badge")
                AccountInfoRow(title: "Project Health", value: "\(profile.projectHealthScore)/100", symbol: "heart.text.square")
                AccountInfoRow(title: "Focus", value: "Repository-grounded AI code intelligence", symbol: "sparkle.magnifyingglass")
                AccountInfoRow(title: "V1 Mode", value: "Mock data only, backend-ready architecture", symbol: "server.rack")
            }
            .panelStyle()
        case .feedback:
            VStack(alignment: .leading, spacing: 14) {
                TextEditor(text: $feedbackText)
                    .frame(minHeight: 150)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Feedback message")
                Button {
                    withAnimation(.snappy) {
                        feedbackSent = true
                    }
                } label: {
                    Label(feedbackSent ? "Feedback Sent" : "Send Feedback", systemImage: feedbackSent ? "checkmark.circle.fill" : "paperplane")
                }
                .buttonStyle(.borderedProminent)
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("sendFeedbackButton")
            }
            .panelStyle()
        }
    }
}

private struct AccountInfoRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ReviewSummaryView: View {
    let summary: CodeReviewSummary
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.repositoryName)
                        .font(.headline)
                    Text(summary.filePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                ScoreRing(score: summary.score)
            }
            .panelStyle()

            CodeSnippetBlock(text: summary.snippet)

            ForEach(summary.issues) { issue in
                CodeIssueCard(issue: issue) {
                    modelContext.insert(SavedCodeAtlasInsight(title: issue.title, detail: issue.detail, source: issue.filePath))
                }
            }
        }
    }
}

private struct CodeIssueCard: View {
    let issue: CodeIssue
    let saveAction: () -> Void
    @State private var isSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label(issue.severity.title, systemImage: issue.severity.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(issue.severity.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(issue.severity.tint.opacity(0.12), in: Capsule())
                Spacer()
                Button {
                    saveAction()
                    withAnimation(.snappy) {
                        isSaved = true
                    }
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(isSaved ? .blue : .secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("saveFindingButton")
                .accessibilityLabel(isSaved ? "Finding saved" : "Save finding")
            }

            Text(issue.title)
                .font(.headline)
            Text(issue.detail)
                .foregroundStyle(.secondary)
            Label("\(issue.filePath):\(issue.lineRange)", systemImage: "doc.text")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .panelStyle()
        .accessibilityIdentifier("codeIssueCard")
    }
}

private struct ChatBubble: View {
    let message: CodeChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
                .padding(14)
                .background(message.role == .user ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(message.role == .user ? .white : .primary)

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

private struct AskInputBar: View {
    @Binding var question: String
    let isStreaming: Bool
    let send: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Ask about authentication, payments, database config...", text: $question, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(isStreaming)

            Button(action: send) {
                Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
            }
            .accessibilityIdentifier("askSendButton")
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming)
        }
        .padding()
        .background(.bar)
    }
}

private struct ArchitectureSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search files, modules, or dependencies", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    withAnimation(.snappy) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear architecture search")
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("architectureSearchField")
    }
}

private struct ArchitectureSnapshotView: View {
    let snapshot: ArchitectureSnapshot
    let selectedFile: ArchitectureFile?
    let selectedFileContent: String?
    let isLoadingFile: Bool
    let selectFile: (ArchitectureFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Project Tree", symbol: "folder.badge.gearshape")
            if snapshot.folders.isEmpty {
                ContentUnavailableView("No matching files", systemImage: "magnifyingglass", description: Text("Try a module name, file name, language, or dependency."))
                    .panelStyle()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(snapshot.folders) { folder in
                        ArchitectureFolderRow(folder: folder, selectedFile: selectedFile, selectFile: selectFile)
                    }
                }
                .panelStyle()
            }

            if let selectedFile {
                ArchitectureFileDetailView(file: selectedFile, content: selectedFileContent, isLoadingContent: isLoadingFile)
            }

            SectionHeader(title: "Modules", symbol: "shippingbox")
            ForEach(snapshot.modules) { module in
                ArchitectureModuleCard(module: module)
            }

            SectionHeader(title: "Entry Points", symbol: "arrow.forward.to.line")
            ForEach(snapshot.entryPoints, id: \.self) { entryPoint in
                Label(entryPoint, systemImage: "play.circle")
                    .font(.body.monospaced())
                    .panelStyle()
            }

            SectionHeader(title: "Architecture Notes", symbol: "lightbulb")
            ForEach(snapshot.architectureNotes, id: \.self) { note in
                Label(note, systemImage: "point.3.connected.trianglepath.dotted")
                    .panelStyle()
            }

            SectionHeader(title: "Quality Notes", symbol: "checkmark.shield")
            ForEach(snapshot.riskNotes, id: \.self) { note in
                Label(note, systemImage: "checkmark.circle")
                    .panelStyle()
            }
        }
    }
}

private struct ArchitectureFolderRow: View {
    let folder: ArchitectureFolder
    let selectedFile: ArchitectureFile?
    let selectFile: (ArchitectureFile) -> Void
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(folder.folders) { child in
                    ArchitectureFolderRow(folder: child, selectedFile: selectedFile, selectFile: selectFile)
                        .padding(.leading, 12)
                }
                ForEach(folder.files) { file in
                    Button {
                        selectFile(file)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedFile?.id == file.id ? "doc.text.fill" : "doc.text")
                                .foregroundStyle(selectedFile?.id == file.id ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.callout.weight(.medium))
                                Text(file.path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                    .padding(.leading, 12)
                    .accessibilityLabel(file.path)
                    .accessibilityIdentifier("architectureFileButton_\(file.accessibilityKey)")
                }
            }
            .padding(.top, 8)
        } label: {
            Label(folder.name, systemImage: folder.symbol)
                .font(.headline)
        }
    }
}

private struct ArchitectureFileDetailView: View {
    let file: ArchitectureFile
    let content: String?
    let isLoadingContent: Bool

    private var displayedContent: String {
        if let content, !content.isEmpty {
            content
        } else {
            file.sampleCode
        }
    }

    private var discoveredSymbols: [String] {
        displayedContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                line.hasPrefix("struct ") ||
                line.hasPrefix("final class ") ||
                line.hasPrefix("class ") ||
                line.hasPrefix("actor ") ||
                line.hasPrefix("enum ") ||
                line.hasPrefix("func ") ||
                line.hasPrefix("private func ") ||
                line.hasPrefix("public func ") ||
                line.hasPrefix("init(")
            }
            .prefix(8)
            .map { String($0.prefix(90)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Selected File", systemImage: "doc.text.magnifyingglass")
                .font(.headline)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(file.name)
                        .font(.title3.weight(.semibold))
                    Text(file.path)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(file.language)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            LabeledContent("Purpose", value: file.purpose)
                .font(.callout)
            if !file.dependencies.isEmpty {
                ArchitectureTagSection(title: "Dependencies", symbol: "arrow.triangle.branch", values: file.dependencies)
            }
            if !file.relatedFiles.isEmpty {
                ArchitectureTagSection(title: "Related Files", symbol: "link", values: file.relatedFiles)
            }
            if !discoveredSymbols.isEmpty {
                ArchitectureTagSection(title: "Functions, Classes, and Types", symbol: "function", values: discoveredSymbols)
            }

            SectionHeader(title: "Architecture Explanation", symbol: "point.3.connected.trianglepath.dotted")
            Text("This file is part of the \(file.language) layer. It depends on \(file.dependencies.isEmpty ? "local project context" : file.dependencies.joined(separator: ", ")) and is related to \(file.relatedFiles.isEmpty ? "nearby files discovered in the repository map" : file.relatedFiles.joined(separator: ", ")).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SectionHeader(title: "Source Preview", symbol: "curlybraces")
            if isLoadingContent {
                ProgressView("Loading file content")
            } else {
                CodeSnippetBlock(text: displayedContent)
            }
        }
        .panelStyle()
        .accessibilityIdentifier("architectureFileDetail")
    }
}

private struct ArchitectureTagSection: View {
    let title: String
    let symbol: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
            FlowLayout(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}

private struct ArchitectureModuleCard: View {
    let module: ArchitectureModule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(module.name, systemImage: module.symbol)
                    .font(.headline)
                Spacer()
                Text("\(module.files) files")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(module.responsibility)
                .foregroundStyle(.secondary)
            Text("Depends on: \(module.dependencies.joined(separator: ", "))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}

private struct RefactorSummaryPanel: View {
    let totalCount: Int
    let highPriorityCount: Int
    let appliedCount: Int
    let maintainabilityScore: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Analysis Summary", symbol: "chart.bar.doc.horizontal")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                RefactorMetricTile(title: "Recommendations", value: "\(totalCount)", symbol: "list.bullet.rectangle")
                RefactorMetricTile(title: "High Priority", value: "\(highPriorityCount)", symbol: "flame", tint: .red)
                RefactorMetricTile(title: "Applied", value: "\(appliedCount)", symbol: "checkmark.circle", tint: .green)
                RefactorMetricTile(title: "Maintainability", value: "\(maintainabilityScore)/100", symbol: "gauge.with.dots.needle.bottom.50percent", tint: maintainabilityScore >= 80 ? .green : .orange)
            }
        }
        .panelStyle()
        .accessibilityIdentifier("refactorSummaryPanel")
    }
}

private struct RefactorMetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RefactorFilterPicker: View {
    @Binding var selection: RefactorFilter

    var body: some View {
        Picker("Refactor filter", selection: $selection) {
            ForEach(RefactorFilter.allCases) { filter in
                Label(filter.title, systemImage: filter.symbol)
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("refactorFilterPicker")
    }
}

private struct RefactorSampleFilePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Sample File", symbol: "doc.text.magnifyingglass")
            Text("Sources/Networking/APIClient.swift")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
            Text("The mock analyzer checks a realistic networking file for duplicate token refresh logic, oversized async methods, naming clarity, and architectural coupling.")
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}

private struct RefactorRecommendationCard: View {
    let recommendation: RefactorRecommendation
    let isApplied: Bool
    let toggleApplied: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Label(recommendation.priority.title, systemImage: recommendation.priority.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(recommendation.priority.tint)
                Spacer()
                Button(action: toggleApplied) {
                    Label(isApplied ? "Applied" : "Mark Applied", systemImage: isApplied ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("markRefactorAppliedButton")
            }

            Text(recommendation.title)
                .font(.headline)
            RefactorDetailRow(title: "Problem", text: recommendation.problem)
            RefactorDetailRow(title: "Why it matters", text: recommendation.whyItMatters)
            RefactorDetailRow(title: "Suggested solution", text: recommendation.suggestedSolution)

            FlowLayout(spacing: 8) {
                ForEach(recommendation.impacts, id: \.self) { impact in
                    Label(impact.title, systemImage: impact.symbol)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(impact.tint.opacity(0.14), in: Capsule())
                        .foregroundStyle(impact.tint)
                }
            }

            HStack(spacing: 10) {
                RefactorCompactMetric(title: "Maintainability", value: "\(recommendation.maintainabilityScore)/100", symbol: "gauge.with.dots.needle.bottom.50percent")
                RefactorCompactMetric(title: "Complexity", value: recommendation.estimatedComplexity, symbol: "slider.horizontal.3")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Before")
                    .font(.subheadline.weight(.semibold))
                CodeSnippetBlock(text: recommendation.beforeCode)
                Text("After")
                    .font(.subheadline.weight(.semibold))
                CodeSnippetBlock(text: recommendation.afterCode)
            }

            ForEach(recommendation.files, id: \.self) { file in
                Label(file, systemImage: "doc.text")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
        .accessibilityIdentifier("refactorRecommendationCard")
    }
}

private struct RefactorCompactMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct RefactorDetailRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PullRequestSummaryView: View {
    let summary: PullRequestSummary
    let approvalStatus: PullRequestApprovalStatus?
    let filteredFiles: [PullRequestFile]
    @Binding var selectedRiskFilter: PullRequestRiskFilter
    let highRiskFileCount: Int
    let totalLineDelta: Int
    let reviewCommentCount: Int
    let approve: () -> Void
    let requestChanges: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary.title)
                            .font(.headline)
                        if let approvalStatus {
                            Label(approvalStatus.title, systemImage: approvalStatus.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(approvalStatus.tint)
                        }
                    }
                    Spacer()
                    ScoreRing(score: summary.riskScore)
                }
                Text(summary.summary)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    PullRequestMetricTile(title: "Files Changed", value: "\(summary.changedFiles.count)", symbol: "doc.on.doc")
                    PullRequestMetricTile(title: "High Risk", value: "\(highRiskFileCount)", symbol: "exclamationmark.triangle", tint: .red)
                    PullRequestMetricTile(title: "Line Delta", value: "\(totalLineDelta)", symbol: "plus.forwardslash.minus", tint: .orange)
                    PullRequestMetricTile(title: "Comments", value: "\(reviewCommentCount)", symbol: "text.bubble", tint: .blue)
                }
                HStack {
                    Button(action: approve) {
                        Label("Approve", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("approvePullRequestButton")

                    Button(action: requestChanges) {
                        Label("Request Changes", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("requestPullRequestChangesButton")
                }
            }
            .panelStyle()

            PullRequestRiskFilterPicker(selection: $selectedRiskFilter)

            SectionHeader(title: "Changed Files", symbol: "doc.on.doc")
            if filteredFiles.isEmpty {
                ContentUnavailableView("No files for this risk", systemImage: "line.3.horizontal.decrease.circle", description: Text("Choose another risk filter to inspect the changed files."))
                    .panelStyle()
            } else {
                ForEach(filteredFiles) { file in
                    PullRequestFileCard(file: file)
                }
            }

            SectionHeader(title: "AI Review Comments", symbol: "text.bubble")
            ForEach(summary.comments) { comment in
                VStack(alignment: .leading, spacing: 8) {
                    Label(comment.severity.title, systemImage: comment.severity.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(comment.severity.tint)
                    Text("\(comment.filePath):\(comment.line)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                    Text(comment.message)
                }
                .panelStyle()
            }

            PullRequestInsightList(title: "Security Concerns", symbol: "lock.shield", items: summary.securityConcerns)
            PullRequestInsightList(title: "Performance Suggestions", symbol: "speedometer", items: summary.performanceSuggestions)
        }
    }
}

private struct PullRequestMetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PullRequestRiskFilterPicker: View {
    @Binding var selection: PullRequestRiskFilter

    var body: some View {
        Picker("Pull request risk filter", selection: $selection) {
            ForEach(PullRequestRiskFilter.allCases) { filter in
                Label(filter.title, systemImage: filter.symbol)
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("pullRequestRiskFilterPicker")
    }
}

private struct PullRequestFileCard: View {
    let file: PullRequestFile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(file.path)
                        .font(.footnote.monospaced())
                    HStack(spacing: 8) {
                        Label("+\(file.additions)", systemImage: "plus")
                            .foregroundStyle(.green)
                        Label("-\(file.deletions)", systemImage: "minus")
                            .foregroundStyle(.red)
                    }
                    .font(.caption.weight(.semibold))
                }
                Spacer()
                Text(file.risk.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(file.risk.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(file.diffLines) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text(line.prefix)
                            .frame(width: 16, alignment: .center)
                        Text("\(line.number)")
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                        Text(line.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(line.background, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .panelStyle()
    }
}

private struct PullRequestInsightList: View {
    let title: String
    let symbol: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, symbol: symbol)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "circle.fill")
                    .font(.callout)
                    .panelStyle()
            }
        }
    }
}

private struct ScoreRing: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.headline.monospacedDigit())
        }
        .frame(width: 58, height: 58)
        .accessibilityLabel("Score \(score)")
    }

    private var scoreColor: Color {
        switch score {
        case 80...100: .green
        case 55..<80: .orange
        default: .red
        }
    }
}

private struct CodeSnippetBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct SectionHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.title3.weight(.semibold))
    }
}

// MARK: - Models

struct AccountProfile: Equatable {
    let fullName: String
    let email: String
    let appleStatus: AppleSignInStatus
    let gitHubStatus: GitHubConnectionStatus
    let memberSince: String
    let appVersion: String
    let projectHealthScore: Int

    static let mock = AccountProfile(
        fullName: "CodeAtlas Demo User",
        email: "demo@codeatlas.local",
        appleStatus: .signedIn,
        gitHubStatus: .notConnected,
        memberSince: "July 2026",
        appVersion: "1.0.0 (Mock V1)",
        projectHealthScore: 92
    )

    var initials: String {
        fullName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }

    func updated(gitHubStatus: GitHubConnectionStatus) -> AccountProfile {
        AccountProfile(
            fullName: fullName,
            email: email,
            appleStatus: appleStatus,
            gitHubStatus: gitHubStatus,
            memberSince: memberSince,
            appVersion: appVersion,
            projectHealthScore: projectHealthScore
        )
    }
}

enum AppleSignInStatus: Equatable {
    case signedIn

    var title: String { "Signed in with Apple" }
    var symbol: String { "apple.logo" }
    var tint: Color { .primary }
}

enum GitHubConnectionStatus: Equatable {
    case connected
    case notConnected

    var title: String {
        switch self {
        case .connected: "Connected"
        case .notConnected: "Not Connected"
        }
    }

    var symbol: String {
        switch self {
        case .connected: "checkmark.circle.fill"
        case .notConnected: "exclamationmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .connected: .green
        case .notConnected: .orange
        }
    }
}

enum AccountAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AccountDestination: String, Hashable {
    case manageAccount
    case privacySecurity
    case about
    case feedback

    var title: String {
        switch self {
        case .manageAccount: "Manage Account"
        case .privacySecurity: "Privacy & Security"
        case .about: "About CodeAtlas"
        case .feedback: "Send Feedback"
        }
    }

    var shortTitle: String {
        switch self {
        case .privacySecurity: "Privacy"
        default: title
        }
    }

    var subtitle: String {
        switch self {
        case .manageAccount: "Review your mock profile, membership, and account settings."
        case .privacySecurity: "Understand how CodeAtlas should protect repository data and credentials."
        case .about: "Version details, project health, and the V1 product focus."
        case .feedback: "Send a mock feedback note for product QA."
        }
    }

    var symbol: String {
        switch self {
        case .manageAccount: "person.text.rectangle"
        case .privacySecurity: "lock.shield"
        case .about: "info.circle"
        case .feedback: "paperplane"
        }
    }
}

struct CodeReviewSummary: Equatable {
    let score: Int
    let repositoryName: String
    let filePath: String
    let analyzedLines: Int
    let issues: [CodeIssue]
    let snippet: String

    nonisolated init(score: Int, repositoryName: String, filePath: String, analyzedLines: Int, issues: [CodeIssue], snippet: String) {
        self.score = score
        self.repositoryName = repositoryName
        self.filePath = filePath
        self.analyzedLines = analyzedLines
        self.issues = issues
        self.snippet = snippet
    }

    fileprivate nonisolated init(backend: BackendCodeReviewSummary) {
        self.init(
            score: backend.score,
            repositoryName: backend.repositoryName,
            filePath: "\(backend.primaryFilePath) • \(backend.analyzedFiles) files • \(backend.analyzedLines) lines",
            analyzedLines: backend.analyzedLines,
            issues: backend.issues.map(CodeIssue.init(backend:)),
            snippet: backend.summary + "\n\n" + backend.snippet
        )
    }
}

struct CodeIssue: Identifiable, Equatable {
    let id = UUID()
    let severity: FindingSeverity
    let title: String
    let detail: String
    let filePath: String
    let lineRange: String
    let category: String

    nonisolated init(severity: FindingSeverity, title: String, detail: String, filePath: String, lineRange: String, category: String) {
        self.severity = severity
        self.title = title
        self.detail = detail
        self.filePath = filePath
        self.lineRange = lineRange
        self.category = category
    }

    fileprivate nonisolated init(backend: BackendCodeReviewIssue) {
        self.init(
            severity: FindingSeverity(rawBackendValue: backend.severity),
            title: backend.title,
            detail: backend.detail,
            filePath: backend.filePath,
            lineRange: backend.lineRange,
            category: backend.category
        )
    }
}

enum FindingSeverity: Equatable {
    case critical
    case warning
    case info

    nonisolated init(rawBackendValue: String) {
        switch rawBackendValue.lowercased() {
        case "critical":
            self = .critical
        case "warning":
            self = .warning
        default:
            self = .info
        }
    }

    var title: String {
        switch self {
        case .critical: "Critical"
        case .warning: "Warning"
        case .info: "Info"
        }
    }

    var symbol: String {
        switch self {
        case .critical: "xmark.octagon"
        case .warning: "exclamationmark.triangle"
        case .info: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .critical: .red
        case .warning: .orange
        case .info: .blue
        }
    }
}

struct CodeChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var content: String
}

struct ArchitectureSnapshot: Equatable {
    let modules: [ArchitectureModule]
    let entryPoints: [String]
    let riskNotes: [String]
    let architectureNotes: [String]
    let folders: [ArchitectureFolder]
}

private extension ArchitectureSnapshot {
    init(backendMap: BackendRepositoryMap, repository: BackendRepository) {
        let rootFolder = ArchitectureFolder(backendNode: backendMap.root)
        self.init(
            modules: backendMap.importantModules.map { module in
                ArchitectureModule(
                    name: module,
                    symbol: "folder",
                    responsibility: "Backend-discovered module from \(repository.fullName).",
                    files: rootFolder.countFiles(in: module),
                    dependencies: backendMap.edges.filter { $0.sourcePath.hasPrefix(module) }.map(\.targetPath)
                )
            },
            entryPoints: backendMap.entryPoints,
            riskNotes: [
                "Map loaded from the local FastAPI backend.",
                "Dependency edges are deterministic mock relationships until real parser output replaces them."
            ],
            architectureNotes: backendMap.edges.map { "\($0.sourcePath) → \($0.targetPath) (\($0.relationship))" },
            folders: rootFolder.folders.isEmpty && rootFolder.files.isEmpty ? [rootFolder] : rootFolder.folders + [ArchitectureFolder(name: "Files", symbol: "doc.text", files: rootFolder.files)]
        )
    }
}

private extension ArchitectureSnapshot {
    func filtered(matching query: String) -> ArchitectureSnapshot {
        let normalizedQuery = query.localizedCaseInsensitiveContains("/") ? query : query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredFolders = folders.compactMap { $0.filtered(matching: normalizedQuery) }
        let filteredModules = modules.filter { module in
            module.name.localizedCaseInsensitiveContains(normalizedQuery) ||
            module.responsibility.localizedCaseInsensitiveContains(normalizedQuery) ||
            module.dependencies.contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
        }
        return ArchitectureSnapshot(
            modules: filteredModules.isEmpty ? modules.filter { module in filteredFolders.contains { $0.name.localizedCaseInsensitiveContains(module.name) } } : filteredModules,
            entryPoints: entryPoints.filter { $0.localizedCaseInsensitiveContains(normalizedQuery) },
            riskNotes: riskNotes,
            architectureNotes: architectureNotes.filter { $0.localizedCaseInsensitiveContains(normalizedQuery) },
            folders: filteredFolders
        )
    }
}

private extension ArchitectureFolder {
    nonisolated init(backendNode: BackendRepositoryMapNode) {
        let childFolders = backendNode.children.filter { $0.kind == "folder" }.map(ArchitectureFolder.init(backendNode:))
        let childFiles = backendNode.children.filter { $0.kind == "file" }.map(ArchitectureFile.init(backendNode:))
        self.init(
            name: backendNode.name,
            symbol: backendNode.kind == "folder" ? "folder" : "doc.text",
            folders: childFolders,
            files: childFiles
        )
    }

    func countFiles(in module: String) -> Int {
        files.filter { $0.path.hasPrefix(module) }.count + folders.reduce(0) { $0 + $1.countFiles(in: module) }
    }

    func filtered(matching query: String) -> ArchitectureFolder? {
        let matchingFiles = files.filter { $0.matches(query) }
        let matchingFolders = folders.compactMap { $0.filtered(matching: query) }
        let folderMatches = name.localizedCaseInsensitiveContains(query)
        guard folderMatches || !matchingFiles.isEmpty || !matchingFolders.isEmpty else { return nil }
        return ArchitectureFolder(
            id: id,
            name: name,
            symbol: symbol,
            folders: folderMatches ? folders : matchingFolders,
            files: folderMatches ? files : matchingFiles
        )
    }
}

private extension ArchitectureFile {
    nonisolated init(backendNode: BackendRepositoryMapNode) {
        self.init(
            name: backendNode.name,
            path: backendNode.path,
            language: backendNode.language ?? "Text",
            purpose: "Indexed backend file discovered in the repository map.",
            dependencies: [],
            relatedFiles: [],
            sampleCode: "Select this file to load its indexed source from the backend.",
            backendFileID: UUID(uuidString: backendNode.id)
        )
    }
}

struct ArchitectureFolder: Identifiable, Equatable {
    let id: UUID
    let name: String
    let symbol: String
    var folders: [ArchitectureFolder]
    var files: [ArchitectureFile]

    nonisolated init(id: UUID = UUID(), name: String, symbol: String, folders: [ArchitectureFolder] = [], files: [ArchitectureFile] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.folders = folders
        self.files = files
    }
}

struct ArchitectureFile: Identifiable, Equatable {
    let id: UUID
    let name: String
    let path: String
    let language: String
    let purpose: String
    let dependencies: [String]
    let relatedFiles: [String]
    let sampleCode: String
    let backendFileID: UUID?

    nonisolated init(
        id: UUID = UUID(),
        name: String,
        path: String,
        language: String,
        purpose: String,
        dependencies: [String],
        relatedFiles: [String],
        sampleCode: String,
        backendFileID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.language = language
        self.purpose = purpose
        self.dependencies = dependencies
        self.relatedFiles = relatedFiles
        self.sampleCode = sampleCode
        self.backendFileID = backendFileID
    }

    var accessibilityKey: String {
        path.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }

    func matches(_ query: String) -> Bool {
        name.localizedCaseInsensitiveContains(query) ||
        path.localizedCaseInsensitiveContains(query) ||
        language.localizedCaseInsensitiveContains(query) ||
        purpose.localizedCaseInsensitiveContains(query) ||
        dependencies.contains { $0.localizedCaseInsensitiveContains(query) } ||
        relatedFiles.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct ArchitectureModule: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let symbol: String
    let responsibility: String
    let files: Int
    let dependencies: [String]
}

struct RefactorRecommendation: Identifiable, Equatable {
    let id: UUID
    let priority: RecommendationPriority
    let title: String
    let problem: String
    let whyItMatters: String
    let suggestedSolution: String
    let beforeCode: String
    let afterCode: String
    let impacts: [RefactorImpact]
    let files: [String]
    let maintainabilityScore: Int
    let estimatedComplexity: String

    nonisolated init(
        id: UUID = UUID(),
        priority: RecommendationPriority,
        title: String,
        problem: String,
        whyItMatters: String,
        suggestedSolution: String,
        beforeCode: String,
        afterCode: String,
        impacts: [RefactorImpact],
        files: [String],
        maintainabilityScore: Int = 78,
        estimatedComplexity: String = "Medium"
    ) {
        self.id = id
        self.priority = priority
        self.title = title
        self.problem = problem
        self.whyItMatters = whyItMatters
        self.suggestedSolution = suggestedSolution
        self.beforeCode = beforeCode
        self.afterCode = afterCode
        self.impacts = impacts
        self.files = files
        self.maintainabilityScore = maintainabilityScore
        self.estimatedComplexity = estimatedComplexity
    }
}

enum RecommendationPriority: Equatable {
    case high
    case medium
    case low

    var title: String {
        switch self {
        case .high: "High priority"
        case .medium: "Medium priority"
        case .low: "Low priority"
        }
    }

    var symbol: String {
        switch self {
        case .high: "flame"
        case .medium: "circle.lefthalf.filled"
        case .low: "leaf"
        }
    }

    var tint: Color {
        switch self {
        case .high: .red
        case .medium: .orange
        case .low: .green
        }
    }
}

enum RefactorFilter: String, CaseIterable, Identifiable {
    case all
    case highPriority
    case maintainability
    case performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .highPriority: "High"
        case .maintainability: "Maintain"
        case .performance: "Perf"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .highPriority: "flame"
        case .maintainability: "wrench.adjustable"
        case .performance: "speedometer"
        }
    }

    func matches(_ recommendation: RefactorRecommendation) -> Bool {
        switch self {
        case .all:
            true
        case .highPriority:
            recommendation.priority == .high
        case .maintainability:
            recommendation.impacts.contains(.maintainability)
        case .performance:
            recommendation.impacts.contains(.performance)
        }
    }
}

enum RefactorImpact: Equatable, Hashable {
    case performance
    case readability
    case maintainability

    var title: String {
        switch self {
        case .performance: "Performance"
        case .readability: "Readability"
        case .maintainability: "Maintainability"
        }
    }

    var symbol: String {
        switch self {
        case .performance: "speedometer"
        case .readability: "text.alignleft"
        case .maintainability: "wrench.adjustable"
        }
    }

    var tint: Color {
        switch self {
        case .performance: .blue
        case .readability: .indigo
        case .maintainability: .green
        }
    }
}

struct PullRequestSummary: Equatable {
    let title: String
    let riskScore: Int
    let summary: String
    let approvalStatus: PullRequestApprovalStatus
    let changedFiles: [PullRequestFile]
    let comments: [PullRequestComment]
    let securityConcerns: [String]
    let performanceSuggestions: [String]
}

enum PullRequestRiskFilter: String, CaseIterable, Identifiable {
    case all
    case high
    case medium
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .high: "exclamationmark.triangle"
        case .medium: "circle.lefthalf.filled"
        case .low: "checkmark.shield"
        }
    }

    func matches(_ file: PullRequestFile) -> Bool {
        switch self {
        case .all:
            true
        case .high:
            file.risk == .high
        case .medium:
            file.risk == .medium
        case .low:
            file.risk == .low
        }
    }
}

struct PullRequestFile: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let additions: Int
    let deletions: Int
    let risk: PullRequestRisk
    let diffLines: [PullRequestDiffLine]
}

struct PullRequestDiffLine: Identifiable, Equatable {
    enum Kind: Equatable {
        case added
        case removed
        case context
    }

    let id = UUID()
    let kind: Kind
    let number: Int
    let text: String

    var prefix: String {
        switch kind {
        case .added: "+"
        case .removed: "-"
        case .context: " "
        }
    }

    var background: Color {
        switch kind {
        case .added: .green.opacity(0.13)
        case .removed: .red.opacity(0.13)
        case .context: .secondary.opacity(0.08)
        }
    }
}

struct PullRequestComment: Identifiable, Equatable {
    let id = UUID()
    let filePath: String
    let line: Int
    let severity: FindingSeverity
    let message: String
}

enum PullRequestApprovalStatus: Equatable {
    case approved
    case changesRequested
    case pending

    var title: String {
        switch self {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .pending: "Pending review"
        }
    }

    var symbol: String {
        switch self {
        case .approved: "checkmark.seal.fill"
        case .changesRequested: "xmark.seal.fill"
        case .pending: "clock.badge.questionmark"
        }
    }

    var tint: Color {
        switch self {
        case .approved: .green
        case .changesRequested: .red
        case .pending: .orange
        }
    }
}

enum PullRequestRisk: Equatable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var tint: Color {
        switch self {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }
}

// MARK: - Layout Helpers

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangeSubviews(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> [FlowRow] {
        let maxWidth = proposal.width ?? 320
        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let spacingWidth = currentItems.isEmpty ? CGFloat.zero : spacing
            if currentWidth + spacingWidth + size.width > maxWidth, !currentItems.isEmpty {
                rows.append(FlowRow(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = []
                currentWidth = 0
                currentHeight = 0
            }

            currentItems.append(FlowItem(subview: subview, size: size))
            currentWidth += (currentItems.count == 1 ? 0 : spacing) + size.width
            currentHeight = max(currentHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, width: currentWidth, height: currentHeight))
        }
        return rows
    }

    private struct FlowItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct FlowRow {
        let items: [FlowItem]
        let width: CGFloat
        let height: CGFloat
    }
}

private extension Array where Element == ArchitectureFolder {
    var firstFile: ArchitectureFile? {
        for folder in self {
            if let file = folder.files.first {
                return file
            }
            if let file = folder.folders.firstFile {
                return file
            }
        }
        return nil
    }
}

// MARK: - Styling

private extension View {
    func panelStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    func screenPadding() -> some View {
        self
            .padding(20)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    CodeAtlasProductRootView()
        .modelContainer(for: [AtlasProgress.self, DocumentAnalysis.self, SavedCodeAtlasInsight.self], inMemory: true)
}
