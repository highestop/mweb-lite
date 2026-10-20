| Field | Content |
| --- | --- |
| ID | EDIT-004 |
| Verification | `MarkdownEditingTests/test_EDIT_004_ItalicCanBeAppliedInsideBoldAndToggledOff` |
| Given | Chinese/emoji content is already bold, with either its inner text or whole markup selected. |
| When | Apply italic and then toggle it off. |
| Then | Italic nests inside bold; toggling restores bold without removing its markers. |
| Level | Unit |
| Path | CI |
| Data | Inline |
