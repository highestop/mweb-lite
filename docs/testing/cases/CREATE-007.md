| Field | Content |
| --- | --- |
| ID | CREATE-007 |
| Verification | `MWebDocumentCreationTests/test_CREATE_007_FailedCommitRemovesCreatedMarkdownAndRollsBackAllRows` |
| Given | A deferred constraint will reject the creation commit after the Markdown file exists. |
| When | Create in a category. |
| Then | The commit error is reported; article, relationship, and audit rows roll back; the newly created Markdown is removed. |
| Level | Integration |
| Path | CI |
| Data | Inline |
