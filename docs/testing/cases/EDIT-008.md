| Field | Content |
| --- | --- |
| ID | EDIT-008 |
| Verification | `MarkdownEditingTests/test_EDIT_008_LinePrefixCanBeToggledWithoutIncludingNextLine` |
| Given | A selection spans Chinese and emoji lines but stops before another line. |
| When | Toggle blockquote prefixes on and off. |
| Then | Only selected lines change and toggling restores the original text. |
| Level | Unit |
| Path | CI |
| Data | Inline |
