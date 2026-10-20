| Field | Content |
| --- | --- |
| ID | EDIT-002 |
| Verification | `MarkdownEditingTests/test_EDIT_002_FencedCodeDoesNotContinueMarkdownLists` |
| Given | List-like text appears inside backtick/tilde code fences, with different fence lengths and indentation. |
| When | Compute newline edits inside and after fences. |
| Then | Code content does not gain Markdown list prefixes, indentation is retained, and list continuation resumes outside the closed fence. |
| Level | Unit |
| Path | CI |
| Data | Inline |
