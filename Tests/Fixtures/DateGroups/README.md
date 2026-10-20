# Article date-group fixture

This independent synthetic overlay supplies [E2E-016](../../../docs/testing/cases/E2E-016.md). It adds the root category Date Groups (107) and six short, text-only articles to a fresh Preview run. The original [Library](../Library/README.md) and [Timeline](../Timeline/README.md) source inputs remain unchanged. The prepared DateGroups run has All 13 and Date Groups 6; apply this scenario instead of Timeline, not on top of it.

The expected order and dates use modification timestamps in Asia/Shanghai. All six creation dates are January 2, 2025. Month names may follow the system locale, but each section must identify both its year and month.

| Order / ID | Title | Local modification time | Section | Row date |
| --- | --- | --- | --- | --- |
| 1 / 12001 | Date Anchor A | 2026-10-19 12:00 | October 2026 starts here | Show 19 |
| 2 / 12002 | Date Anchor B | 2026-10-19 07:00 | Continue October 2026 | Omit repeated date |
| 3 / 12003 | Date Anchor C | 2026-10-19 00:30 | Continue October 2026 | Omit repeated date |
| 4 / 12004 | Previous Day | 2026-10-18 20:00 | Continue October 2026 | Show 18 |
| 5 / 12005 | Previous Month | 2026-09-21 12:00 | September 2026 starts here | Show 21 |
| 6 / 12006 | Previous Year | 2025-10-17 12:00 | October 2025 starts here | Show 17 |

Date Anchor A has an October 19 UTC timestamp; B and C have October 18 UTC timestamps. All three belong to October 19 locally. Previous Day also has an October 18 UTC timestamp but belongs to October 18 locally. This distinguishes local-calendar grouping from UTC grouping. The previous-year note repeats October in another year so a month-only grouping or label cannot pass the case.

Search for the exact title `Date Anchor B`. It is the sole matching article and must show its own 19 date and the October 2026 section header. Clear the search to restore all six rows, the three headers, and the omitted dates on B and C. Each article's first paragraph identifies its place in the scenario, so selecting a row can be checked against the displayed document.

Build from committed source according to the [testing guide](../../../docs/testing/test-guide.md). From the repository root, use one fresh run name in these three commands:

```sh
./scripts/run-preview-app.sh e2e-016 --prepare-only
python3 scripts/apply-timeline-fixture.py e2e-016 --date-groups
./scripts/run-preview-app.sh --reopen e2e-016
```

The shared overlay script retains its default Timeline behavior; `--date-groups` selects this fixture, IDs, category, and SQL instead. It requires a pristine Library baseline and matching overlay source hashes in the prepared run's `run.json`. It writes only the six new Markdown files and scenario database rows in ignored `build/Test Runs/`. It rejects a changed or previously overlaid run. Apply the overlay before first launch and never use a personal library.

The unchanged `.fixture-baseline.json` describes the original Library; the changed database and added six documents are intentional setup differences. Keep observations and screenshots in the ignored run directory. Record the actual tested full SHA from `run.json` `baseCommit`, with the source/dirty-state checks required by the guide. Preparing the fixture is not an E2E execution and does not establish a result.
