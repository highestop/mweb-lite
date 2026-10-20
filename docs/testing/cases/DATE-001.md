| Field | Content |
| --- | --- |
| ID | DATE-001 |
| Verification | `ArticleTimelineGroupingTests/test_DATE_001_VisibleRunsUseLocalMonthsAndDaysWithoutReordering` |
| Given | Inline articles include pin/custom-sort metadata and deliberately nonchronological input, repeated local creation days/months, year boundaries, conflicting modification dates, missing creation dates with or without modification dates, and creation timestamps crossing Shanghai midnight and New York daylight-saving transitions. |
| When | Generate timeline entries for the supplied visible order using explicit calendars; repeat after changing every modification timestamp, and for filtered subsets, undated interruptions, the same numeric month in another year, UTC, and an empty list. |
| Then | Grouping preserves article identity, metadata, and supplied order. Headings and day labels use creation time only; changing modification times does not change them, and a missing creation time remains undated without falling back to modification time. Each consecutive local year run starts an independent year heading and each local year/month run starts a separate month heading. A year boundary emits both; a month change within the same year emits only the month. Undated runs receive one undated heading and no day labels. Only the first adjacent row of each local creation day shows its date. A filtered first dated row or a dated row after an undated run restores both headings and its date; a repeated day after another day also restores its date. Midnight and daylight-saving boundaries follow the injected calendar. These presentation flags do not establish list sorting, actual UI spacing, or alignment. |
| Level | Unit |
| Path | CI |
| Data | Inline |
