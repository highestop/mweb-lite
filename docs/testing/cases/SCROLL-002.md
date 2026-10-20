| Field | Content |
| --- | --- |
| ID | SCROLL-002 |
| Verification | `ArticleRowRevealTests/test_SCROLL_002_SelectionClearsStickyHeadersWithoutMovingVisibleRows` |
| Given | A real `NSWindow` and `NSHostingView` mount the production `ArticleTimelineList` with 18 inline articles represented by 80-point native rows. October 2026, September 2026, and October 2025 contain 4, 5, and 9 rows. An outer `ScrollViewReader` uses the same default `scrollTo` selection behavior as the library view, and the stacked sticky headers occupy 68 points at the viewport top. |
| When | Select row 9 at the year boundary and position its top 90 points below the viewport top. Change selection to row 8 and then row 7, followed by the already fully visible row 8. Scroll manually by 20 points and update the hosted view without changing the selected article. Finally move row 8's top to 24 points below the viewport top, explicitly mount a new production `ArticleRowRevealView` inside that native row, and configure it with the list's shared coordinator and the same selected ID. Measure row bounds against the real native `documentVisibleRect` and record the clip view's scroll origin. |
| Then | The newly revealed row 7 is fully inside the native visible rectangle: its top clears the 68-point sticky-header region and its bottom remains visible, within half a point. Selecting the already fully visible row 8 leaves the scroll origin unchanged. Updating the same selection after manual scrolling also preserves the user's scroll position. Mounting a new native anchor for that same selection does not replay its completed reveal request or move the vertical scroll origin, even with the row partly beneath the headers. This explicit native-anchor remount does not establish that `LazyVStack` evicted a row. These component assertions also do not establish operating-system keyboard-event delivery or full-app end-to-end behavior. |
| Level | Integration |
| Path | CI |
| Data | Inline |
