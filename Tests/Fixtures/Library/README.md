# Full-app fixture

Synthetic data for the full application's end-to-end cases. The SQL, Markdown, images, and expected manifest are source fixtures and belong in Git. Generated SQLite databases, modified articles, screenshots, and app bundles belong under ignored `build/`.

| Category | Active articles, including descendants |
| --- | --- |
| All | Selection A, Selection B, Markdown Showcase, Uncategorized Note, 山间漫游 · 多图日记, 版式实验 · 不同比例, 图文笔记 · 细节与留白 |
| Workspace (101) | Selection A, Selection B, Markdown Showcase |
| Writing (102, child of Workspace) | Selection A (10001), Selection B (10002) |
| Notes (103, child of Workspace) | Markdown Showcase (10003) |
| Empty Category (104) | None |
| Image Demos (105) | 山间漫游 · 多图日记 (10006), 版式实验 · 不同比例 (10007), 图文笔记 · 细节与留白 (10008) |
| Uncategorized | Uncategorized Note (10004) |

There are seven active articles. Hidden Trash (10005) has state 0. Selection A starts first because timestamps are fixed in `seed.sql`; the original four active articles retain their order. Image Demos is a root category after Workspace and Empty Category. Unknown metadata and tag relationships are included to make accidental changes visible. `manifest.json` records the baseline expectations.

The three Chinese image articles contain four, six, and five images respectively. Their shared media is stored under `docs/media/10006/`; sharing this directory across articles is intentional. `10007.md` includes all six inputs so one narrow-window check covers every format and aspect ratio. Some references use MWeb's `-w` width markers. All six assets are original synthetic illustrations, not photographs: the SVGs contain vector shapes, while the PNG/JPEG images are separately generated raster artwork. Their combined size is under 100 KB.

| Media | Format and dimensions | Coverage |
| --- | --- | --- |
| [mountain.svg](docs/media/10006/mountain.svg) | SVG, 1200 × 720 | Landscape illustration |
| [panorama.svg](docs/media/10006/panorama.svg) | SVG, 1600 × 480 | Wide panorama |
| [portrait.svg](docs/media/10006/portrait.svg) | SVG, 720 × 1080 | Tall illustration |
| [square.png](docs/media/10006/square.png) | PNG, 800 × 800 | Square raster image |
| [detail.jpg](docs/media/10006/detail.jpg) | JPEG, 960 × 640 | Landscape raster image |
| [transparent.png](docs/media/10006/transparent.png) | PNG, 640 × 480 | Transparent image edges |

[E2E-014](../../../docs/testing/cases/E2E-014.md) checks all three articles, six media inputs, mode changes, scrolling, and narrow-window rendering. Look for `旅程结束。`, `版式实验结束。`, and `混排笔记结束。` in the final paragraphs respectively. No download or personal image library is needed.

Run `./scripts/run-preview-app.sh <run-name>` from the repository root to build and open an isolated app with a writable copy. Use a fresh run name per independent case. Never open this source directory as a library or store a `mainlib.db` here. See [the test guide](../../../docs/testing/test-guide.md) and [case catalog](../../../docs/testing/test-cases.md).

When changing this fixture, update the manifest, affected GWT cases, and fixture version together. Preserve each case's latest recorded result and tested revision until another execution replaces it; an earlier pass does not verify changed inputs. All text and artwork here were created for testing; there is no personal MWeb content.
