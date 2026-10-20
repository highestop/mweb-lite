| Field | Content |
| --- | --- |
| ID | EDIT-003 |
| Given | Selected text contains Chinese characters and an emoji. |
| When | Wrap it in bold markers, then toggle bold off. |
| Then | Text and UTF-16 selection ranges remain correct after both operations. |
| Level | Unit |
| Path | CI |
| Data | Inline |
| Verification | `MarkdownEditingTests/test_EDIT_003_FormattingPreservesUTF16Selections` |
