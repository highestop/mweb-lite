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
    case trashedArticle
    case invalidDocument(String)
    case conflict
    case recoveryRequired(URL)
    case creationConflict
    case creationRecoveryRequired(documentURL: URL, backupURL: URL)

    public var errorDescription: String? {
        switch self {
        case .invalidLibrary(let detail):
            return "无法打开文库：\(detail)"
        case .database(let detail):
            return "文库数据库操作失败：\(detail)"
        case .missingArticle:
            return "这篇文章已不在文库中，请刷新文库。"
        case .missingCategory:
            return "所选分类已不存在，请刷新文库后重试。"
        case .trashedArticle:
            return "这篇文章已被移入废纸篓，无法在此编辑。"
        case .invalidDocument(let detail):
            return "无法读取文章：\(detail)"
        case .conflict:
            return "文章已被 MWeb 或其他程序修改。当前编辑内容仍保留，请先重新载入，再合并修改。"
        case .recoveryRequired(let backupURL):
            return "保存未完成，恢复原文件也未成功。原文和数据库已备份到 \(backupURL.path)，请先保留当前编辑内容。"
        case .creationConflict:
            return "新文章标识与已有数据冲突，请重试。已有数据没有修改。"
        case .creationRecoveryRequired(let documentURL, let backupURL):
            return "新建文章未完成，文件无法自动清理：\(documentURL.path)。数据库备份位于 \(backupURL.path)，请先保留此文件。"
        }
    }
}
