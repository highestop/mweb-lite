| Field | Content |
| --- | --- |
| ID | THUMB-001 |
| Verification | `ArticleThumbnailTests/test_THUMB_001_ConfinedImagesDecodeCacheAndIgnoreObsoleteLoads` |
| Given | A disposable copy of the Library fixture's documents and six image assets, plus an inline one-pixel GIF with red and blue frames and generated files with an encoded-space name, an outside-library symlink, an external-resource SVG, invalid bytes, and an oversized payload. Controlled completion gates provide delayed image results without network access. |
| When | Load the PNG, JPEG, all three SVG fixtures, and generated GIF with the production thumbnail loader, repeat a request, resolve local and HTTP(S) references, attempt unsafe or invalid loads, cancel a cached request, and complete older row requests after newer ones. |
| Then | All six fixture images produce nonempty pixels with the expected aspect ratio and a maximum dimension of 256 pixels; the GIF thumbnail shows its red first frame; repeated requests reuse the decoded image. Encoded spaces, an in-library `../media` reference, library-root-relative paths, and explicit `mweblite://library` URLs resolve correctly. Plain and percent-encoded traversal outside the library, symlink escape, file URLs, missing library roots, and SVG external resources are rejected; invalid, missing, and oversized images fail. HTTP(S) URL resolution is accepted without exercising a live server. Cancelled requests cannot publish an image, and obsolete completions cannot overwrite a reused row's current image. This component test does not verify full-app thumbnail appearance or network delivery. |
| Level | Integration |
| Path | CI |
| Data | Mixed: [Library media](../../../Tests/Fixtures/Library/docs/media/10006) plus an inline two-frame GIF, generated unsafe files, and controlled asynchronous completions. |
