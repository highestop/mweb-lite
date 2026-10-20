| Field | Content |
| --- | --- |
| ID | STORE-001 |
| Verification | `LibraryStoreCreationTests/test_STORE_001_PendingCreationWaitsForPriorSaveAndInheritsCategory` |
| Given | A store has an edited article, selected category, and search text that would hide a new article. |
| When | Request creation and await pending writes. |
| Then | The old draft saves before creation; the new article inherits the category, is visible with cleared search, and opens in editor mode; busy/pending flags clear. |
| Level | Integration |
| Path | CI |
| Data | Inline |
