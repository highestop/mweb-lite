| Field | Content |
| --- | --- |
| ID | CREATE-005 |
| Given | The next generated UUID collides first with an unindexed Markdown file, then with an existing media directory. |
| When | Attempt creation for each collision. |
| Then | Neither existing data nor the index is overwritten, and the media collision does not create Markdown. |
| Level | Integration |
| Path | CI |
| Data | Inline |
| Verification | `MWebDocumentCreationTests/test_CREATE_005_UnindexedFileAndMediaCollisionsAreNotOverwritten` |
