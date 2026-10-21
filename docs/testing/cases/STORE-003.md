| Field | Content |
| --- | --- |
| ID | STORE-003 |
| Verification | LibraryStoreCreationTests/test_STORE_003_TrashUsesTargetAndMaintainsSelectionThroughLastArticle |
| Given | A temporary library with two articles and an edited current document. |
| When | Trash the other article, wait for pending writes, then trash the remaining article. |
| Then | The first deletion saves and retains the current draft/selection; the last deletion clears the editor, active list, and save status; finishing pending writes waits for both operations. |
| Level | Integration |
| Path | CI |
| Data | Inline |
