# Timeline article-list fixture

This synthetic overlay supplies [E2E-015](../../../docs/testing/cases/E2E-015.md). It adds the root category Timeline (106) and six articles to a fresh, ignored Preview run. The committed [Library fixture](../Library/README.md), its seven active articles, existing category counts, and all media files remain unchanged. The overlaid run has All 13 and Timeline 6; it is not the starting state for the other Library cases.

The article list uses the fixed modification dates below, newest first. All six creation dates are January 2, 2026, so displaying creation dates instead would be visible. Dates are specified for Asia/Shanghai: each SQL timestamp is at 04:00 UTC, or noon locally. Month labels may follow the system locale; their calendar months must match. One independent 2026 year heading precedes six month-only headings, October through May. The year and first month occupy separate lines, and the row date column shows only the large day number at both normal and narrow widths.

| Order / ID | Title | Modified date / day and month heading | Images in document | Expected collage |
| --- | --- | --- | --- | --- |
| 1 / 11000 | Timeline 0 · Quiet notes | October 19, 2026 / 19 and October | 0 | No collage or empty image placeholder |
| 2 / 11001 | Timeline 1 · Mountain morning | September 18, 2026 / 18 and September | 1 | Mountain fills the square |
| 3 / 11002 | Timeline 2 · Lake and dunes | August 17, 2026 / 17 and August | 2 | Mountain left, dunes right |
| 4 / 11003 | Timeline 3 · Three stops | July 16, 2026 / 16 and July | 3 | Mountain fills the left half; dunes upper right and woodland lower right |
| 5 / 11004 | Timeline 4 · Four views | June 15, 2026 / 15 and June | 4 | Mountain and dunes on top; woodland and courtyard below |
| 6 / 11006 | Timeline 6 · Beyond four | May 14, 2026 / 14 and May | 6 | The same first four images and arrangement as 11004 |

The first paragraph after each title is a distinct plain-text excerpt. Each document ends with `End of Timeline <image-count>.` The six-image article places the JPEG color detail fifth and the transparent plant sixth; neither belongs in its article-list collage. Its article preview still contains all six images.

All references point to existing `docs/media/10006/` assets in the copied Library. Source order is mountain.svg, panorama.svg, portrait.svg, square.png, detail.jpg, transparent.png. The collage occupies one square, with source images cropped to fill their tiles without stretching. Preview images keep their normal article rendering; the square cropping is specific to the list thumbnails.

Build from committed source as required by the [testing guide](../../../docs/testing/test-guide.md). From the repository root, choose a fresh run name and use it in all three commands:

```sh
./scripts/run-preview-app.sh e2e-015 --prepare-only
python3 scripts/apply-timeline-fixture.py e2e-015
./scripts/run-preview-app.sh --reopen e2e-015
```

The first command builds the full app and prepares its isolated Library without launching it. The overlay script accepts only a prepared run name under ignored `build/Test Runs/`; it requires an unchanged Library baseline and overlay source hashes matching that run's `run.json`. It inserts the rows from `seed.sql` and copies only the six new Markdown files. It rejects an already overlaid or edited run. Apply it before the first launch; never point an app at these source inputs or use a personal library. `--reopen` launches the prepared binary without rebuilding.

The `.fixture-baseline.json` still describes the original Library: the changed `mainlib.db` and six added Markdown files are intentional setup differences. Keep all run observations and screenshots under the ignored run directory. Record the actual app's full `run.json` `baseCommit`, verify dirty source metadata as the guide requires, and update an E2E result only after executing the case. Preparing this overlay is not a test execution.
