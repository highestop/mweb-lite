# Testing guide

Use [test-cases.md](test-cases.md) for the shared case format and index. Each case has its own file under [cases/](cases/) describing what must work, how it is verified, and its latest recorded execution result. Use committed synthetic fixtures to reproduce full-app cases. A successful build alone does not verify any user interaction.

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
| `CI` | GitHub Actions runs the checked-out revision and scripts on its macOS runner. | The 43 XCTest cases and baseline WebKit cases PV-001 through PV-004. |
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
| `scripts/prepare-test-library.py` | Materializes a runnable library from the full-app fixture. |
| `scripts/run-preview-app.sh` | Builds and starts the full Preview app with a copied fixture library for end-to-end tests. |

Run all 43 cataloged XCTest cases, or select a class or method while investigating a change:

```sh
swift test
swift test --filter MarkdownEditingTests
swift test --filter LibraryStoreSelectionTests/testSelectionChangesBeforeSavingAndLoadingTheNextDocument
```

To retain a log without losing the command's failure status:

```sh
mkdir -p build/test-results
set -o pipefail
swift test 2>&1 | tee build/test-results/swift-test.log
```

Use a fresh log name when keeping multiple runs. On a restricted execution host, a failure to start WebKit or use `NSFileCoordinator` may be an environment problem. Record the diagnostic and mark that execution `Blocked`; rerun in a normal macOS session before claiming a pass. A local diagnostic does not change the recorded result of a separate CI execution.

## Write automated tests

Start with a case file in **Given / When / Then (GWT)** form. Given identifies the exact starting state, When describes one action or sequence, and Then states observable results. Name the XCTest method after the behavior and link that method in the case's Verification field. Keep failure diagnostics specific enough to identify which assertion failed.

A unit test can directly mirror GWT. This example uses the existing Markdown editing API:

```swift
func testBoldPreservesUnicodeSelection() {
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

The temporary app and mutable fixture copy are removed when the script exits. The script preserves its result log as `build/test-results/preview-<UTC timestamp>.log`; use the printed path as evidence. It reports `PASS PV-001` through `PASS PV-004`, then either `PASS PV-005` or `SKIP PV-005`. A nonzero exit is a failure, not a partial pass.

The baseline rendering runs with optional runtimes disabled even when MWeb is installed. MathJax, Mermaid, ECharts, and Prism assertions depend on the optional runtime assets that the production preview reads from a local MWeb installation. PV-005 therefore uses the `Local script` path. Record whether these assets were available. If they are absent, record `Skipped` for that execution; the baseline cases must still pass. A CI skip does not establish PV-005's local result.

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

To prepare only a library for a targeted investigation:

```sh
python3 scripts/prepare-test-library.py 'build/Test Runs/fixture-check/Library'
```

The destination must be a new directory inside this repository's ignored `build/`. The script creates `mainlib.db` from `schema.sql` and `seed.sql`, copies document/media files, and checks the fixture manifest. It does not read an existing MWeb library. Use the launcher for catalog end-to-end runs so their app and run metadata are retained together.

Execute each full-app case from its documented Given state. Use a fresh run after a case changes the initial data unless the next case explicitly depends on that change. A typical sequence is:

1. **Browse:** compare the visible tree, article titles, category counts, and Uncategorized contents with the fixture's documented expectations: All 4, Workspace 3, Writing 2, Notes 1, Empty Category 0, and Uncategorized 1. Hidden Trash must stay out of active lists. Check category descendants and search results through the UI.
2. **Select on mouse down:** under Writing, select Selection A, then press and hold the primary mouse button on Selection B. Observe B's selected background before releasing. Check that A does not become blue, and that B remains selected after release. A normal quick click cannot prove the intermediate state.
3. **Create and edit:** select the case's category, click New Article or press `⌘N`, and replace the selected title. Type the specified body. Confirm the new article appears in that category and that the editor receives focus. Repeat All/Uncategorized cases on fresh runs as required by their Given state.
4. **Switch modes:** use the View menu and `⌘R`. Compare the rendered fixture with its Markdown: headings, lists, tables, image dimensions, internal article link, and fallback or installed optional runtimes. Use actual mouse and keyboard interaction for the relevant case.
5. **Save and reopen:** save with `⌘S` when the case calls for explicit save, or wait for the observable saved-file result for an autosave case. Switch articles, quit, and reopen the same run. Confirm both content and category membership survived. Inspect only this run's database and document files if the Then clause requires storage assertions.
6. **Inspect appearance and input:** check hover/pressed feedback, compact margins, dark/light appearance, and the app icon where specified. For Chinese input, use the actual macOS input method and record its name; `setMarkedText` in an XCTest does not substitute for this interaction.

For every case, follow its file's exact GWT values rather than treating this sequence as a blanket pass. Keep reports, logs, and screenshots in ignored `build/Test Runs/` or `build/test-results/`; do not commit run reports. Record the latest result and a dated evidence reference in that case file. Quit the Preview app before removing its run directory. Keep a failed run until its diagnosis is complete.

## Verify the Release app

REL-001 exercises the normal production identity and library bookmark. Perform it in a separate macOS test account so its production preferences are isolated from the account used for personal writing. Use only a newly materialized fixture copy available to that account.

1. Build `MWeb Lite.app` with `./scripts/build-app.sh release` and prepare a fresh fixture, for example `python3 scripts/prepare-test-library.py 'build/Test Runs/release-001/Library'`.
2. In the test account, install that unchanged bundle in the account's Applications folder and launch it through Finder. Keep its production bundle identifier. Do not use `--library`, the Preview app launcher, or a renamed preview bundle for this case.
3. Inspect the Finder and running Dock icon. Use File → Open / `⌘O` to select the copied fixture. Verify the expected categories and articles, then quit with `⌘Q`.
4. Launch the installed app normally again. Verify that it restores the selected fixture through the saved library bookmark and still displays the expected content and icon. Record the installed bundle location, revision, account isolation, and observed results.

This remains an end-to-end case, with Path `Release app`. A successful Preview app run does not pass it. If there is no recorded execution, use `—`; if a required test environment prevents an attempted execution, record `Blocked` and its cause. No step requires opening a personal library.

## GitHub Actions coverage

[The macOS workflow](../../.github/workflows/test.yml) runs on pushes and pull requests. It validates the case catalog and fixture references, runs `swift test`, runs the WebKit integration test program, and builds the Release application.

The runner has its own checkout and temporary data; it does not access a developer's library. Optional installed-MWeb rendering may be skipped there. CI does not currently drive the Preview app or Release app with mouse and keyboard, perform visual review, or automatically update case results. Its passing result is evidence for the assertions that actually ran, not for the full-app end-to-end cases. Running the same commands locally is useful evidence for `Local script`, but cannot be recorded as `CI passed`.

Before submitting a case or fixture change, run:

```sh
python3 scripts/check-test-cases.py
swift test
./scripts/test-preview.sh
./scripts/build-app.sh release
```

Also run the affected end-to-end cases when their behavior changes. Building via the Preview app launcher already builds the Release app; a second build is unnecessary when it is the same source revision.

## Maintain the case files

Keep the shared specification and links in [test-cases.md](test-cases.md). Store each case in `docs/testing/cases/<ID>.md`, with `# <ID>` followed by nine `##` headings in this order: `Given`, `When`, `Then`, `Level`, `Path`, `Data`, `Status`, `Verification`, and `Evidence`. Put each field's content below its heading in a single vertical flow. This preserves the same ten items of information without a wide table. The index links to cases and does not duplicate their results.

Keep IDs stable. Data links to fixture inputs where applicable; Verification contains the exact test selector or full-app instructions. Create separate cases when scope or required execution path differs. **Status records the latest recorded execution result for that case's Path.** If none exists, put `—` in Status and Evidence; this is an empty marker, not a test result.

`check-test-cases.py` checks case-file structure, unique IDs, index coverage, complete XCTest mappings, preview case IDs, result values, fixture links, and evidence reference formats. Local ignored reports need not exist in a CI checkout. The checker does not execute cases or prove their results; review the actual logs and observations before recording them.

| Status | Meaning |
| --- | --- |
| `CI passed` | The case's assertions actually ran and passed in the linked CI job for the recorded source and fixture revision. |
| `Local script passed` | The documented script actually ran locally and every assertion passed for the recorded revision and environment. It does not prove a CI run passed. |
| `Preview app passed` | The complete Preview app was exercised through the documented actions and every Then assertion was observed. |
| `Release app passed` | The normal Release app was exercised through its documented installation and launch flow, and every Then assertion was observed. |
| `Failed` | The case ran and at least one expected result was not met. Include actual versus expected behavior. |
| `Blocked` | The case could not be completed because a required environment, runtime, or setup was unavailable. Include the cause. |
| `Skipped` | A documented optional check was deliberately omitted, for example because MWeb rendering runtimes are not installed. This is not a pass. |

A passing result must match the case's Path. A local rerun does not replace a CI result, and a Preview app observation cannot become `Release app passed`. Do not invent `Blocked` or `Skipped` for a case that has no execution record.

Keep run reports, logs, screenshots, and recordings outside Git, under ignored `build/test-results/` or `build/Test Runs/`. Each case's Evidence field retains the run date and source revision, plus a GitHub Actions URL or a reference labeled `local-only` to an ignored report. Local reports are not expected to be available to CI or other checkouts. Include these details in the report or CI evidence:

- Case IDs, Level, executed Path, and result; date with timezone; tester or CI run URL.
- Source revision and fixture revision. If testing uncommitted work, say so and retain the relevant diff or source snapshot; do not label it as an unchanged commit.
- macOS version, relevant Swift/Xcode version, and optional MWeb runtime availability. Include input method and appearance when they affect the case.
- Exact command or full-app run name, actions actually performed, and observations. Link logs, screenshots, video, or saved-data checks when they prove the result.

A screenshot proves a visible state, not how it was reached or whether a save survived restart. Record the action sequence and persisted-data check for those cases. Mouse-down timing may need a held-button screenshot or video. A green build, a related test, a past assistant statement, or a skipped assertion is never evidence of a case pass.

Code, fixture, or case changes do not clear the last result. Keep its execution date and tested revision so an earlier pass is not mistaken for verification of the changed version. Replace Status and Evidence only when a newer execution on that case's Path is recorded. A component pass never proves a full-app flow; future automated end-to-end cases can use `CI passed` when CI actually performs and verifies their complete flow.

For each behavior change, update its GWT case, assertions, and fixture inputs as needed, then run the affected checks and record their actual results. Preserve existing results if no newer run exists; use `—` for cases with no execution record.
