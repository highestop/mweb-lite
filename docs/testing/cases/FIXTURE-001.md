| Field | Content |
| --- | --- |
| ID | FIXTURE-001 |
| Verification | `SharedFixtureTests/test_FIXTURE_001_EndToEndFixtureLoadsWithExpectedDocumentsAndCategories`; fixture `Tests/Fixtures/Library` |
| Given | The committed Library fixture's Markdown/media are copied into a temporary directory, and its schema/seed SQL builds a fresh database there. |
| When | Open that copy through production `MWebLibrary` and load its index and active documents. |
| Then | Seven active articles, trashed and uncategorized IDs, category hierarchy, and descendant article memberships match manifest version 2; Selection A remains newest; the three image demo articles belong to Image Demos; documents have nonempty content and matching titles; each image demo contains at least four Markdown images with safe relative paths to existing manifest media, covering all six new media files; opening creates no backup directory. |
| Level | Integration |
| Path | CI |
| Data | Fixture: [Library](../../../Tests/Fixtures/Library) |
