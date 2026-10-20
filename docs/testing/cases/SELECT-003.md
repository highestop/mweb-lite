| Field | Content |
| --- | --- |
| ID | SELECT-003 |
| Given | B is indexed but its Markdown file has been removed. |
| When | Select B and await loading. |
| Then | An error appears in the store; selection and document return to A with A's content intact. |
| Level | Integration |
| Path | CI |
| Data | Inline |
| Verification | `LibraryStoreSelectionTests/test_SELECT_003_LoadFailureRestoresSelectionWithoutReplacingTheDocument` |
