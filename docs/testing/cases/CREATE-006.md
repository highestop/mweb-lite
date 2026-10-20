| Field | Content |
| --- | --- |
| ID | CREATE-006 |
| Verification | `MWebDocumentCreationTests/test_CREATE_006_FailedRelationshipInsertRollsBackArticleWithoutCreatingFile` |
| Given | A database trigger rejects insertion of category relationships. |
| When | Create in a category. |
| Then | Creation fails; article rows roll back, no relationship is added, and no new Markdown appears. |
| Level | Integration |
| Path | CI |
| Data | Inline |
