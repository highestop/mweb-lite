| Field | Content |
| --- | --- |
| ID | DRAWER-003 |
| Verification | `DrawerResizeViewTests/test_DRAWER_003_NativeHandleOwnsCursorAndDragUntilDisabledOrRemoved` |
| Given | A real `NSWindow` contains a `DrawerResizeView` above an `NSTextView`, with inline callback recordings and synthetic native mouse and cursor events. |
| When | Hit-test points inside and outside the handle, invoke repeated cursor updates after setting an I-beam, enter and exit the handle, drag while moving and reconfiguring it, then disable, re-enable, and invalidate it during interaction. |
| Then | Only the handle's bounds claim hits; its tracking area requests native cursor updates in the key window. Each cursor update restores horizontal resize, and exit leaves the destination cursor unchanged. Drag widths use the initial width and window-coordinate delta despite layout changes. Pointer events update hover and drag highlights correctly. Disabling through configuration and invalidating clear native interaction state without invoking resize or highlight callbacks, so representable updates and teardown cannot mutate parent SwiftUI state. Disabled or invalidated handles release tracking and hits, cannot resize, and do not alter the cursor; invalidation releases callbacks. This verifies native handler integration, not actual OS pointer routing or full-app hover appearance. |
| Level | Integration |
| Path | CI |
| Data | Inline |
