| Field | Content |
| --- | --- |
| ID | SELECT-001 |
| Verification | `LibraryStoreSelectionTests/test_SELECT_001_SelectionChangesBeforeSavingAndLoadingTheNextDocument` |
| Given | Newer article A has an unsaved draft and older B is available. Their creation timestamps determine their display order. |
| When | Select B before the asynchronous save/load finishes, then await completion. Edit B, flush its pending save, and refresh the store. |
| Then | Selected ID immediately becomes B while A's draft remains pending and the store reports an article switch separately from other busy work; after completion A is saved, B's content is loaded, and the article-switch flag clears. Editing and saving older B leaves both creation timestamps and the A-before-B order unchanged, including after refresh. |
| Level | Integration |
| Path | CI |
| Data | Inline |
