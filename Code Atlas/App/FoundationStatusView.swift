//
//  FoundationStatusView.swift
//  Code Atlas
//

import SwiftUI

struct FoundationStatusView: View {
    @EnvironmentObject private var container: AppContainer

    private let milestones: [FoundationMilestone] = [
        FoundationMilestone(title: "Product requirements", detail: "Focused repository AI with cited answers.", isComplete: true),
        FoundationMilestone(title: "iOS module boundaries", detail: "Core, Authentication, Networking, Repositories, and DesignSystem are separated.", isComplete: true),
        FoundationMilestone(title: "Secure token storage", detail: "Keychain abstraction is ready for Sign in with Apple.", isComplete: true),
        FoundationMilestone(title: "Backend contracts", detail: "FastAPI routes, schema, Docker Compose, and tests are scaffolded.", isComplete: true),
        FoundationMilestone(title: "GitHub ingestion", detail: "Phase 2 will add provider authorization and indexing workers.", isComplete: false),
        FoundationMilestone(title: "RAG answers", detail: "Phase 3 will add embeddings, retrieval, streaming, and citations.", isComplete: false)
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image("CodeAtlasLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        Text("CodeAtlas Foundation")
                            .font(.title2.weight(.bold))

                        Text("Environment: \(container.environment.apiBaseURL.absoluteString)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 8)
                }

                Section("Phase 1 Progress") {
                    ForEach(milestones) { milestone in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: milestone.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(milestone.isComplete ? .green : .secondary)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(milestone.title)
                                    .font(.headline)
                                Text(milestone.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Foundation")
        }
    }
}

private struct FoundationMilestone: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let isComplete: Bool
}

#Preview {
    FoundationStatusView()
        .environmentObject(AppContainer())
}
