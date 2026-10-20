| Field | Content |
| --- | --- |
| ID | SELECT-001 |
| Verification | `LibraryStoreSelectionTests/test_SELECT_001_SelectionChangesBeforeSavingAndLoadingTheNextDocument` |
| Given | Article A has an unsaved draft and B is available. |
| When | Select B before the asynchronous save/load finishes, then await completion. |
| Then | Selected ID immediately becomes B while A's draft remains pending and the store reports an article switch separately from other busy work; after completion A is saved, B's content is loaded, and the article-switch flag clears. |
| Level | Integration |
| Path | CI |
| Data | Inline |
