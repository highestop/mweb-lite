| Field | Content |
| --- | --- |
| ID | EDIT-005 |
| Given | A multiline selection ends exactly at the next line's start. |
| When | Indent and then outdent. |
| Then | Only selected lines change; the following line remains unchanged and the original text/selection are restored. |
| Level | Unit |
| Path | CI |
| Data | Inline |
| Verification | `MarkdownEditingTests/test_EDIT_005_IndentExcludesNextLineAtSelectionBoundary` |
