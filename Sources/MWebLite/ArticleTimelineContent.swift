import SwiftUI
import MWebCore

/// The date and optional mosaic keep their columns while the excerpt uses the
/// remaining space. The parent owns selection and the full-row mouse target.
struct ArticleTimelineContent: View {
    let article: MWebArticle
    let title: String
    let libraryRoot: URL?
    let width: CGFloat
    var showsDate = true

    private var compact: Bool { width < 250 }
    private let dateWidth: CGFloat = 36
    private var gap: CGFloat { compact ? 6 : 8 }
    private var imageSide: CGFloat { min(88, max(48, (width - dateWidth - gap * 2) * 0.34)) }

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            date
                .frame(width: dateWidth, alignment: .leading)
            if let root = libraryRoot, !article.imageReferences.isEmpty {
                ArticleImageMosaic(
                    references: Array(article.imageReferences.prefix(4)),
                    documentURL: root.appendingPathComponent("docs/\(article.id).md"),
                    libraryRoot: root
                )
                .frame(width: imageSide, height: imageSide)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                }
                if !article.excerpt.isEmpty {
                    Text(article.excerpt)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var date: some View {
        if showsDate, let date = article.createdAt {
            day(date)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(date.formatted(.dateTime.year().month(.abbreviated).day().locale(L10n.current.locale)))
        } else {
            Color.clear.frame(height: 1).accessibilityHidden(true)
        }
    }

    private func day(_ date: Date) -> some View {
        Text(String(format: "%02d", Calendar.current.component(.day, from: date)))
            .font(.system(size: 23, weight: .regular, design: .rounded))
            .monospacedDigit()
            .fixedSize()
    }
}

private struct ArticleImageMosaic: View {
    let references: [String]
    let documentURL: URL
    let libraryRoot: URL

    var body: some View {
        HStack(spacing: 2) {
            if references.count == 1 {
                tile(0)
            } else if references.count == 2 {
                tile(0)
                tile(1)
            } else if references.count == 3 {
                tile(0)
                VStack(spacing: 2) {
                    tile(1)
                    tile(2)
                }
            } else {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        tile(0)
                        tile(1)
                    }
                    HStack(spacing: 2) {
                        tile(2)
                        tile(3)
                    }
                }
            }
        }
    }

    private func tile(_ index: Int) -> some View {
        ArticleThumbnail(reference: references[index], documentURL: documentURL, libraryRoot: libraryRoot)
    }
}
