| Field | Content |
| --- | --- |
| ID | DRAWER-002 |
| Verification | `DrawerWorkspaceLayoutTests/test_DRAWER_002_NativeScrollViewKeepsItsRightEdgeAfterSizeNegotiation` |
| Given | An `NSWindow` and `NSHostingView` mount the production `DrawerWorkspaceLayout` with a real `NSScrollView`, a visible legacy vertical scroller, and inline scrollable content. Its representable rounds its preferred width upward to an eight-backing-pixel grid to exercise the compatibility contract that a child may choose a size different from its proposal; this is not an assertion about default AppKit rounding. |
| When | Change each column's requested width and sample open, closed, and intermediate drawer progress in both directions while retaining the same hosted view tree. |
| Then | The actual native scroll view's right edge stays at the hosting view's right edge in window coordinates, and the vertical scrollbar keeps its original inset from that edge. The same native scroll view remains mounted throughout, and at least one measured native width differs from the proposed width. This component test samples layout states; it does not establish full-app animation behavior. |
| Level | Integration |
| Path | CI |
| Data | Inline |
