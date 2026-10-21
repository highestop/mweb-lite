| Field | Content |
| --- | --- |
| ID | TRASH-002 |
| Verification | LibraryManagementTests/test_TRASH_002_MissingTrashedAndFailedWritesPreserveDatabase |
| Given | A copied Library fixture and a trigger rejecting state changes. |
| When | Trash a missing article, an already trashed article, then an active article with the trigger installed. |
| Then | All attempts fail without modifying article rows or document/media bytes. |
| Level | Integration |
| Path | CI |
| Data | Mixed: [Library](../../../Tests/Fixtures/Library) plus a failure trigger. |
