| Field | Content |
| --- | --- |
| ID | EDIT-001 |
| Given | Unordered/ordered lists, completed tasks, empty items, and blockquotes are at the caret. |
| When | Compute a newline edit. |
| Then | Lists/quotes continue with correct prefixes, ordered numbers increment, checked tasks reset, empty items exit, and resulting selections remain in bounds. |
| Level | Unit |
| Path | CI |
| Data | Inline |
| Status | CI passed |
| Verification | `MarkdownEditingTests/testListContinuationAndEmptyItemExit` |
| Evidence | [2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845) |
