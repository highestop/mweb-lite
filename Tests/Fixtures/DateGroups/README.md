# Article date-group fixture

This independent synthetic overlay supplies [E2E-016](../../../docs/testing/cases/E2E-016.md). It adds the root category Date Groups (107) and 18 text-only articles to a fresh Preview run. The original [Library](../Library/README.md) and [Timeline](../Timeline/README.md) source inputs remain unchanged. The prepared DateGroups run has All 25 and Date Groups 18; apply this scenario instead of Timeline, not on top of it. The six original anchor articles retain their IDs, contents, and dates; twelve additional articles make the later month and year boundaries reachable by scrolling.

The expected order and dates use modification timestamps in Asia/Shanghai. All creation dates are January 2, 2025. The list has two independent year headings, 2026 and 2025, and three month-only headings, October, September, and October. Each year heading occupies a visibly separate line before its first month heading. Month names may follow the system locale. The three month groups contain 4, 5, and 9 articles respectively.

| Order / ID | Title | Local modification time | Headings before row | Row date |
| --- | --- | --- | --- | --- |
| 1 / 12001 | Date Anchor A | 2026-10-19 12:00 | Year 2026, then month October | Show 19 |
| 2 / 12002 | Date Anchor B | 2026-10-19 07:00 | None | Omit repeated date |
| 3 / 12003 | Date Anchor C | 2026-10-19 00:30 | None | Omit repeated date |
| 4 / 12004 | Previous Day | 2026-10-18 20:00 | None | Show 18 |
| 5 / 12005 | Previous Month | 2026-09-21 12:00 | Month September | Show 21 |
| 6 / 12007 | DateScrollSeptember1 | 2026-09-20 12:00 | None | Show 20 |
| 7 / 12008 | DateScrollSeptember2 | 2026-09-20 11:00 | None | Omit repeated date |
| 8 / 12009 | DateScrollSeptember3 | 2026-09-20 10:00 | None | Omit repeated date |
| 9 / 12010 | DateScrollSeptember4 | 2026-09-20 09:00 | None | Omit repeated date |
| 10 / 12006 | Previous Year | 2025-10-17 12:00 | Year 2025, then month October | Show 17 |
| 11 / 12011 | DateScrollOctober1 | 2025-10-16 17:00 | None | Show 16 |
| 12 / 12012 | DateScrollOctober2 | 2025-10-16 16:00 | None | Omit repeated date |
| 13 / 12013 | DateScrollOctober3 | 2025-10-16 15:00 | None | Omit repeated date |
| 14 / 12014 | DateScrollOctober4 | 2025-10-16 14:00 | None | Omit repeated date |
| 15 / 12015 | DateScrollOctober5 | 2025-10-16 13:00 | None | Omit repeated date |
| 16 / 12016 | DateScrollOctober6 | 2025-10-16 12:00 | None | Omit repeated date |
| 17 / 12017 | DateScrollOctober7 | 2025-10-16 11:00 | None | Omit repeated date |
| 18 / 12018 | DateScrollOctober8 | 2025-10-16 10:00 | None | Omit repeated date |

Date Anchor A has an October 19 UTC timestamp; B and C have October 18 UTC timestamps. All three belong to October 19 locally. Previous Day also has an October 18 UTC timestamp but belongs to October 18 locally. This distinguishes local-calendar grouping from UTC grouping. The previous-year note repeats October in another year so a month-only grouping or label cannot pass the case.

At a 640-point window height and the normal article-column width, scroll down through the September 2026 boundary and then past the October 2025 boundary. The current year stays pinned below the search field, with the current month pinned directly below the year. September replaces October when that month boundary reaches the pinned area; 2025 and October replace 2026 and September at the next year boundary. Eight trailing October notes provide enough content for that boundary to reach the top. Scroll back upward and verify the reverse changes. The two pinned headings must remain readable and separate from each other and the search field.

Search for the exact title `Date Anchor B`. It is the sole matching article and must show its own 19 date, a separate 2026 year heading, and an October month heading. Clear the search to restore all 18 rows, both year headings, all three month headings, and the omitted dates on B and C. Only the first September scroll note shows 20, and only the first October scroll note shows 16. Each article's first paragraph identifies its place in the scenario, so selecting a row can be checked against the displayed document.

Build from committed source according to the [testing guide](../../../docs/testing/test-guide.md). From the repository root, use one fresh run name in these three commands:

```sh
./scripts/run-preview-app.sh e2e-016 --prepare-only
python3 scripts/apply-timeline-fixture.py e2e-016 --date-groups
./scripts/run-preview-app.sh --reopen e2e-016
```

The shared overlay script retains its default Timeline behavior; `--date-groups` selects this fixture, IDs, category, and SQL instead. It requires a pristine Library baseline and matching overlay source hashes in the prepared run's `run.json`. It writes only the 18 new Markdown files and scenario database rows in ignored `build/Test Runs/`. It rejects a changed or previously overlaid run. Apply the overlay before first launch and never use a personal library.

The unchanged `.fixture-baseline.json` describes the original Library; the changed database and added 18 documents are intentional setup differences. Keep observations and screenshots in the ignored run directory. Record the actual tested full SHA from `run.json` `baseCommit`, with the source/dirty-state checks required by the guide. Preparing the fixture is not an E2E execution and does not establish a result.
