# MWeb Lite

A native macOS app for opening an existing MWeb document library, browsing its categories, and editing or previewing Markdown. It uses the original library directly. There is no import or conversion step.

## Run

Requires macOS 14 or later and Xcode Command Line Tools with Swift 5.9 or later.

The build generates the app icon from vector sources. Xcode 26 or later also compiles its native Icon Composer version. See [icon sources and attribution](Support/IconSource/README.md).

```sh
./scripts/build-app.sh
open "build/MWeb Lite.app"
```

Choose the library directory containing `mainlib.db` and `docs/`. The app remembers that directory. You can also open `Package.swift` in Xcode and run the `MWebLite` executable. The locally built app is ad hoc signed; it is not a notarized distribution.

For an isolated demo that never reads an existing library:

```sh
python3 scripts/create-demo-library.py
open "build/MWeb Lite.app" --args --library "$PWD/build/Demo Library"
```

The demo generator refuses to overwrite existing directories. `--library` does not change the remembered library.

## Included

- Native category tree, article list, title/summary search, and editor/preview modes. Switch modes from the View menu or with `⌘R`; the article uses the full window height.
- Create an article from the button beside search or `⌘N`. It belongs to the selected category and opens in the editor with its title selected. Creating from All or Uncategorized leaves it uncategorized.
- UTF-8 Markdown editing with native undo, find, Chinese input support, syntax colors, list continuation, indentation, and image paste/drop.
- Tables, task lists, strikethrough, footnotes, `[TOC]`, local images, MWeb image widths such as `![caption -w320](media/...)`, and `mweblib://{articleID}` links.
- Debounced autosave after 1.5 seconds, explicit save, and pending-save checks before switching documents, closing the window, or quitting.
- Refresh to reload changes made by MWeb. Save conflicts keep the edited text in the window instead of overwriting the external version.

| Shortcut | Action |
| --- | --- |
| `⌘O` | Select a library |
| `⌘N` | Create an article in the selected category |
| `⌘S` | Save |
| `⌘R` | Switch editor / preview |
| `⇧⌘R` | Refresh the library |
| `⌘B` / `⌘I` / `⌘K` | Bold / italic / link |
| `⌘F` | Find in the editor |
| `Tab` / `⇧Tab` | Indent / outdent |

## Data compatibility

Implementation was checked against the local MWeb app, its bundled help, and nono's `docs/mweb/database-guide.md` and `docs/mweb/docs-structure-guide.md`.

- `cat.uuid` and `cat.pid` form the tree; `cat.sort` controls tree order.
- `cat_article.rid` references `cat.uuid`; `cat_article.aid` references `article.uuid`. Multiple categories per article are preserved.
- Active articles have `state = 1`. Other states are hidden. Body files use `docs/{uuid}.md`; titles and summaries come from their contents.
- Saving replaces the existing Markdown file and updates only `article.dateModif`, in Unix seconds. Unknown columns, tags, category relationships, settings, and other MWeb tables are preserved.
- New articles use a timestamp identifier, a UTF-8 `docs/{uuid}.md` file, active article metadata, and an optional `cat_article` relation to the selected category. A failed creation rolls back its database changes and removes its new file.
- Pasted images use unique names in `docs/media/{uuid}/`. Removing their Markdown reference does not delete the files.
- An unsupported schema, missing file, invalid UTF-8, or a path outside the chosen library fails explicitly. Opening and browsing do not create a backup or rewrite files.

The current version uses pinned-first, most-recently-modified article ordering. MWeb's saved `sortType` is preserved but its undocumented numeric mappings are not interpreted. Selecting a category includes its descendants, with articles deduplicated. There is no category creation, deletion, publishing, sync, import/export, or other MWeb administration UI.

## Save recovery

Before the first write in a library session, the app makes a consistent SQLite backup at `.mweb-lite/backups/{session}/mainlib.db`, including committed WAL data. For each edited article, it preserves the original `{uuid}.md` and up to 20 recent Markdown snapshots in that session. Backup sessions have private filesystem permissions. Old sessions are retained.

Each save checks both the article metadata and file bytes for external edits, uses a short SQLite transaction and coordinated atomic file replacement, and restores the original Markdown if the database commit fails. File permissions are preserved. A conflict pauses autosave; copy the draft if needed before using **从磁盘重新载入…**. `⌘S` retries saving but does not bypass conflict checks.

SQLite and Markdown are separate files: a process crash or power loss between the file replacement and database commit is not a fully atomic cross-file transaction. Backups are recovery material, not a replacement for a complete library backup. For recovery, close both apps and preserve the current library before restoring a specific Markdown snapshot. The session database is from the first save, while each article's original snapshot is from its first edit; do not blindly restore the entire database over newer work. Simultaneously editing the same article in both apps remains best avoided.

## Rendering scope

Basic Markdown rendering is bundled and works offline. When MWeb Pro is installed locally, the preview reads its third-party MathJax, Mermaid, ECharts, and Prism runtime assets in place. These MWeb assets are not copied into this repository or the app. Without them, formulas and diagrams retain their source and fenced code remains readable without syntax colors.

This is a focused compatible editor, not a pixel-for-pixel replacement for every MWeb theme or extension. ECharts accepts JSON5 data configurations, not executable functions. HTML scripts, frames, and arbitrary styles are filtered. Local media access is limited to the selected library; database files and paths outside it are not exposed to the web view. Remote images can load over HTTPS when a document references them. The app does not upload or sync notes.

## Verify

See the [testing guide](docs/testing/test-guide.md) for test scope, authoring, and full-app verification. The [case specification and index](docs/testing/test-cases.md) links to [individual case files](docs/testing/cases), each with vertically arranged GWT, level, execution path, data source, and latest recorded result/evidence fields. Results live only in the case file, with their date and tested revision. `—` means no execution record; later code changes do not erase past results or extend them to untested revisions. Versioned synthetic inputs live in [Tests/Fixtures](Tests/Fixtures).

Generated libraries, app bundles, run reports, logs, and screenshots stay in ignored `build/`. Reports are not committed. Each case's evidence links to GitHub Actions or explicitly labeled `local-only` report paths.

```sh
python3 scripts/check-test-cases.py
swift test
./scripts/test-preview.sh
./scripts/build-app.sh release
```

For a full-app end-to-end run with an isolated fixture copy:

```sh
./scripts/run-preview-app.sh my-first-run
```

This creates `MWeb Lite Preview.app` with its own bundle identifier. The separate `PreviewTests.app` created by `test-preview.sh` tests only the WebKit component. GitHub Actions runs the catalog check, XCTest, WebKit integration, and release build; full-app UI results must be recorded separately.

Tests create synthetic temporary libraries. They cover article creation and category membership, waiting for pending writes, conflicts, rollback, unknown-field preservation, WAL backups, private backup permissions, snapshot retention, UTF-8/BOM/CRLF, path boundaries, Markdown text transformations, and native editor focus/Chinese composition. The separate preview test runs a real WKWebView from a standalone app bundle against temporary fixtures, with no SwiftPM resource fallback, and checks rendering and content isolation. MWeb-dependent rendering assertions run when the local runtime is available.

On restricted execution hosts, `NSFileCoordinator` and WebKit need normal macOS service access. Run tests outside that execution sandbox; no test needs a personal MWeb library.

SwiftUI/AppKit UI code lives in `Sources/MWebLite`, SQLite/file compatibility in `Sources/MWebCore`, and third-party renderer notices in `Sources/MWebLite/Resources/Preview-Libraries.txt`.
