| Field | Content |
| --- | --- |
| ID | DRAWER-001 |
| Verification | `DrawerGeometryTests/test_DRAWER_001_ColumnsSlideTogetherWhileDetailKeepsItsRightEdge` |
| Given | Inline window widths from 0 to 1380 points, a fixed height, requested column widths below/within/above their limits, and a 16-point layer overlap. |
| When | Calculate `DrawerGeometry` at closed, open, and intermediate progress values in both directions. |
| Then | Both columns keep their resolved widths and translate together; divider positions follow their content boundaries; the detail's content left edge follows drawer progress and its right edge stays at the window edge. Columns are fully outside the window when closed and start at the left edge when open. Width limits reserve 420 points for detail, reduce the article column before the category column, and shrink proportionally when both minimums cannot fit; all frames remain finite and nonnegative in size, with unchanged vertical bounds. |
| Level | Unit |
| Path | CI |
| Data | Inline |
