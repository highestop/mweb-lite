| Field | Content |
| --- | --- |
| ID | FOCUS-001 |
| Verification | `MarkdownEditorFocusTests/test_FOCUS_001_ResigningFocusCommitsCompositionToBinding` |
| Given | A native editor has marked Chinese text not yet committed to its binding. |
| When | Resign first responder, then return focus. |
| Then | Composition commits to the editor and binding, marked text clears, and the selection remains unchanged. |
| Level | Integration |
| Path | CI |
| Data | Inline |
