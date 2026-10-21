| Field | Content |
| --- | --- |
| ID | TRASH-001 |
| Verification | LibraryManagementTests/test_TRASH_001_TrashChangesOnlyStateAndKeepsBytesAndRelationships |
| Given | A copied Library fixture with a multi-image document. |
| When | Trash document 10006 through production library code. |
| Then | Only article.state changes to 0; timestamps, unknown metadata, all Markdown/media bytes, category and tag relations remain; the article is hidden from active results and cannot be loaded for editing. |
| Level | Integration |
| Path | CI |
| Data | Fixture: [Library](../../../Tests/Fixtures/Library). |
