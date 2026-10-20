# Full-app fixture

Synthetic data for the full application's end-to-end cases. The SQL, Markdown, image, and expected manifest are source fixtures and belong in Git. Generated SQLite databases, modified articles, screenshots, and app bundles belong under ignored `build/`.

| Category | Active articles, including descendants |
| --- | --- |
| All | Selection A, Selection B, Markdown Showcase, Uncategorized Note |
| Workspace (101) | Selection A, Selection B, Markdown Showcase |
| Writing (102, child of Workspace) | Selection A (10001), Selection B (10002) |
| Notes (103, child of Workspace) | Markdown Showcase (10003) |
| Empty Category (104) | None |
| Uncategorized | Uncategorized Note (10004) |

Hidden Trash (10005) has state 0. Selection A starts first because timestamps are fixed in `seed.sql`. Unknown metadata and tag relationships are included to make accidental changes visible. `manifest.json` records the baseline expectations.

Run `./scripts/run-preview-app.sh <run-name>` from the repository root to build and open an isolated app with a writable copy. Use a fresh run name per independent case. Never open this source directory as a library or store a `mainlib.db` here. See [the test guide](../../../docs/testing/test-guide.md) and [case catalog](../../../docs/testing/test-cases.md).

When changing this fixture, update the manifest, affected GWT cases, and fixture version together. Preserve each case's latest recorded result and tested revision until another execution replaces it; an earlier pass does not verify changed inputs. All text and artwork here were created for testing; there is no personal MWeb content.
