| Field | Content |
| --- | --- |
| ID | CREATE-008 |
| Given | The next document destination is a symlink to an outside path. |
| When | Attempt creation. |
| Then | Creation fails, no outside file is created, and the article count stays unchanged. |
| Level | Integration |
| Path | CI |
| Data | Inline |
| Verification | `MWebDocumentCreationTests/test_CREATE_008_SymlinkDestinationCannotCreateFileOutsideLibrary` |
