| Field | Content |
| --- | --- |
| ID | FOCUS-004 |
| Verification | `MarkdownEditorFocusTests/test_FOCUS_004_DocumentChangeStartsAtTop` |
| Given | A production LibraryView is mounted in an NSHostingView and opens an isolated temporary library containing long Articles A and B. Article A's native editor has its caret and viewport at the end and contains an unsaved edit with a real native undo action. |
| When | Select B through LibraryStore, wait for its native editor to mount, and process another main-queue layout pass. Then select B's paragraph 145, scroll to it, and switch to preview and back without changing articles, inspecting native visibility and hit testing in both modes. |
| Then | Selecting B saves A's edit and creates a different native editor instance with a zero-length selection at offset zero and viewport at the top, both when mounted and after the additional layout pass. B's content remains unchanged and its undo manager does not inherit A's undo action. Switching modes within B preserves the same native editor and WebKit instances, the editor selection, and a nonzero scroll position. The inactive editor scroll view or WebKit view is natively hidden and returns no hit-test target; the active view is not hidden, and returning to editing restores focus. This hosted component test does not replace full-app scroll or visible pointer verification. |
| Level | Integration |
| Path | CI |
| Data | Inline |
