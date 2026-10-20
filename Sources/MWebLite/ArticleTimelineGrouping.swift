import Foundation
import MWebCore

/// Adds date labels to consecutive visible runs without changing article order.
enum ArticleTimelineGrouping {
    enum Heading: Equatable {
        case month(Date)
        case undated
    }

    struct Entry: Identifiable {
        let article: MWebArticle
        let yearHeading: Date?
        let heading: Heading?
        let showsDate: Bool
        var id: String { article.id }
    }

    static func entries(articles: [MWebArticle], calendar: Calendar = .current) -> [Entry] {
        var entries: [Entry] = []
        var previousDate: Date?
        for article in articles {
            let date = article.modifiedAt ?? article.createdAt
            let yearHeading: Date?
            let heading: Heading?
            let showsDate: Bool
            if let date {
                let sameYear = previousDate.map { calendar.isDate(date, equalTo: $0, toGranularity: .year) } ?? false
                let sameMonth = previousDate.map { calendar.isDate(date, equalTo: $0, toGranularity: .month) } ?? false
                yearHeading = sameYear ? nil : date
                heading = sameMonth ? nil : .month(date)
                showsDate = !(previousDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false)
            } else {
                yearHeading = nil
                heading = entries.isEmpty || previousDate != nil ? .undated : nil
                showsDate = false
            }
            entries.append(Entry(article: article, yearHeading: yearHeading, heading: heading, showsDate: showsDate))
            previousDate = date
        }
        return entries
    }
}
