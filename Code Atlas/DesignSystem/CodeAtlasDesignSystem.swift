//
//  CodeAtlasDesignSystem.swift
//  Code Atlas
//

import SwiftUI

enum CodeAtlasColor {
    static let navy = Color(red: 0.08, green: 0.13, blue: 0.24)
    static let teal = Color(red: 0.08, green: 0.55, blue: 0.60)
    static let amber = Color(red: 0.91, green: 0.62, blue: 0.18)
}

enum CodeAtlasSpacing {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 20
}

struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
