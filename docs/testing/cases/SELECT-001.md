| Field | Content |
| --- | --- |
| ID | SELECT-001 |
| Given | Article A has an unsaved draft and B is available. |
| When | Select B before the asynchronous save/load finishes, then await completion. |
| Then | Selected ID immediately becomes B while A's draft remains pending; after completion A is saved and B's content is loaded. |
| Level | Integration |
| Path | CI |
| Data | Inline |
| Status | CI passed |
| Verification | `LibraryStoreSelectionTests/testSelectionChangesBeforeSavingAndLoadingTheNextDocument` |
| Evidence | [2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845) |
