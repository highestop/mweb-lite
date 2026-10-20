| Field | Content |
| --- | --- |
| ID | STORE-002 |
| Given | A dirty draft conflicts with an externally edited file. |
| When | Request creation and await pending writes. |
| Then | Creation is blocked; the current document and draft remain, the article count does not grow, and external content is preserved. |
| Level | Integration |
| Path | CI |
| Data | Inline |
| Verification | `LibraryStoreCreationTests/test_STORE_002_ConflictingDraftPreventsCreationAndPreservesDraft` |
