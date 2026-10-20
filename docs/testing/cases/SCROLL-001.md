| Field | Content |
| --- | --- |
| ID | SCROLL-001 |
| Verification | `OverlayScrollbarsTests/test_SCROLL_001_OverflowDoesNotReserveRowWidth` |
| Given | A real `NSWindow` and `NSHostingView` mount the production `ArticleTimelineList` with 18 inline articles and native row probes. The viewport initially measures 360 by 400 points. The list has 20 points of total horizontal content padding, and its first row and enclosing native scroll view can be measured directly. |
| When | Set that native scroll view to legacy scroller style without changing system preferences. Update the unchanged 18-row content again, then retain the hosted hierarchy while alternating 18-row and one-row content at 360- and 420-point widths and restoring 18 rows at 360 points. Allow each update to settle and measure the actual native clip view and the first row's bounds converted into hosting coordinates. |
| Then | The first native row and its enclosing scroll view remain the same instances through content updates, filtering, and resizing. In every state, the native scroll view and clip width equal the hosting width; the scroll view's left and right edges match the host; and the row remains exactly 10 points inside both hosting edges, with width equal to the hosting width minus 20 points, within the test's half-point tolerance. The production configuration retains overlay style and an enabled native vertical scroller with automatic hiding, including after an update that does not change row count. Each long-content state actually exceeds the viewport height. Both a scrollbar-width reduction and a constant-width row shifted sideways therefore fail. This component test verifies layout integration; it does not establish full-app thumb appearance, fading, or pointer interaction. |
| Level | Integration |
| Path | CI |
| Data | Inline |
