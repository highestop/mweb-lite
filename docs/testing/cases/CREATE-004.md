| Field | Content |
| --- | --- |
| ID | CREATE-004 |
| Given | A document already exists with the UUID generated for a fixed creation time. |
| When | Create again at the same time in another category. |
| Then | A creation conflict is returned; existing article rows, Markdown, and its original category remain unchanged. |
| Level | Integration |
| Path | CI |
| Data | Inline |
| Status | CI passed |
| Verification | `MWebDocumentCreationTests/testIdentifierCollisionPreservesExistingArticleAndFile` |
| Evidence | [2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845) |
