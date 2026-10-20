| Field | Content |
| --- | --- |
| ID | FOCUS-003 |
| Given | A new Markdown heading contains Chinese text and an emoji, or the document is empty. |
| When | Ask the native editor to select its title. |
| Then | Only heading text is selected using valid Unicode ranges; empty content selects the zero-length range at the start. |
| Level | Integration |
| Path | CI |
| Data | Inline |
| Verification | `MarkdownEditorFocusTests/test_FOCUS_003_NewDocumentFocusSelectsUnicodeTitleOnly` |
