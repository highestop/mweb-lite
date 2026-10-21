import Foundation

public struct MWebCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let parentID: String?
    public let sort: Int64
    public let sortType: Int64
    public let categoryType: Int64
}

public struct MWebArticle: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let excerpt: String
    public let modifiedAt: Date?
    public let createdAt: Date?
    public let categoryIDs: [String]
    public let isTrashed: Bool
    public let isPinned: Bool
    public let sort: Int64
    public let isAvailable: Bool
    public let imageReferences: [String]

    public init(id: String, title: String, excerpt: String, modifiedAt: Date?, createdAt: Date?,
                categoryIDs: [String], isTrashed: Bool, isPinned: Bool, sort: Int64,
                isAvailable: Bool, imageReferences: [String] = []) {
        self.id = id
        self.title = title
        self.excerpt = excerpt
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.categoryIDs = categoryIDs
        self.isTrashed = isTrashed
        self.isPinned = isPinned
        self.sort = sort
        self.isAvailable = isAvailable
        self.imageReferences = imageReferences
    }

    /// Refreshes the edited row without rereading every document in the library.
    public func updating(document: MWebDocument) -> MWebArticle {
        guard document.articleID == id else { return self }
        let summary = MWebLibrary.summary(document.content)
        return MWebArticle(id: id, title: summary.title, excerpt: summary.excerpt,
                           modifiedAt: document.modifiedAt, createdAt: createdAt,
                           categoryIDs: categoryIDs, isTrashed: isTrashed, isPinned: isPinned,
                           sort: sort, isAvailable: true,
                           imageReferences: MarkdownImageReferences.firstImages(in: document.content))
    }
}

public struct LibraryIndex: Sendable {
    public let categories: [MWebCategory]
    public let articles: [MWebArticle]
}

public struct MWebDocument: Sendable {
    public let articleID: String
    public let title: String
    public let content: String
    public let fileURL: URL
    public let modifiedAt: Date?
    public let lastBackupURL: URL?

    let originalData: Data
    let metadataFingerprint: String
    let libraryURL: URL
}

public enum MWebLibraryError: LocalizedError {
    case invalidLibrary(String)
    case database(String)
    case missingArticle
    case missingCategory
    case invalidCategory(String)
    case trashedArticle
    case invalidDocument(String)
    case conflict
    case recoveryRequired(URL)
    case creationConflict
    case creationRecoveryRequired(documentURL: URL, backupURL: URL)

    public var errorDescription: String? {
        switch self {
        case .invalidLibrary(let detail):
            return L10n.format("Could not open the library: %@", detail)
        case .database(let detail):
            return L10n.format("Library database operation failed: %@", detail)
        case .missingArticle:
            return L10n.string("This article is no longer in the library. Refresh the library.")
        case .missingCategory:
            return L10n.string("The selected category no longer exists. Refresh the library and try again.")
        case .invalidCategory(let detail):
            return L10n.format("Could not change the category: %@", detail)
        case .trashedArticle:
            return L10n.string("This article is in the trash and cannot be edited here.")
        case .invalidDocument(let detail):
            return L10n.format("Could not read the article: %@", detail)
        case .conflict:
            return L10n.string("This article was changed by MWeb or another app. Your edits are still in this window. Reload the article before merging your changes.")
        case .recoveryRequired(let backupURL):
            return L10n.format("Saving and restoring the original file both failed. The original text and database are backed up at %@. Keep a copy of your current edits.", backupURL.path)
        case .creationConflict:
            return L10n.string("The new article ID conflicts with existing data. Try again. Existing data was not changed.")
        case .creationRecoveryRequired(let documentURL, let backupURL):
            return L10n.format("Article creation failed and the file could not be cleaned up: %@. The database backup is at %@. Keep this file.", documentURL.path, backupURL.path)
        }
    }
}
