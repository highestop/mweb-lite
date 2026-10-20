| Field | Content |
| --- | --- |
| ID | FOCUS-002 |
| Given | An editor contains an undoable insertion and a selected range. |
| When | Move focus away and back, then undo. |
| Then | Selection and undo availability survive the focus round trip; undo restores the original text. |
| Level | Integration |
| Path | CI |
| Data | Inline |
| Status | CI passed |
| Verification | `MarkdownEditorFocusTests/testFocusRoundTripPreservesSelectionAndUndo` |
| Evidence | [2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845) |
