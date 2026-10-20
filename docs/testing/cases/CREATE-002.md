| Field | Content |
| --- | --- |
| ID | CREATE-002 |
| Given | A valid library is open without a selected category. |
| When | Create a document with `categoryID: nil`. |
| Then | The new article has no category relationship and is indexed as uncategorized. |
| Level | Integration |
| Path | CI |
| Data | Inline |
| Verification | `MWebDocumentCreationTests/test_CREATE_002_CreateWithoutCategoryIsUncategorized` |
