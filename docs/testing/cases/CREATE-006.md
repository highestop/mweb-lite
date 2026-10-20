| Field | Content |
| --- | --- |
| ID | CREATE-006 |
| Given | A database trigger rejects insertion of category relationships. |
| When | Create in a category. |
| Then | Creation fails; article rows roll back, no relationship is added, and no new Markdown appears. |
| Level | Integration |
| Path | CI |
| Data | Inline |
| Status | CI passed |
| Verification | `MWebDocumentCreationTests/testFailedRelationshipInsertRollsBackArticleWithoutCreatingFile` |
| Evidence | [2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845) |
