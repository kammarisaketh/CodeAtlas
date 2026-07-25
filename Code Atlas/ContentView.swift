//
//  ContentView.swift
//  Code Atlas
//
//  Created by Saketh Kammari on 7/23/26.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        CodeAtlasProductRootView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [AtlasProgress.self, DocumentAnalysis.self, SavedCodeAtlasInsight.self], inMemory: true)
}
