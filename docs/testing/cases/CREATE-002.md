| Field | Content |
| --- | --- |
| ID | CREATE-002 |
| Given | A valid library is open without a selected category. |
| When | Create a document with `categoryID: nil`. |
| Then | The new article has no category relationship and is indexed as uncategorized. |
| Level | Integration |
| Path | CI |
| Data | Inline |
| Status | CI passed |
| Verification | `MWebDocumentCreationTests/testCreateWithoutCategoryIsUncategorized` |
| Evidence | [2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845) |
