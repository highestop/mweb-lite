| Field | Content |
| --- | --- |
| ID | SAVE-001 |
| Verification | `LibraryStoreSelectionTests/test_SAVE_001_StatusTracksAutosaveInFlightEditsAndRetry` |
| Given | A new store and an isolated inline library with two articles; a second SQLite connection can briefly hold the writer lock. |
| When | Open the library, edit and await automatic saving, hold the writer lock during a manual save and edit again while saving, then release it. Cause an external-file conflict, dismiss its error, restore the fixture's original file, and retry saving. Switch editor/preview modes. |
| Then | No document reports unavailable; a loaded document reports saved; edits report unsaved until actual automatic saving completes. The held save reports saving, including a newer in-flight edit, and reports saved only after the latest draft reaches disk. A conflict reports failed and preserves both draft and external file; dismissing the alert does not clear failed status. Successful retry reports saved with matching disk content, and mode changes retain it. |
| Level | Integration |
| Path | CI |
| Data | Inline |
