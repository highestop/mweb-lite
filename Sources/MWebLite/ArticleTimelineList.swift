import SwiftUI

/// Natural headers retain their accessibility order. A single overlay positions
/// their visual copies without publishing scroll offsets into view state.
struct ArticleTimelineList<Row: View>: View {
    private let sections: [TimelineYearSection]
    private let row: (ArticleTimelineGrouping.Entry) -> Row
    private let yearHeight: CGFloat = 36
    private let monthHeight: CGFloat = 32

    init(entries: [ArticleTimelineGrouping.Entry],
         @ViewBuilder row: @escaping (ArticleTimelineGrouping.Entry) -> Row) {
        sections = TimelineYearSection.group(entries)
        self.row = row
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(sections) { year in
                    VStack(spacing: 0) {
                        if let date = year.date {
                            yearHeader(date)
                        }
                        ForEach(year.months) { month in
                            VStack(spacing: 0) {
                                monthHeader(month.heading)
                                LazyVStack(spacing: 2) {
                                    ForEach(month.entries) { entry in
                                        row(entry).id(entry.id)
                                    }
                                }
                            }
                            .anchorPreference(key: TimelineSectionAnchorKey.self, value: .bounds) {
                                TimelineSectionAnchors(months: [month.id: $0])
                            }
                        }
                    }
                    .transformAnchorPreference(key: TimelineSectionAnchorKey.self, value: .bounds) {
                        $0.years[year.id] = $1
                    }
                }
            }
            .padding(10)
        }
        .overlayPreferenceValue(TimelineSectionAnchorKey.self) { anchors in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(sections) { year in
                        if let anchor = anchors.years[year.id] {
                            let bounds = geometry[anchor]
                            let height = year.date == nil ? 0 : yearHeight
                            let yearY = min(max(bounds.minY, 0), bounds.maxY - height)
                            let monthTop = max(0, yearY + height)
                            ForEach(year.months) { month in
                                if let anchor = anchors.months[month.id] {
                                    let monthBounds = geometry[anchor]
                                    let monthY = min(max(monthBounds.minY, monthTop),
                                                     monthBounds.maxY - monthHeight)
                                    positionedHeader(bounds: monthBounds, y: monthY, height: monthHeight,
                                                     minimumY: monthTop, viewportHeight: geometry.size.height) {
                                        monthHeader(month.heading)
                                    }
                                }
                            }
                            if let date = year.date {
                                positionedHeader(bounds: bounds, y: yearY, height: yearHeight,
                                                 minimumY: 0, viewportHeight: geometry.size.height) {
                                    yearHeader(date)
                                }
                                .zIndex(1)
                            }
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .clipped()
                .accessibilityHidden(true)
                .transaction { $0.animation = nil }
            }
        }
    }

    /// Clip an outgoing month below its year, including fractional scroll offsets.
    /// Only the visible opaque header rectangle consumes pointer clicks.
    @ViewBuilder
    private func positionedHeader<Header: View>(
        bounds: CGRect, y: CGFloat, height: CGFloat, minimumY: CGFloat,
        viewportHeight: CGFloat, @ViewBuilder content: () -> Header
    ) -> some View {
        let top = max(0, max(y, minimumY))
        let bottom = min(viewportHeight, y + height)
        if bottom > top {
            content()
                .frame(width: bounds.width, height: height)
                .offset(y: y - top)
                .frame(width: bounds.width, height: bottom - top, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {}
                .position(x: bounds.midX, y: (top + bottom) / 2)
                .accessibilityElement(children: .ignore)
                .accessibilityHidden(true)
        }
    }

    private func yearHeader(_ date: Date) -> some View {
        Text(date, format: .dateTime.year())
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 2)
            .frame(height: yearHeight)
            .background(Color(nsColor: .controlBackgroundColor))
    }

    private func monthHeader(_ heading: ArticleTimelineGrouping.Heading) -> some View {
        Group {
            switch heading {
            case .month(let date):
                Text(date, format: .dateTime.month(.wide))
            case .undated:
                Text("无日期")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityAddTraits(.isHeader)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(height: monthHeight)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct TimelineYearSection: Identifiable {
    let id: String
    let date: Date?
    var months: [TimelineMonthSection]

    static func group(_ entries: [ArticleTimelineGrouping.Entry]) -> [Self] {
        var years: [Self] = []
        for entry in entries {
            let startsUndatedRun = entry.heading == .undated
            if years.isEmpty || entry.yearHeading != nil || startsUndatedRun {
                years.append(Self(id: entry.id, date: entry.yearHeading, months: []))
            }
            let yearIndex = years.count - 1
            if years[yearIndex].months.isEmpty || entry.heading != nil {
                years[yearIndex].months.append(TimelineMonthSection(
                    id: entry.id, heading: entry.heading ?? .undated, entries: []
                ))
            }
            let monthIndex = years[yearIndex].months.count - 1
            years[yearIndex].months[monthIndex].entries.append(entry)
        }
        return years
    }
}

private struct TimelineMonthSection: Identifiable {
    let id: String
    let heading: ArticleTimelineGrouping.Heading
    var entries: [ArticleTimelineGrouping.Entry]
}

private struct TimelineSectionAnchors {
    var years: [String: Anchor<CGRect>] = [:]
    var months: [String: Anchor<CGRect>] = [:]
}

private enum TimelineSectionAnchorKey: PreferenceKey {
    static var defaultValue: TimelineSectionAnchors { TimelineSectionAnchors() }

    static func reduce(value: inout TimelineSectionAnchors, nextValue: () -> TimelineSectionAnchors) {
        let next = nextValue()
        value.years.merge(next.years, uniquingKeysWith: { _, latest in latest })
        value.months.merge(next.months, uniquingKeysWith: { _, latest in latest })
    }
}
