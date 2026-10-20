| Field | Content |
| --- | --- |
| ID | FOCUS-004 |
| Verification | `MarkdownEditorFocusTests/test_FOCUS_004_DocumentChangeStartsAtTop` |
| Given | A native scroll view and Markdown text view contain a long Article A with the caret and viewport at its end. |
| When | Load long Article B through the production editor coordinator and process the next main-queue layout pass. Then rapidly load C and D, immediately place the caret at D's end, insert text, and scroll to that caret before queued resets finish. |
| Then | B starts with a zero-length selection at offset zero and its viewport at the top, immediately and after the queued layout pass. Stale resets from rapid switches do not overwrite D's content, user selection, edit, or new scroll position. |
| Level | Integration |
| Path | CI |
| Data | Inline |
