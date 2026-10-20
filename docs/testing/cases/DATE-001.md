| Field | Content |
| --- | --- |
| ID | DATE-001 |
| Verification | `ArticleTimelineGroupingTests/test_DATE_001_VisibleRunsUseLocalMonthsAndDaysWithoutReordering` |
| Given | Inline articles include pinned and nonchronological rows, adjacent and noncontiguous repeated local days/months, year boundaries, missing dates, creation-date fallback, and timestamps crossing Shanghai midnight and New York daylight-saving transitions. |
| When | Generate timeline entries for the supplied visible order using explicit calendars; repeat for filtered subsets, undated interruptions, the same numeric month in another year, UTC, and an empty list. |
| Then | Article identity, metadata, and input order remain unchanged. Each consecutive local year run starts an independent year heading, and each consecutive local year/month run starts a separate month heading. A year boundary emits both headings; a month change within the same year emits only the month heading. Undated runs receive one undated heading and no day labels. Only the first adjacent row of each local day shows its date, using modification time before creation time. A filtered first dated row or a dated row after an undated run restores both year and month headings and its date label; a repeated day after another day also restores its date label. Daylight-saving changes and UTC/local differences follow the injected calendar rather than fixed elapsed-day durations. These presentation flags do not establish actual UI spacing or alignment. |
| Level | Unit |
| Path | CI |
| Data | Inline |
