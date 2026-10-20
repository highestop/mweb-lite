| Field | Content |
| --- | --- |
| ID | SELECT-004 |
| Verification | `LibraryStoreSelectionTests/test_SELECT_004_SelectionWhileBusyDoesNotReplaceThePendingTarget` |
| Given | The store is in preview mode and a selection change from A to B is already busy. |
| When | Request A, then nil, an editor-mode change, and article creation before B finishes loading; request editor mode again after completion. |
| Then | During the switch the pending target remains B, preview mode and its focus state stay unchanged, and no article or document file is created. B becomes the loaded document and the article-switch flag clears; changing mode after completion succeeds and requests editor focus. |
| Level | Integration |
| Path | CI |
| Data | Inline |
