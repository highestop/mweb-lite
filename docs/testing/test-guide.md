# Testing guide

Use [test-cases.md](test-cases.md) for the shared case format and index. Each case has its own definition under [cases/](cases/) describing what must work and how it is verified. Results are separate in [ci-test-result.md](ci-test-result.md) and [e2e-test-result.md](e2e-test-result.md). Use committed synthetic fixtures to reproduce full-app cases. A successful build alone does not verify any user interaction.

**Preview app** means `MWeb Lite Preview.app`: the complete application built for end-to-end testing with an isolated fixture library. **Release app** means the normal `MWeb Lite.app` with its production identity and normal launch flow. **WebKit integration test program** means `PreviewTests.app`: the temporary program that checks only the Markdown rendering component. Their existing filenames remain unchanged.

## Choose the level and execution path

The catalog separates **Level**, the scope of an assertion, from **Path**, where and how the case is verified. **Data** records the source of its initial test data. `swift test` is a runner that executes both unit and integration tests here. CI is an execution path, not a synonym for unit testing. An end-to-end case can also be automated in CI if the runner actually drives and checks the complete app; the current workflow does not do that.

| Level | Suitable assertions | Examples in this project | What it cannot establish by itself |
| --- | --- | --- | --- |
| Unit | A function or small piece of logic produces the right result for controlled inputs. | Markdown list continuation, formatting, UTF-16 selection ranges, indentation. | Event delivery, window focus, visual appearance, or persistence through the whole app. |
| Integration | Real components work together across a boundary. | SQLite plus Markdown saves and rollback; store selection while saving; AppKit text view plus binding and undo; packaged resources plus `WKWebView`. | That the production window connects these components correctly, or that a user can complete the workflow. |
| End-to-end | The built app accepts real user actions and produces the expected visible and persisted outcome. | Pressing a different article selects it immediately without blue feedback; creating an article in a category, editing it, quitting, and reopening it; View menu and shortcuts; actual Chinese input; layout, hover, and icon checks. | Exhaustive failure combinations. Test those deterministically at a lower level as well. |

Use the lowest level that can prove an assertion, then add an end-to-end case for behavior that depends on the assembled app. For example, the store tests prove that selecting B updates the selected ID before saving A finishes. Only a full-app mouse test proves that holding the mouse down on B shows the intended row background. These are separate cases with separate results.

An `NSWindow` created inside XCTest is still a component test. The WebKit integration test program uses real WebKit, but exercises only the Markdown rendering component. Full-app end-to-end cases run the complete Preview app or Release app, according to their Path.

Integration tests do not inherently require an app bundle. A test that creates a temporary SQLite database and Markdown file, invokes the real save code, and reads both back already exercises an integration boundary. The WebKit harness needs a macOS program to host its renderer; a GitHub macOS runner can build and execute that program without a person clicking its window. Both are automated integration tests. Full-app end-to-end tests additionally exercise the assembled user interface and complete user flows.

| Path | Execution environment and entry point | Current use |
| --- | --- | --- |
| `CI` | GitHub Actions runs the checked-out revision and scripts on its macOS runner. | The 54 XCTest cases and baseline WebKit cases PV-001 through PV-004 and PV-006. |
| `Local script` | A developer runs the documented command locally and records its output and environment. | PV-005 needs optional runtimes from an installed MWeb app; all CI commands can also be investigated locally. |
| `Preview app` | The complete app runs on macOS with a per-run bundle identifier and copied fixture library selected by `--library`. | Repeatable UI, editing, selection, rendering, and save/restart flows. |
| `Release app` | The normal app runs with its production bundle identifier, preferences, installation location, and normal launch entry point. | Installation, Finder/Dock icon, library chooser, and remembered-library restoration. |

Both Preview app and Release app run on a real Mac. The distinction is application identity, preferences, and startup behavior. The Preview app uses a per-run `app.highestop.mweb-lite.preview.<token>` identifier and an explicit fixture path. The Release app uses `app.highestop.mweb-lite` and exercises ordinary library selection and restoration. Preview results therefore do not establish that production preferences or installation behavior work. Keep Level and Path independent when adding cases; the current assignments are not restrictions on future test design.

## Test entry points

Run commands from the repository root on macOS 14 or later with Swift 5.9 or later, the Xcode Command Line Tools, and Python 3.9 or later. Native window and WebKit checks need a usable macOS graphical session and access to normal system services.

| Entry point | Purpose |
| --- | --- |
| `Tests/MWebCoreTests/` | Database, filesystem, backup, compatibility, and creation integration tests. |
| `Tests/MWebCoreTests/SharedFixtureTests.swift` | Opens a disposable copy of the committed full-app fixture with production library code; validates its documents, categories, and manifest. |
| `Tests/MWebLiteTests/MarkdownEditingTests.swift` | Pure Markdown editing unit tests. |
| Other files in `Tests/MWebLiteTests/` | Store and native control tests; classify each assertion by its scope in the catalog. |
| `Tests/PreviewIntegration/main.swift` | WebKit integration test program: automated rendering and resource isolation checks. |
| `Tests/Fixtures/Preview/` | Committed Markdown and image inputs for the WebKit integration test program. |
| `Tests/Fixtures/Library/` | Committed SQL, Markdown, and media for full-app cases. |
| `Tests/Fixtures/DateGroups/` | Same-day notes and month/year boundaries added to an isolated Library run for list grouping and search checks. |
| `Tests/Fixtures/Timeline/` | Six synthetic timeline articles covering zero, one, two, three, four, and six image references, added only to an isolated Library run. |
| `Tests/Fixtures/Scroll/` | Long Selection A/B documents overlaid onto an isolated Library run for article-switch scroll checks. |
| `scripts/prepare-test-library.py` | Materializes a runnable library from the full-app fixture. |
| `scripts/run-preview-app.sh` | Builds and starts the full Preview app with a copied fixture library for end-to-end tests. |

Run all 54 cataloged XCTest cases, or select a class or method while investigating a change:

```sh
swift test
swift test --filter MarkdownEditingTests
swift test --filter LibraryStoreSelectionTests/test_SELECT_001_SelectionChangesBeforeSavingAndLoadingTheNextDocument
```

To retain structured XCTest results and a console log without losing the command's failure status:

```sh
mkdir -p build/test-results
export MWEB_XCTEST_RESULTS_PATH="$PWD/build/test-results/xctest.jsonl"
: > "$MWEB_XCTEST_RESULTS_PATH"
set -o pipefail
swift test 2>&1 | tee build/test-results/swift-test.log
```

Tests inherit from the test-only `CaseReportingTestCase` in [Tests/CaseReporting](../../Tests/CaseReporting). When `MWEB_XCTEST_RESULTS_PATH` is set, its XCTest observer appends one JSONL record per completed case with exactly `case_id`, `status`, and `evidence`. Evidence starts with the exact selector and may include failure diagnostics. Use a new file or truncate it before every run; the reporter appends. Without that environment variable, ordinary `swift test` still runs without writing JSONL. This pipeline does not use `--xunit-output`: on the tested macOS toolchain it produced an empty Swift Testing XML report rather than XCTest results.

Use a fresh log name when keeping multiple runs. On a restricted execution host, a failure to start WebKit or use `NSFileCoordinator` may be an environment problem. Keep the diagnostic and rerun in a normal macOS session before claiming a pass. A local diagnostic does not change the recorded result of a separate CI execution.

## Write automated tests

Start with a case file in **Given / When / Then (GWT)** form. Given identifies the exact starting state, When describes one action or sequence, and Then states observable results. Include the stable case ID in the XCTest method name, for example `test_LIB_001_<Behavior>`, and put the exact `ClassName/test_LIB_001_<Behavior>` selector in Verification. The result collector maps this explicit ID; it does not infer identity from execution order. Keep failure diagnostics specific enough to identify which assertion failed.

Import `CaseReporting` and derive new XCTest classes from `CaseReportingTestCase` so CI receives their per-case results. Assertions and setup/teardown continue to use XCTest normally.

A unit test can directly mirror GWT. This example uses the existing Markdown editing API:

```swift
func test_EDIT_003_BoldPreservesUnicodeSelection() {
    // Given: Chinese characters and an emoji are selected using UTF-16 offsets.
    let source = "中文 😀"
    let selection = NSRange(location: 0, length: (source as NSString).length)

    // When: the selected text is wrapped in bold markers.
    let edit = MarkdownEditing.wrap(source, selection: selection, before: "**", after: "**")
    let result = (source as NSString).replacingCharacters(in: edit.range, with: edit.replacement)

    // Then: the content and selected text are both preserved.
    XCTAssertEqual(result, "**中文 😀**")
    XCTAssertEqual((result as NSString).substring(with: edit.selection), source)
}
```

See [MarkdownEditingTests.swift](../../Tests/MWebLiteTests/MarkdownEditingTests.swift) for the existing regression coverage; do not add a duplicate merely to copy this example.

For integration tests:

1. Create a uniquely named temporary directory and a minimal synthetic schema and document set. Register cleanup with `defer` or `tearDownWithError`; release database handles before removing their files. Never depend on a remembered library, the user's MWeb installation data, or another test's output.
2. Use fixed IDs, content, and timestamps where they affect the result. For example, `createDocument(categoryID:now:)` accepts a fixed date. Readable inline fixtures are useful for small failure cases; use the shared fixture when its categories and documents are part of the case contract.
3. Exercise real collaborators when the boundary is being tested: real SQLite and file writes for save recovery; a real AppKit text view for focus and undo. Run AppKit operations on `@MainActor` and clean up delegates, windows, and pending work.
4. Assert both state and effects. A successful save should reopen with the expected bytes and metadata. A failed save should preserve the draft, original file, and unrelated rows. Checking only an error or a return value is insufficient for rollback behavior.
5. Await operations or poll an observable condition with a deadline and a failure assertion. Do not use an arbitrary sleep as proof of completion. For debounced autosave, check its eventual disk result within a bounded timeout.
6. Produce failures deterministically. Existing tests use external file edits, conflicting metadata, and SQLite constraints to exercise conflicts and rollback. Do not rely on a live second app or randomly timed races for these cases.

[MWebDocumentCreationTests.swift](../../Tests/MWebCoreTests/MWebDocumentCreationTests.swift) demonstrates fixed-time creation, metadata preservation, and rollback. [LibraryStoreSelectionTests.swift](../../Tests/MWebLiteTests/LibraryStoreSelectionTests.swift) checks the immediate selection state separately from the eventual loaded document and saved file. [MarkdownEditorFocusTests.swift](../../Tests/MWebLiteTests/MarkdownEditorFocusTests.swift) tests marked-text and focus integration; actual input-method interaction remains a full-app case.

[SharedFixtureTests.swift](../../Tests/MWebCoreTests/SharedFixtureTests.swift) implements FIXTURE-001. It copies the same committed source fixture used by the Preview app into its own temporary library and opens it through production `MWebLibrary`. This catches fixture drift without sharing mutable run data or certifying any end-to-end interaction.

For a regression, make the test fail for the original behavior, then verify the fix. Test externally visible behavior rather than duplicating the implementation's internal steps.

## Run the WebKit integration test program

```sh
./scripts/test-preview.sh
```

This script compiles `MarkdownPreview.swift` and `Tests/PreviewIntegration/main.swift` into the temporary WebKit integration test program, `PreviewTests.app`, packages the production renderer resources, and loads a copy of `Tests/Fixtures/Preview/`. It deliberately has no SwiftPM resource fallback. It checks rendered DOM content and media loading in a real `WKWebView`, and checks that unsafe content and files outside the library are not exposed.

The temporary app and mutable fixture copy are removed when the script exits. The script preserves a human-readable `.log` and machine-readable `.jsonl` under `build/test-results/preview-<UTC timestamp>`. Each JSONL line contains exactly `case_id`, `status`, and `evidence`, with status `Passed`, `Failed`, or `Skipped`. The matching `PASS`, `FAIL`, and `SKIP` console messages come from the same result records. A setup failure can terminate the process before a case reports; it must not fabricate results for unexecuted cases.

Set `MWEB_CASE_RESULTS_PATH` to choose a JSONL destination, for example:

```sh
MWEB_CASE_RESULTS_PATH="$PWD/build/test-results/preview.jsonl" ./scripts/test-preview.sh
```

Each invocation starts a fresh result file. A nonzero process exit still matters even if some preceding cases passed.

The baseline rendering runs with optional runtimes disabled even when MWeb is installed. MathJax, Mermaid, ECharts, and Prism assertions depend on optional runtime assets from a local MWeb installation. PV-005 therefore has Path `Local script`: its JSONL result remains available locally but is excluded from the CI artifact. If the assets are absent, the program explicitly emits `Skipped`; the baseline cases must still pass.

This program does not test the article list, menus, editor, application lifecycle, or the complete save workflow. Use the Preview app below for those end-to-end cases.

## Fixture ownership

CI can read committed fixture files after checking out the repository. Data placement depends on size and reuse, not on whether a test runs in CI. Keep short unit-test inputs and small, scenario-specific integration setups inline. Put long Markdown, media, complex/shared integration data, and full-app starting states in versioned fixture files. Both forms are valid for CI; all writable runtime data must still be isolated.

Each case's **Data** field identifies how its **Given** state is supplied:

| Data | Meaning | Example |
| --- | --- | --- |
| `Inline` | Initial text, SQL, events, or objects are defined in the test code or setup instructions. | A Markdown editing string or a minimal database constructed inside an XCTest. |
| `Fixture` | Initial content comes from committed fixture files; the field links to the relevant file or directory. Copying files or materializing their SQL into a runtime database does not change this classification. | FIXTURE-001 and the Preview app cases use [the Library fixture](../../Tests/Fixtures/Library). |
| `Mixed` | The initial state combines committed fixture content with case-specific data or objects added programmatically or by setup instructions. Include a fixture link and describe the added setup. | PV-001 uses [the test image](../../Tests/Fixtures/Preview/media/test.png) plus generated outside-library and symlink probes. |

Data describes the starting input, not every literal used by a test. Text entered during **When**, expected values in **Then**, and assertions do not by themselves make a fixture case `Mixed`. For example, creating an article with a specified title in a copied Library fixture remains `Fixture`. This classification is independent of Level and Path: a CI integration test can use `Inline`, `Fixture`, or `Mixed` data.

The fixture sources are intentionally tracked in Git: synthetic SQL, Markdown, media, and their expected facts make the cases reviewable and repeatable. Generated SQLite databases, mutable document copies, backups, apps, screenshots, and logs belong in ignored `build/` or temporary directories.

Treat `Tests/Fixtures/` as immutable input during a test run. Materialize or copy it before opening it in an app. Never select a personal MWeb library to satisfy a test. Each new full-app run gets its own library; tests do not share changes with each other unless a case explicitly requires reuse for restart verification.

Keep IDs and timestamps stable, document the purpose of each article and category, and use local synthetic media rather than network-dependent images. When adding a fixture, describe its expected rows, document text, relationships, and visible results in its README and catalog case. Changes to fixture contents must be reviewed with the affected case expectations.

## Build and run the Preview app for end-to-end tests

Use a new run name for a clean starting state:

```sh
./scripts/run-preview-app.sh selection-check
```

This builds the real Release app, copies it to `build/Test Runs/selection-check/MWeb Lite Preview.app`, creates `build/Test Runs/selection-check/Library` from the committed fixture, and launches that copy with `--library`. The Preview app has its own bundle identifier and preferences. The explicit library argument does not replace the remembered library of the normal app. The app includes the complete category tree, article list, editor, menus, and Markdown rendering needed for end-to-end testing.

The run directory retains the app, mutable library, `run.json`, and the library's `.fixture-baseline.json`. `run.json` records the source fingerprint, base commit, working-tree state, macOS and Swift/Xcode versions, and the fixture version read from that baseline. The baseline retains initial file hashes. Record this run name and use its paths for all observations. The launcher refuses to overwrite an existing run. If only preparation is needed, use:

```sh
./scripts/run-preview-app.sh selection-check --prepare-only
```

Choose one of those commands for a new run; do not run both with the same name. To test persistence, quit that Preview app with `⌘Q`, then reopen the same app and modified library:

```sh
./scripts/run-preview-app.sh --reopen selection-check
```

`--reopen` preserves the run and does not rebuild the binary. After changing source, start a new run to test the new build. Closing a window is not the same as quitting the application.

E2E-013 uses the committed [Scroll fixture](../../Tests/Fixtures/Scroll/README.md) as an overlay on a new Library run. Prepare its app with `--prepare-only`, copy the two long Markdown files into that run's `Library/docs/`, and only then launch with `--reopen`. Follow the fixture's exact commands; do not replace the short source files under `Tests/Fixtures/Library/`. The overlay is part of the case's Given state, not a user-data edit or a new fixture baseline.

E2E-014 needs no overlay: the standard Library fixture includes three Chinese image articles under Image Demos. Follow the [Library fixture README](../../Tests/Fixtures/Library/README.md) for the six shared media files and dimensions. Open and scroll through all three previews, then use the six-image `10007.md` article for the editor/preview round trip and 940-point-wide window check. Keep both left columns visible so the narrow article pane is exercised.

To prepare only a library for a targeted investigation:

```sh
python3 scripts/prepare-test-library.py 'build/Test Runs/fixture-check/Library'
```

The destination must be a new directory inside this repository's ignored `build/`. The script creates `mainlib.db` from `schema.sql` and `seed.sql`, copies document/media files, and checks the fixture manifest. It does not read an existing MWeb library. Use the launcher for catalog end-to-end runs so their app and run metadata are retained together.

Execute each full-app case from its documented Given state. Use a fresh run after a case changes the initial data unless the next case explicitly depends on that change. A typical sequence is:

1. **Browse:** compare the visible tree, article titles, category counts, and Uncategorized contents with the fixture's documented expectations: All 7, Workspace 3, Writing 2, Notes 1, Empty Category 0, Image Demos 3, and Uncategorized 1. Hidden Trash must stay out of active lists. Check category descendants and search results through the UI; sidebar selection must remain neutral gray during press, release, and focus changes, with matching capsule shapes for selected, hover, and pressed row backgrounds.
2. **Select on mouse down:** under Writing, select Selection A, then press and hold the primary mouse button on Selection B. From mouse-down through release, only B should have the normal light-gray card background with smooth rounded corners and its article should be displayed; neither row may turn blue. Repeat on A's row padding. Move focus to the document, click A to restore list focus, then verify Down selects B and Up returns to A without blue highlighting. A normal quick click cannot prove the held-button state.
3. **Create and edit:** select the case's category, click the plus-shaped New Article button in the document toolbar or press `⌘N`, and replace the selected title. Type the specified body. Confirm the new article appears in that category and that the editor receives focus. Repeat All/Uncategorized cases on fresh runs as required by their Given state.
4. **Switch modes:** use the single pencil button at the document toolbar's right edge, the View menu, and `⌘R` as specified by the case. Click the pencil to activate editing; click again to deactivate it and return to preview. The 32-by-32-point circular button has a light-gray active background and selected accessibility trait only in editor mode, regardless of the entry point used. Inspect its mode value and next-action help through accessibility; there is no eye button or outer capsule. Compare the rendered fixture with its Markdown: headings, lists, tables, image dimensions, internal article link, and fallback or installed optional runtimes. Check selection, focus, and undo after returning to the editor.
5. **Save and reopen:** save with `⌘S` when the case calls for explicit save, or wait for the observable saved-file result for an autosave case. Switch articles, quit, and reopen the same run. Confirm both content and category membership survived. Inspect only this run's database and document files if the Then clause requires storage assertions.
6. **Inspect appearance and input:** check gray hover/pressed feedback, compact margins, dark/light appearance, and the app icon where specified. E2E-009/010 check two approximately 14-point icons centered in 32-by-32-point controls with circular hover/pressed backgrounds at the toolbar's left and one 32-by-32-point circular editing toggle at the right with a centered pencil icon and a light-gray background only while editing is active. E2E-010 also checks neutral app/preview styling, retained expansion arrows, a capsule-shaped search field, toolbar alignment with search, and hiding/restoring both left columns at default and minimum sizes. The sidebar's former library-name/subtitle area is absent; its tree starts below the window-control safe area with only a small top inset. The category and article panels have rounded upper-right and lower-right corners, layered with categories above articles and articles above the document. Hover each panel's right-edge resize area: it must show a horizontal resize cursor and strengthen only its edge shadow, without a vertical divider line. Drag both resize areas and record the resulting column widths before hiding the drawer. Move the actual pointer between preview glyphs, whitespace, links, both divider edges, and the article list: whitespace uses an arrow, selectable glyphs an I-beam, links a pointing hand, and divider edges a horizontal resize cursor. Repeat after mode changes and hide/restore; there must be no flicker or stale I-beam in non-text regions. Across hide/restore, both columns slide together from the left while the document width changes with the exposed drawer; compare the document pane's right edge with the window's content edge at the start, intermediate frames, and end. It must stay fixed throughout; endpoint screenshots alone do not verify the transition. Reverse a transition before it finishes, check that the last request wins without a jump, and confirm that restoring at the same window width retains both dragged column widths and document/navigation state. The toolbar's top and bottom edges must stay at the same height without an extra titlebar row; the collapsed layout must leave horizontal clearance for the window controls. Verify a brief smooth transition with Reduce Motion off and no animation with it on; restore the original setting afterward. In both editor and preview, compare a wide document pane with the drawer hidden against the minimum window width with the drawer visible: text is centered at a maximum content width of 900 points, with approximately 16-point side insets when narrower and a 16-point top inset. The toolbar and scroll area still span the document pane; the vertical scrollbar stays on its right edge. Resizing must retain document content, selection, and undo history without resetting the viewport to the beginning. Markdown syntax highlighting and fixture media colors are content, not the UI theme, and remain unchanged. For Chinese input, use the actual macOS input method and record its name; `setMarkedText` in an XCTest does not substitute for this interaction.

For every case, follow its file's exact GWT values rather than treating this sequence as a blanket pass. Keep observations, detailed reports, logs, and screenshots in ignored `build/Test Runs/` or `build/test-results/`; record the outcome in [the manual E2E summary](e2e-test-result.md), not in case definitions. Full-app execution remains manual. Quit the Preview app before removing its run directory. Keep a failed run until its diagnosis is complete.

## Verify the Release app

REL-001 exercises the normal production identity and library bookmark. Perform it in a separate macOS test account so its production preferences are isolated from the account used for personal writing. Use only a newly materialized fixture copy available to that account.

1. Record `git rev-parse HEAD` before building `MWeb Lite.app` with `./scripts/build-app.sh release`, then prepare a fresh fixture, for example `python3 scripts/prepare-test-library.py 'build/Test Runs/release-001/Library'`. Release builds have no `run.json`; retain this full SHA and ensure the installed app is this exact build.
2. In the test account, install that unchanged bundle in the account's Applications folder and launch it through Finder. Keep its production bundle identifier. Do not use `--library`, the Preview app launcher, or a renamed preview bundle for this case.
3. Inspect the Finder and running Dock icon and the welcome screen's capsule-shaped library-picker button. Use File → Open / `⌘O` to select the copied fixture. Verify the expected categories and articles, then quit with `⌘Q`.
4. Launch the installed app normally again. Verify that it restores the selected fixture through the saved library bookmark and still displays the expected content and icon. Record the installed bundle location, revision, account isolation, and observed results.

This remains an end-to-end case, with Path `Release app`. A successful Preview app run does not pass it. Record its outcome in the manual E2E summary and keep detailed observations with the ignored local run artifacts; it is not included in the CI summary. No step requires opening a personal library.

E2E-006 verifies save/restart persistence and stable creation-time ordering: after saving A, edit older B with `Older article edit marker`, save, then return to A for the immediate-quit flush. B must remain after A before and after reopening, with unchanged creation-based date labels and repeated-day omissions.

E2E-015 uses the [Timeline fixture](../../Tests/Fixtures/Timeline/README.md). Prepare a fresh Preview run, apply its overlay before opening the app, then follow the case to inspect creation-date/text columns and square mosaics at normal and narrow article-list widths. Its common modification timestamp must not replace the six creation-month groups. MEDIA-001/002 and THUMB-001 cover extraction, index refresh, decoding, caching, and file boundaries; they do not establish the appearance or selection behavior of the assembled list.

E2E-016 uses the [Date Groups fixture](../../Tests/Fixtures/DateGroups/README.md) to check separate year/month headings, their two-level sticky behavior while scrolling, repeated-day labels, and search results in the real app. DATE-001 verifies creation-time adjacency with a fixed calendar and time zone, including midnight boundaries, conflicting modification dates, and missing creation dates without a modification-time fallback. The grouping helper preserves supplied order; the app displays creation time descending, ignores stored pin/custom-sort metadata for ordering, and offers no sort setting. DateGroups preserves its expected creation chronology while giving Previous Year a newer modification time and stored pin/sort metadata. SCROLL-002 measures selected-row visibility below the 68-point sticky-header area in the production timeline, which owns selection scrolling. Its inline rows check stable positions and an explicit native-anchor remount using the shared coordinator. A second hosted `LibraryView` with the real store and temporary Library/DateGroups data calls the native Up handler twice and checks both loaded selections after asynchronous document loading. Operating-system keyboard-event delivery still requires the full app.

E2E-017 checks the same light, translucent overlay treatment in the category tree, article list, editor, and preview. Use the [Scrollbars setup](../../Tests/Fixtures/Scrollbars/README.md): prepare a fresh run, apply DateGroups, import the committed 30-category SQL into that ignored runtime database in read/write mode, copy both existing Scroll long documents, and reopen. Expand/collapse Empty Category to change tree overflow without changing the selected category; use the short Uncategorized Note for the document comparison and Image Demos for preview image bounds. At fixed widths, compare each thumb while shown and after fading, then change between overflowing and short content. Content edges, wrapping, and selection-card widths must stay fixed without a reserved gutter. Check wheel input over both pinned article headings and drag every region's thumb. SCROLL-001 separately measures hosted article-list/editor geometry, shared scroller wiring, direct native wheel handling, and knob hit geometry. It does not establish full-app thumb dragging, fading, or the other regions' visual integration. Follow all four regions in E2E-017 before recording a pass.

E2E-018 checks the persistent local save-status icon immediately left of the editing toggle. Its fixed slot must remain visible in both modes: clock while unsaved, circular arrows while saving, circled check after success, and circled exclamation after failure. SAVE-001 covers actual autosave, a database lock that makes in-flight writes observable, edits during that save, conflict persistence after dismissing the alert, and successful retry. The status describes local disk saves, not cloud synchronization or continuous external-file monitoring.

## Record manual end-to-end results

[e2e-test-result.md](e2e-test-result.md) contains all 19 end-to-end cases (18 Preview app cases and REL-001), with `Case ID`, `Status`, `Commit SHA`, and `Outdated` columns. Record `Passed`, `Failed`, or `Skipped` only after an actual attempt. An unexecuted case keeps `—` in the last three columns. The recorded SHA is the full 40-character commit of the application actually tested, not the later commit that saves the result.

Build from a known committed revision. Before building, commit source, fixture, script, case-definition, or other non-report changes; only edits to the two result Markdown files may remain uncommitted. For a Preview app run, capture `baseCommit` from its `run.json`, not the current checkout after further work. If `workingTreeDirty` is true, confirm that only result files were dirty and verify the recorded source-file hashes/fingerprint against the build inputs. Do not label an app built from other uncommitted changes as the recorded commit. Run metadata identifies the binary's source; it does not prove that a case was executed.

After following one case's GWT and checking every Then assertion, refresh the main reference and record that case:

```sh
git fetch origin
python3 scripts/update-e2e-results.py \
  --case E2E-008 --status Passed --commit '<full tested commit SHA>' \
  --head-ref origin/main
```

Use the observed outcome, not the example's `Passed` by default. The command updates only that case's Status and Commit SHA, then refreshes Outdated for all cases. It does not run tests, fetch Git history, or substitute HEAD for the tested version. New recorded SHAs must resolve locally to the exact supplied commit. Preserve unexecuted cases and previous failed outcomes until a new execution supplies a result.

You may edit a case's Status and Commit SHA in the summary manually, keeping the full SHA inside backticks, then refresh derived freshness:

```sh
git fetch origin
python3 scripts/update-e2e-results.py --refresh --head-ref origin/main
python3 scripts/update-e2e-results.py --check
```

`--check` validates only the table's format and case coverage; it neither recomputes freshness nor verifies execution. Refresh requires complete Git history and rejects shallow repositories. If the checkout is shallow, fetch the full history with `git fetch --unshallow origin` before refreshing. A previously recorded SHA that is missing locally is conservatively marked `Yes`; retrieve that commit before treating the result as current.

Freshness compares **effective versions** of the tested SHA and main. For each, walk backward through first-parent history while the nonempty actual commit diff changes only `docs/testing/ci-test-result.md` and/or `docs/testing/e2e-test-result.md`. Compare the two resulting SHAs. This ignores result-recording commits on either side. A source, fixture, case-definition, other-documentation, or mixed report-and-source commit counts as a version change. This is a repository-wide version check, not an estimate of whether one case is affected.

For an executed case, Outdated is `Yes` when the effective versions differ or the tested commit cannot be resolved, and empty when they match. It is `—` when no result exists. Refresh changes only Outdated; it preserves the manually recorded outcome and tested SHA. Keep detailed logs and screenshots under ignored `build/`, and include the updated summary through the normal project PR workflow.

The **Update E2E result freshness** workflow maintains these flags after main changes. Code pushes wait for the CI publisher workflow to finish before refreshing; a skipped publisher does not trigger freshness, while a failed publisher still can. Pushes changing only the two summaries can refresh immediately. It creates a PR only when derived flags change, independently validates the update, then rebase merges and deletes its branch. The CI and E2E writers queue in a shared concurrency group, and unchanged output produces no PR. This workflow never executes E2E cases or changes Status or Commit SHA. It becomes active only after the new workflow is merged into the default branch.

## GitHub Actions coverage

A GitHub Actions **workflow** is the YAML-defined event, jobs, and steps under `.github/workflows/`. An **action** is a reusable step used by a workflow, such as `actions/checkout`; a step can also run a script directly. [Publish CI test results](../../.github/workflows/publish-ci-test-results.yml) and [Update E2E result freshness](../../.github/workflows/update-e2e-results.yml) are workflows that invoke this repository's Python scripts, rather than new reusable actions.

[The macOS workflow](../../.github/workflows/test.yml) validates case definitions and fixture references, runs XCTest and the WebKit integration program, and builds the Release application. The test methods carry explicit case IDs, and WebKit emits one structured record per reported case.

The collector combines the actual test reports into the `ci-case-results` artifact containing `case-results.json`, following [the result contract](test-cases.md#ci-result-contract). It includes only Path `CI` cases with an explicit result from that run. A build failure is not a failure for every case; a case that never started has no entry. The overall job can fail while individual completed cases have valid passing results.

To reproduce collection from files belonging to an actual CI execution, supply its run URL, tested SHA, and attempt number:

```sh
python3 scripts/collect-test-results.py \
  --xctest build/test-results/xctest.jsonl \
  --preview build/test-results/preview.jsonl \
  --run-url '<actual GitHub Actions run URL>' \
  --source-sha '<tested commit SHA>' --attempt 1 \
  --output build/test-results/case-results.json \
  --markdown build/test-results/ci-test-result.md
```

`--markdown` is optional and renders a local inspection copy. Do not attach a CI URL to results from a different local execution. Add `--require-xctest` when the XCTest runner succeeded and `--require-preview` when the WebKit runner succeeded: these flags require complete reporting for that successful runner. The workflow sets them from each runner's outcome. Failed or interrupted runners may supply partial observed results without those flags; absent results are never filled in. A complete baseline run currently produces 59 CI records: 54 XCTest cases and five WebKit cases, excluding local-only PV-005.

The runner has its own checkout and temporary data; it does not access a developer's library. CI does not currently drive the Preview app or Release app with mouse and keyboard or perform visual review. PV-005 and all full-app cases are excluded from the CI result summary because their Paths are local. A local run of the same command cannot substitute for CI evidence.

Before submitting a case or fixture change, run:

```sh
python3 scripts/check-test-cases.py
swift test
./scripts/test-preview.sh
./scripts/build-app.sh release
```

Also run the affected end-to-end cases when their behavior changes. Building via the Preview app launcher already builds the Release app; a second build is unnecessary when it is the same source revision.

## Maintain the case files

Keep the shared specification and links in [test-cases.md](test-cases.md). Store each case in `docs/testing/cases/<ID>.md` using the [copyable case file template](test-cases.md#case-file-template): one `Field` / `Content` table containing eight definition fields, with no title, headings, or content outside it. Follow that specification for field order, filename matching, line breaks, and pipe escaping. Definitions contain no Status or Evidence fields.

Keep IDs stable. Data links to fixture inputs where applicable; Verification contains the exact test selector or full-app instructions. Create separate cases when scope or required execution path differs. Update the GWT, fixture, and assertion together when behavior changes; do not edit an earlier execution result to imply the changed code passed.

`check-test-cases.py` validates case-file structure, stable IDs, index coverage, exact XCTest mappings, preview IDs, and fixture references. Result validation separately rejects malformed or unknown case records and cases whose Path is not CI. These checks cannot replace executing the actual assertions.

## CI result publication

[ci-test-result.md](ci-test-result.md) is the generated latest CI summary. Its two result columns are `Case ID` and `Status`, with IDs linked to their definitions. Shared CI run-attempt and tested-commit links appear before the table; per-case evidence and diagnostics remain in the artifact's three-field JSON records. `Passed`, `Failed`, and `Skipped` describe individual reported cases. Missing entries mean no result was published for those cases from that run; they are not implied passes or failures. The shared links identify the execution and tested source, so a summary does not automatically verify later edits.

The publication flow is:

1. CI collects per-case results and uploads the `ci-case-results` artifact. Raw JSON and logs remain artifacts, not repository files.
2. After a default-branch CI run completes, a trusted `workflow_run` publisher downloads and validates that run's artifact. It does not execute privileged publication code from a pull-request checkout.
3. The publisher accepts only a current eligible run and updates `docs/testing/ci-test-result.md` through a dedicated results PR. Independent validation checks the generated change before rebase merging it.
4. Stale runs are prevented from replacing newer results, and result-only updates are guarded against triggering an endless publication loop.

The existing CI publication cycle was verified by [CI run 39360230846](https://github.com/highestop/mweb-lite/actions/runs/39360230846), [publisher run 39360314868](https://github.com/highestop/mweb-lite/actions/runs/39360314868), and [results PR #7](https://github.com/highestop/mweb-lite/pull/7). The new E2E freshness workflow becomes active only after its workflow file reaches the default branch; this earlier CI result does not verify the new workflow.

Repository **Settings → Actions → General → Workflow permissions** must allow **Allow GitHub Actions to create and approve pull requests** for the publisher to create its results PR. The publisher does not submit approval reviews; it keeps the repository's default token permission at read and grants write permissions only to the publication job. This combined repository switch is enabled for this repository. If it is disabled later, publication cannot create its PR.

For a read-only check of an eligible completed default-branch push run, use an authenticated GitHub token and the repository name in the environment:

```sh
GITHUB_REPOSITORY=highestop/mweb-lite \
  python3 scripts/publish-test-results.py --run-id '<run-id>' --dry-run
```

The run's effective source version must match current main and its artifact must validate. This comparison requires complete Git history and ignores commits changing only the two result summaries, as described above, so report-only advances do not invalidate an otherwise eligible run. CI evidence retains the actual tested SHA, not the later main head. A PR run is not eligible, even with `--dry-run`. Dry-run validates and renders without writing locally or remotely. Live publication is restricted to the trusted `workflow_run` context; it is not a command for publishing a local or PR-branch report.

Both Markdown result summaries are committed. Keep raw JSON, detailed run reports, screenshots, recordings, generated libraries, and app bundles in workflow artifacts or ignored `build/test-results/` and `build/Test Runs/`. Recording a manual outcome or refreshing its Outdated field does not automate full-app execution.
