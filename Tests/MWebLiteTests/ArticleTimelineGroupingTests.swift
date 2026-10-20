import Foundation
import XCTest
import CaseReporting
import MWebCore
@testable import MWebLite

final class ArticleTimelineGroupingTests: CaseReportingTestCase {
    func test_DATE_001_VisibleRunsUseLocalMonthsAndDaysWithoutReordering() throws {
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let articles = [
            article("pinned-december", modified: "2026-02-01T08:00:00Z",
                    created: "2025-12-31T15:59:00Z", pinned: true, sort: 99),
            article("january-first", created: "2025-12-31T16:01:00Z"),
            article("same-local-day", created: "2026-01-01T14:00:00Z"),
            article("next-local-day", created: "2026-01-01T16:00:00Z"),
            article("repeated-day", created: "2025-12-31T16:30:00Z"),
            article("repeated-month", created: "2025-12-30T16:00:00Z"),
            article("modified-only-undated", modified: "2026-03-01T08:00:00Z"),
            article("undated-second"),
            article("created-without-modified", created: "2026-01-01T08:00:00Z"),
            article("created-wins", modified: "2026-02-01T08:00:00Z", created: "2026-01-01T09:00:00Z")
        ]

        let entries = ArticleTimelineGrouping.entries(articles: articles, calendar: shanghai)

        XCTAssertEqual(entries.map(\.id), articles.map(\.id), "Grouping annotates the supplied order without applying pin or sort metadata")
        XCTAssertEqual(entries.map(\.article), articles)
        XCTAssertEqual(entries.map(\.showsDate), [true, true, false, true, true, true, false, false, true, false])
        XCTAssertEqual(entries.map(\.yearHeading), [
            date("2025-12-31T15:59:00Z"), date("2025-12-31T16:01:00Z"),
            nil, nil, nil, date("2025-12-30T16:00:00Z"),
            nil, nil, date("2026-01-01T08:00:00Z"), nil
        ], "A year heading starts each local year run, including a return to an earlier year")
        XCTAssertEqual(entries.map(\.heading), [
            .month(date("2025-12-31T15:59:00Z")),
            .month(date("2025-12-31T16:01:00Z")),
            nil, nil, nil,
            .month(date("2025-12-30T16:00:00Z")),
            .undated, nil,
            .month(date("2026-01-01T08:00:00Z")),
            nil
        ])
        XCTAssertTrue(ArticleTimelineGrouping.entries(articles: [], calendar: shanghai).isEmpty)
        let undated = ArticleTimelineGrouping.entries(articles: [articles[6], articles[7]], calendar: shanghai)
        XCTAssertEqual(undated.map(\.yearHeading), [nil, nil])
        XCTAssertEqual(undated.map(\.heading), [.undated, nil])
        XCTAssertEqual(undated.map(\.showsDate), [false, false])
        XCTAssertNil(undated[0].article.createdAt)
        XCTAssertNotNil(undated[0].article.modifiedAt, "A modification date must not supply a missing creation date")

        let editedArticles = articles.map {
            article($0.id, modified: "2030-07-01T08:00:00Z",
                    created: $0.createdAt.map { ISO8601DateFormatter().string(from: $0) },
                    pinned: $0.isPinned, sort: $0.sort)
        }
        let afterEdit = ArticleTimelineGrouping.entries(articles: editedArticles, calendar: shanghai)
        XCTAssertEqual(afterEdit.map(\.id), entries.map(\.id))
        XCTAssertEqual(afterEdit.map(\.yearHeading), entries.map(\.yearHeading))
        XCTAssertEqual(afterEdit.map(\.heading), entries.map(\.heading))
        XCTAssertEqual(afterEdit.map(\.showsDate), entries.map(\.showsDate),
                       "Changing modification dates must not change creation-date labels or undated rows")

        let filtered = ArticleTimelineGrouping.entries(articles: [articles[2], articles[3]], calendar: shanghai)
        XCTAssertEqual(filtered.map(\.yearHeading), [date("2026-01-01T14:00:00Z"), nil],
                       "The first search result gets its own year heading")
        XCTAssertEqual(filtered.map(\.showsDate), [true, true], "The first search result gets its own date")
        XCTAssertEqual(filtered.map(\.heading), [.month(date("2026-01-01T14:00:00Z")), nil])
        let interrupted = ArticleTimelineGrouping.entries(articles: [articles[1], articles[6], articles[2]], calendar: shanghai)
        XCTAssertEqual(interrupted.map(\.yearHeading), [
            date("2025-12-31T16:01:00Z"), nil, date("2026-01-01T14:00:00Z")
        ], "An undated run interrupts the year grouping")
        XCTAssertEqual(interrupted.map(\.showsDate), [true, false, true])
        XCTAssertEqual(interrupted.map(\.heading), [
            .month(date("2025-12-31T16:01:00Z")), .undated, .month(date("2026-01-01T14:00:00Z"))
        ])
        let anotherYear = ArticleTimelineGrouping.entries(articles: [
            articles[0], article("december-next-year", created: "2026-12-31T15:59:00Z")
        ], calendar: shanghai)
        XCTAssertEqual(anotherYear.map(\.yearHeading), [
            date("2025-12-31T15:59:00Z"), date("2026-12-31T15:59:00Z")
        ], "The same numeric month in a different year needs a separate year heading")
        XCTAssertEqual(anotherYear.map(\.heading), [
            .month(date("2025-12-31T15:59:00Z")), .month(date("2026-12-31T15:59:00Z"))
        ], "The same numeric month in a different year starts a new heading")
        let sameYear = ArticleTimelineGrouping.entries(articles: [
            articles[1], article("february", created: "2026-02-01T08:00:00Z")
        ], calendar: shanghai)
        XCTAssertEqual(sameYear.map(\.yearHeading), [date("2025-12-31T16:01:00Z"), nil],
                       "A month change within the same local year must not repeat the year heading")
        XCTAssertEqual(sameYear.map(\.heading), [
            .month(date("2025-12-31T16:01:00Z")), .month(date("2026-02-01T08:00:00Z"))
        ])

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let utcYearBoundary = ArticleTimelineGrouping.entries(articles: Array(articles.prefix(2)), calendar: utc)
        XCTAssertEqual(utcYearBoundary.map(\.yearHeading), [date("2025-12-31T15:59:00Z"), nil],
                       "The injected calendar's time zone determines the year boundary")

        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let daylightSavingRuns = [
            ["2026-03-08T06:30:00Z", "2026-03-08T07:30:00Z", "2026-03-09T03:30:00Z", "2026-03-09T04:00:00Z"],
            ["2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z", "2026-11-02T04:30:00Z", "2026-11-02T05:00:00Z"]
        ]
        for timestamps in daylightSavingRuns {
            let run = timestamps.enumerated().map { article("dst-\($0.offset)", created: $0.element) }
            let local = ArticleTimelineGrouping.entries(articles: run, calendar: newYork)
            XCTAssertEqual(local.map(\.showsDate), [true, false, false, true],
                           "Spring-forward and repeated fall-back hours remain in their local day")
            XCTAssertEqual(local.map(\.yearHeading), [date(timestamps[0]), nil, nil, nil])
            XCTAssertEqual(local.map(\.heading), [.month(date(timestamps[0])), nil, nil, nil])
            XCTAssertEqual(ArticleTimelineGrouping.entries(articles: run, calendar: utc).map(\.showsDate),
                           [true, false, true, false], "The injected calendar's time zone determines the day boundary")
        }
    }

    private func article(_ id: String, modified: String? = nil, created: String? = nil,
                         pinned: Bool = false, sort: Int64 = 0) -> MWebArticle {
        MWebArticle(id: id, title: id, excerpt: "Body", modifiedAt: modified.map(date),
                    createdAt: created.map(date), categoryIDs: [], isTrashed: false,
                    isPinned: pinned, sort: sort, isAvailable: true)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
