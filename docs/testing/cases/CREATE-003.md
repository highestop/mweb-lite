| Field | Content |
| --- | --- |
| ID | CREATE-003 |
| Given | Category input is missing, SQL-shaped, or a path traversal string. |
| When | Attempt creation with each invalid category ID. |
| Then | Each attempt reports a missing category before creating backups, Markdown, or article rows. |
| Level | Integration |
| Path | CI |
| Data | Inline |
| Status | CI passed |
| Verification | `MWebDocumentCreationTests/testMissingCategoryRefusesCreationBeforeBackupOrFileChanges` |
| Evidence | [2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845) |
