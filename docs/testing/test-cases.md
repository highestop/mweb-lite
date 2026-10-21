# Test cases

This document defines the shared case format and indexes the individual case files. Each file records behavior, test level, verification path, data source, and execution instructions. It contains 91 cases: 64 Swift tests, 6 preview-component integration cases, 20 full-app preview cases, and 1 release-app case. Execution results are separate in [CI results](ci-test-result.md) and [manual end-to-end results](e2e-test-result.md). Follow the [test guide](test-guide.md) for setup and implementation. A passing test verifies only its **Then** statement at the recorded revision; it does not certify the whole feature or subsequent changes. In particular, AppKit component tests and `PreviewTests.app` are integration tests, not full-application end-to-end tests.

## Format and result rules

Store each case in `cases/<ID>.md` as exactly one two-column Markdown table. Use `| Field | Content |` as the header and `| --- | --- |` as its separator. Follow them with exactly eight rows in this order: `ID`, `Verification`, `Given`, `When`, `Then`, `Level`, `Path`, and `Data`. The ID value must equal the filename without `.md`. Do not add a title, section headings, or content outside the table. Keep execution results out of case definitions.

Keep each row on one source line. Field content may use inline Markdown; use `<br>` for displayed line breaks. Escape every literal pipe as `\|`, including pipes inside code spans, so it cannot be mistaken for a column delimiter.

### Case file template

Copy the complete table below into a new case file and replace the placeholders. Replace a source-link placeholder with a real relative link when Data is Fixture or Mixed.

```markdown
| Field | Content |
| --- | --- |
| ID | <ID> |
| Verification | <Exact automated selector or full-app execution steps> |
| Given | <Initial state and required data> |
| When | <Action or sequence under test> |
| Then | <Observable expected results> |
| Level | <Unit, Integration, or End-to-end> |
| Path | <CI, Local script, Preview app, or Release app> |
| Data | <Inline, Fixture: source link, or Mixed: source link + generated setup> |
```

Use relative links from the case file's directory: fixture links start with `../../../Tests/Fixtures/`. Commands and runtime paths remain relative to the repository root. Follow the [test guide](test-guide.md) for execution setup and shared fixture expectations.

Each case has a permanent ID and explicit **Given / When / Then (GWT)** statements. Keep IDs when renaming tests. Add a separate case file when a scenario needs a different setup, test level, or verification path. Update the implementation, fixture, and case together when behavior changes.

| Field | Meaning |
| --- | --- |
| ID | Stable identifier used in logs and review discussions; equals the filename without `.md`. |
| Verification | Exact automated selector, or full-app steps and fixture reference. |
| Given | Initial state and required data. |
| When | The action under test. |
| Then | Observable assertions that determine the result. |
| Level | `Unit`, `Integration`, or `End-to-end`. The level describes the test's scope independently of where or how it runs. |
| Path | `CI`, `Local script`, `Preview app`, or `Release app`. The path identifies the execution environment and application variant used to verify this case. |
| Data | Initial input source and any additional generated setup: `Inline` for literals/setup in test code, `Fixture: <source link>` for committed fixture inputs, or `Mixed: <source link> + <generated setup>` when both are required. Links identify source files/directories, not a mutable run copy. |

XCTest methods include their stable case ID, replacing its hyphen with an underscore: `test_LIB_001_<Behavior>`. Verification must name the exact `ClassName/test_LIB_001_<Behavior>` selector implemented in code. Test classes inherit from `CaseReportingTestCase`, which appends structured results to `MWEB_XCTEST_RESULTS_PATH` when configured. The WebKit integration program emits explicit PV case IDs to `MWEB_CASE_RESULTS_PATH`. Result collection uses these IDs, not test order or a guessed match from a description; see the [guide](test-guide.md) for fresh-output setup and collection commands.

Data describes the case's initial inputs. Runtime database materialization and copying a fixture into an isolated run do not turn a Fixture case into Inline or Mixed. Action inputs such as text typed in the app belong in When; they do not change a fixture-based case's Data label. Mixed is used when the setup adds separate generated inputs, such as PV-001's outside-file and symlink escape probes. Keep mutable runtime copies separate from committed source links.

## CI result contract

The `ci-case-results` workflow artifact contains `case-results.json`: a JSON array whose items have exactly three fields, `case_id`, `status`, and `evidence`. Each ID must refer to a case whose Path is `CI`. Status is `Passed`, `Failed`, or `Skipped`, and evidence identifies the actual execution. Only explicitly reported results from that run are included.

```json
[
  {
    "case_id": "LIB-001",
    "status": "Passed",
    "evidence": "<execution evidence and source/run reference>"
  }
]
```

A test that did not run has no result entry. A compile error, failed application build, or failed overall job does not make every case `Failed`. An explicit skip is `Skipped`; it is never a pass. Local script, Preview app, and Release app results are not inserted into this CI artifact. Running the same command locally is not a CI execution, and starting an app or passing a build does not verify a user flow.

[ci-test-result.md](ci-test-result.md) contains the latest published CI results as a two-column table: `Case ID` and `Status`. Each Case ID links to `cases/<ID>.md`. Shared links to the CI run attempt and tested commit appear before the table. Per-case evidence and diagnostics remain in the artifact's unchanged three-field JSON records. Results apply to the linked execution and tested revision, not automatically to later code.

## Manual end-to-end result contract

[e2e-test-result.md](e2e-test-result.md) tracks the 21 end-to-end cases: 20 Preview app cases and REL-001 for the Release app. Its columns are `Case ID`, `Status`, `Commit SHA`, and `Outdated`. Case IDs link to their definitions. Record `Passed`, `Failed`, or `Skipped` only for an actual execution, with the full commit SHA of the app version tested, formatted as inline code. Do not use the later commit that records the result. A case with no execution record uses `—` for Status, Commit SHA, and Outdated.

Outdated is computed independently of the recorded outcome: `Yes` means the tested effective version differs from current main or the recorded commit cannot be resolved; an empty cell means they match. Refreshing freshness must not change Status or Commit SHA. Both versions are normalized along first-parent history, ignoring only commits with a nonempty actual diff limited to `docs/testing/ci-test-result.md` and `docs/testing/e2e-test-result.md`. Source, fixture, case-definition, other documentation, or mixed commits count as version changes. See the [manual result workflow](test-guide.md#record-manual-end-to-end-results) for recording and refreshing results with full Git history.

Both Markdown result summaries are tracked. Keep raw JSON, detailed run reports, generated databases, app bundles, screenshots, and logs outside Git, in workflow artifacts or ignored `build/test-results/` and `build/Test Runs/`. Case definitions and this index do not duplicate execution results.

## Case index

Open a case to read or update its GWT statements, execution details, and data source. The short labels below are navigation aids only; see [CI results](ci-test-result.md) and [manual end-to-end results](e2e-test-result.md) for execution outcomes.

### Shared fixture compatibility

- [FIXTURE-001](cases/FIXTURE-001.md) — Open the shared fixture with production library code.

### Library reading and saving

- [LIB-001](cases/LIB-001.md) — Index UUID relationships and Markdown titles.
- [LIB-002](cases/LIB-002.md) — Save content while preserving metadata and backups.
- [LIB-003](cases/LIB-003.md) — Avoid changes when saving identical content.
- [LIB-004](cases/LIB-004.md) — Preserve external file edits on a save conflict.
- [LIB-005](cases/LIB-005.md) — Preserve external metadata changes on a save conflict.
- [LIB-006](cases/LIB-006.md) — Restore Markdown and metadata after a failed save commit.
- [LIB-007](cases/LIB-007.md) — Bound backup history while retaining the original.
- [LIB-008](cases/LIB-008.md) — Include committed WAL changes in database backups.
- [LIB-009](cases/LIB-009.md) — Preserve private backup and source-file permissions.
- [LIB-010](cases/LIB-010.md) — Reject trashed, absent, and invalid UTF-8 documents.
- [LIB-011](cases/LIB-011.md) — Keep other articles visible when one file is missing.
- [LIB-012](cases/LIB-012.md) — Reject unsupported libraries without creating files.
- [LIB-013](cases/LIB-013.md) — Reject article symlinks outside the library.
- [LIB-014](cases/LIB-014.md) — Preserve UTF-8 BOM and CRLF when saving.

### Document creation

- [CREATE-001](cases/CREATE-001.md) — Create, reopen, and edit an article in its selected category.
- [CREATE-002](cases/CREATE-002.md) — Create an uncategorized article.
- [CREATE-003](cases/CREATE-003.md) — Reject invalid categories before writing.
- [CREATE-004](cases/CREATE-004.md) — Preserve existing data on an identifier collision.
- [CREATE-005](cases/CREATE-005.md) — Reject unindexed file and media collisions.
- [CREATE-006](cases/CREATE-006.md) — Roll back creation when a category relationship fails.
- [CREATE-007](cases/CREATE-007.md) — Remove new Markdown after a failed creation commit.
- [CREATE-008](cases/CREATE-008.md) — Reject creation through an outside-library symlink.

### Application state and native row selection

- [SAVE-001](cases/SAVE-001.md) — Report local save status through autosave, in-flight edits, conflicts, and retry.

- [STORE-001](cases/STORE-001.md) — Save the prior draft before creating in the selected category.
- [STORE-002](cases/STORE-002.md) — Block creation while preserving a conflicting draft.
- [SELECT-001](cases/SELECT-001.md) — Update selection before asynchronous save and load.
- [SELECT-002](cases/SELECT-002.md) — Restore selection and draft after a save conflict.
- [SELECT-003](cases/SELECT-003.md) — Restore the current document after a target load failure.
- [SELECT-004](cases/SELECT-004.md) — Keep the pending selection while busy.
- [ROW-001](cases/ROW-001.md) — Attach row selection to the current reused row.
- [ROW-002](cases/ROW-002.md) — Disable and dismantle row selection callbacks.
- [ROW-003](cases/ROW-003.md) — Accept only an unmodified primary mouse-down.

### Timeline article cards

- [DATE-001](cases/DATE-001.md) — Mark consecutive year/month boundaries and suppress repeated local-day labels without reordering visible articles.

- [MEDIA-001](cases/MEDIA-001.md) — Extract the first four Markdown image references in order while ignoring code and comments.
- [MEDIA-002](cases/MEDIA-002.md) — Find images beyond the summary prefix and refresh references after a save.
- [THUMB-001](cases/THUMB-001.md) — Decode local thumbnails with bounded caching, path confinement, and stale-request protection.

### Drawer and scroll layout

- [DRAWER-001](cases/DRAWER-001.md) — Move both navigation columns together while keeping the document's right edge fixed.
- [DRAWER-002](cases/DRAWER-002.md) — Keep a hosted native scroll view's right edge fixed when its preferred width differs from the layout proposal.
- [DRAWER-003](cases/DRAWER-003.md) — Give native resize handles cursor and drag ownership with clean disabling and teardown.
- [SCROLL-001](cases/SCROLL-001.md) — Preserve hosted timeline/editor width with shared overlay scrollers and native wheel input.
- [SCROLL-002](cases/SCROLL-002.md) — Reveal asynchronous library selections below sticky headers while preserving visible rows and completed requests on native remount.

### Markdown editing rules

- [EDIT-001](cases/EDIT-001.md) — Continue lists and exit empty items.
- [EDIT-002](cases/EDIT-002.md) — Keep list continuation outside fenced code.
- [EDIT-003](cases/EDIT-003.md) — Preserve Unicode selections while toggling bold.
- [EDIT-004](cases/EDIT-004.md) — Toggle italic within bold text.
- [EDIT-005](cases/EDIT-005.md) — Indent only the selected lines.
- [EDIT-006](cases/EDIT-006.md) — Clamp the caret when removing indentation.
- [EDIT-007](cases/EDIT-007.md) — Select a new link destination for replacement.
- [EDIT-008](cases/EDIT-008.md) — Toggle line prefixes without including the next line.

### Native editor integration

- [FOCUS-001](cases/FOCUS-001.md) — Commit composition when the editor loses focus.
- [FOCUS-002](cases/FOCUS-002.md) — Preserve selection and undo through a focus round trip.
- [FOCUS-003](cases/FOCUS-003.md) — Select only a new document’s Unicode title.
- [FOCUS-004](cases/FOCUS-004.md) — Open a different article in a fresh editor at the top while keeping the same editor through mode changes.

### Packaged WebKit preview integration

- [PV-001](cases/PV-001.md) — Confine local media access to the library.
- [PV-002](cases/PV-002.md) — Parse supported article URLs.
- [PV-003](cases/PV-003.md) — Render bundled Markdown and load a local image.
- [PV-004](cases/PV-004.md) — Isolate unsafe HTML content.
- [PV-005](cases/PV-005.md) — Render optional math, diagrams, charts, and code highlighting.
- [PV-006](cases/PV-006.md) — Reset preview scroll for a different document and preserve it for updates to the same document.

### Preview-app end-to-end cases

- [E2E-001](cases/E2E-001.md) — Browse the category tree and article counts with neutral gray selection.
- [E2E-002](cases/E2E-002.md) — Search article titles and clear the query.
- [E2E-003](cases/E2E-003.md) — Create an article in the current category with the toolbar's plus button.
- [E2E-004](cases/E2E-004.md) — Create an uncategorized article from the keyboard.
- [E2E-005](cases/E2E-005.md) — Keep the editing toggle and selected state synchronized with menu/shortcut changes while preserving undo.
- [E2E-006](cases/E2E-006.md) — Save edits across article switches and app restart.
- [E2E-007](cases/E2E-007.md) — Commit real Chinese composition across focus changes.
- [E2E-008](cases/E2E-008.md) — Keep one light-gray selection through mouse-down, release, and keyboard navigation.
- [E2E-009](cases/E2E-009.md) — Center the compact plus icon and show gray hover/pressed feedback.
- [E2E-010](cases/E2E-010.md) — Align the toolbar's left buttons and right editing toggle, and animate column visibility with Reduce Motion support.
- [E2E-011](cases/E2E-011.md) — Render the showcase and follow an internal article link.
- [E2E-012](cases/E2E-012.md) — Preserve the UI draft after an external-file conflict.
- [E2E-013](cases/E2E-013.md) — Start newly selected articles at the top in editor and preview while preserving same-article mode positions.
- [E2E-014](cases/E2E-014.md) — Render local image galleries across formats, mode changes, scrolling, and narrow window widths.

- [E2E-015](cases/E2E-015.md) — Browse dated article cards with zero through four thumbnails and a four-image cap.

- [E2E-016](cases/E2E-016.md) — Display separate sticky year/month headings and repeated-day spacing across scrolling, selection, and search.
- [E2E-017](cases/E2E-017.md) — Keep light translucent scrollbars overlaid without layout shifts in categories, articles, editor, and preview.

- [E2E-018](cases/E2E-018.md) — Show local save status for pending edits and conflicts, and hide it after autosave or reload.

### Document and category management

- [CAT-001](cases/CAT-001.md) — Names, root/child UUID relationships, sort position, defaults, and the database backup are correct
- [CAT-002](cases/CAT-002.md) — Only Notes and all of its memberships disappear
- [CAT-003](cases/CAT-003.md) — Workspace, Writing, and Notes disappear together; documents and outside-subtree memberships survive
- [CAT-004](cases/CAT-004.md) — Every operation throws
- [TRASH-001](cases/TRASH-001.md) — Only article.state changes to 0
- [TRASH-002](cases/TRASH-002.md) — All attempts fail without modifying article rows or document/media bytes.
- [STORE-003](cases/STORE-003.md) — The first deletion saves and retains the current draft/selection
- [STORE-004](cases/STORE-004.md) — Each operation is blocked before its structural write
- [STORE-005](cases/STORE-005.md) — The draft is saved before management writes
- [ROW-004](cases/ROW-004.md) — Deletion calls the current target without selecting it
- [E2E-019](cases/E2E-019.md) — Creation and renaming update the tree
- [E2E-020](cases/E2E-020.md) — Cancel changes nothing. Deleting B removes B while A stays open. Deleting the selected article opens another remaining row. Both deletions persist, active/category counts update, and deleted documents have state 0 with Markdown, attachments, and other metadata/relations preserved. No right-click selects or deletes a different row.

### Release-app end-to-end case

- [REL-001](cases/REL-001.md) — Install and normally launch the release app with library restoration.
