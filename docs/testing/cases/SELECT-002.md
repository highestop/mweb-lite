| Field | Content |
| --- | --- |
| ID | SELECT-002 |
| Verification | `LibraryStoreSelectionTests/test_SELECT_002_SaveConflictRestoresSelectionAndPreservesTheDraft` |
| Given | A's draft conflicts with an external edit. |
| When | Select B and await the failed save. |
| Then | Selection initially targets B, then returns to A with its draft and error; neither external A nor B is overwritten. |
| Level | Integration |
| Path | CI |
| Data | Inline |
