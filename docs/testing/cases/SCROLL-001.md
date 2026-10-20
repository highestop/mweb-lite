| Field | Content |
| --- | --- |
| ID | SCROLL-001 |
| Verification | `OverlayScrollbarsTests/test_SCROLL_001_OverflowDoesNotReserveRowWidth` |
| Given | A real `NSWindow` and `NSHostingView` mount the production `ArticleTimelineList` with 18 inline articles and native row probes. The viewport initially measures 360 by 400 points. The list has 20 points of total horizontal content padding, and its first row and enclosing native scroll view can be measured directly. |
| When | Set that native scroll view to legacy scroller style without changing system preferences. Retain the hosted hierarchy while alternating 18-row and one-row content at 360- and 420-point widths, then restore 18 rows at 360 points. Allow each update to settle and measure the actual native clip view and first row. |
| Then | The first native row and its enclosing scroll view remain the same instances through filtering and resizing. In every state, the clip width equals the hosting width and the row width equals the hosting width minus the declared 20-point content padding, within the test's half-point tolerance. The production configuration restores overlay scroller style, and each long-content state actually exceeds the viewport height. A scrollbar-width reduction in the row therefore fails even if the native scroller reports overlay style. This component test verifies layout integration; it does not establish full-app thumb appearance, fading, or pointer interaction. |
| Level | Integration |
| Path | CI |
| Data | Inline |
