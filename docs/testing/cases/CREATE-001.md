| Field | Content |
| --- | --- |
| ID | CREATE-001 |
| Verification | `MWebDocumentCreationTests/test_CREATE_001_CreateUsesSelectedCategoryUUIDAndReopensAsEditableDocument` |
| Given | A temporary library has parent/child categories, an existing article, unknown columns/defaults, and an unrelated table. |
| When | Create in the child category at a fixed time, reopen, and edit the new document. |
| Then | A unique numeric UUID, default title/content, timestamps, and child UUID relationship are written; unrelated rows/defaults survive; backup represents the pre-create database; the document reopens and saves. |
| Level | Integration |
| Path | CI |
| Data | Inline |
