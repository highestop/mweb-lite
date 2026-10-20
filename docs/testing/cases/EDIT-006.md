| Field | Content |
| --- | --- |
| ID | EDIT-006 |
| Verification | `MarkdownEditingTests/test_EDIT_006_OutdentClampsCursorInsideRemovedIndentation` |
| Given | The caret sits inside leading whitespace that will be removed. |
| When | Outdent the line. |
| Then | Text loses the indentation and the caret clamps to the beginning rather than becoming invalid. |
| Level | Unit |
| Path | CI |
| Data | Inline |
