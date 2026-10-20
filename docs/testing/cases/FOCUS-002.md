| Field | Content |
| --- | --- |
| ID | FOCUS-002 |
| Verification | `MarkdownEditorFocusTests/test_FOCUS_002_FocusRoundTripPreservesSelectionAndUndo` |
| Given | A mounted editor contains an undoable insertion and a selected body range; LibraryStore is in editor mode. |
| When | Switch to preview and back through LibraryStore.setMode, process the resulting focus request, then send undo and a key-down through the window first responder. Also queue another return-to-edit request and cancel it by switching back to preview before it executes. |
| Then | Returning to editor requests focus with preserve-selection intent; the production coordinator restores the editor as first responder without selecting the title, consumes the request, preserves native undo, and publishes subsequent typing to the binding. Full-app undo-to-preview synchronization is verified by E2E-005. An unconsumed request cancelled by preview does not take focus. |
| Level | Integration |
| Path | CI |
| Data | Inline |
