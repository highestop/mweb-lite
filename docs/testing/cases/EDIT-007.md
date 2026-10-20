| Field | Content |
| --- | --- |
| ID | EDIT-007 |
| Given | Chinese text is selected. |
| When | Insert a Markdown link. |
| Then | The text becomes the link label and only the `https://` destination is selected for replacement. |
| Level | Unit |
| Path | CI |
| Data | Inline |
| Verification | `MarkdownEditingTests/test_EDIT_007_LinkSelectsDestinationForImmediateReplacement` |
