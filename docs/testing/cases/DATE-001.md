| Field | Content |
| --- | --- |
| ID | DATE-001 |
| Verification | `ArticleTimelineGroupingTests/test_DATE_001_VisibleRunsUseLocalMonthsAndDaysWithoutReordering` |
| Given | Inline articles include pinned and nonchronological rows, adjacent and noncontiguous repeated local days/months, year boundaries, missing dates, creation-date fallback, and timestamps crossing Shanghai midnight and New York daylight-saving transitions. |
| When | Generate timeline entries for the supplied visible order using explicit calendars; repeat for filtered subsets, undated interruptions, the same numeric month in another year, UTC, and an empty list. |
| Then | Article identity, metadata, and input order remain unchanged. Each consecutive local year/month run starts a month heading; undated runs receive one undated heading and no day labels. Only the first adjacent row of each local day shows its date, using modification time before creation time. A filtered first row, a repeated day after another day, or a dated row after an undated row restores its date label. Daylight-saving changes and UTC/local differences follow the injected calendar rather than fixed elapsed-day durations. These presentation flags do not establish actual UI spacing or alignment. |
| Level | Unit |
| Path | CI |
| Data | Inline |
