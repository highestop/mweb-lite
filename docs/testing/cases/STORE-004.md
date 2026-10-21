| Field | Content |
| --- | --- |
| ID | STORE-004 |
| Verification | LibraryStoreCreationTests/test_STORE_004_ConflictingDraftBlocksManagementWrites |
| Given | A temporary library whose current edited draft conflicts with an external Markdown change. |
| When | Attempt document trash, category creation, rename, and deletion. |
| Then | Each operation is blocked before its structural write; the draft remains, the original category survives, and the article stays active. |
| Level | Integration |
| Path | CI |
| Data | Inline |
