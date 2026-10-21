| Field | Content |
| --- | --- |
| ID | STORE-005 |
| Verification | LibraryStoreCreationTests/test_STORE_005_CategoryOperationsRefreshCountsAndKeepCurrentEditor |
| Given | A temporary library with one categorized article and a modified draft. |
| When | Create and rename a child, delete the selected parent, then save another edit. |
| Then | The draft is saved before management writes; the child survives at root, selection falls back to All, counts/memberships refresh, and the current article remains editable without a false metadata conflict. |
| Level | Integration |
| Path | CI |
| Data | Inline |
