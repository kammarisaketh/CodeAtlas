//
//  Item.swift
//  Code Atlas
//
//  Created by Saketh Kammari on 7/23/26.
//

import Foundation
import SwiftData

@Model
final class AtlasProgress {
    @Attribute(.unique) var topicID: String
    var isComplete: Bool
    var updatedAt: Date

    init(topicID: String, isComplete: Bool = false, updatedAt: Date = Date()) {
        self.topicID = topicID
        self.isComplete = isComplete
        self.updatedAt = updatedAt
    }
}

@Model
final class DocumentAnalysis {
    var fileName: String
    var summary: String
    var recommendations: String
    var wordCount: Int
    var codeSignalCount: Int
    var createdAt: Date

    init(
        fileName: String,
        summary: String,
        recommendations: String,
        wordCount: Int,
        codeSignalCount: Int,
        createdAt: Date = Date()
    ) {
        self.fileName = fileName
        self.summary = summary
        self.recommendations = recommendations
        self.wordCount = wordCount
        self.codeSignalCount = codeSignalCount
        self.createdAt = createdAt
    }
}

@Model
final class SavedCodeAtlasInsight {
    var title: String
    var detail: String
    var source: String
    var createdAt: Date

    init(title: String, detail: String, source: String, createdAt: Date = Date()) {
        self.title = title
        self.detail = detail
        self.source = source
        self.createdAt = createdAt
    }
}
