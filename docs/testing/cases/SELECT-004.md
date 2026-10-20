| Field | Content |
| --- | --- |
| ID | SELECT-004 |
| Given | A selection change from A to B is already busy. |
| When | Request A and then nil before B finishes loading. |
| Then | The pending target remains B and B becomes the loaded document. |
| Level | Integration |
| Path | CI |
| Data | Inline |
| Verification | `LibraryStoreSelectionTests/test_SELECT_004_SelectionWhileBusyDoesNotReplaceThePendingTarget` |
