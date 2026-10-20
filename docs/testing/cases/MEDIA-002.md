| Field | Content |
| --- | --- |
| ID | MEDIA-002 |
| Verification | `MarkdownImageReferencesTests/test_MEDIA_002_IndexReadsLateImagesAndUpdatesSavedArticleReferences` |
| Given | An isolated copy of the shared library includes its three image-demo articles and a generated note whose first image and reference definition are beyond 64 KiB. |
| When | Load the production library index, then save replacement image references and refresh the edited row with updating(document:); finally save content with no images. |
| Then | The image-demo rows expose their first four source-order images, and the late image is included despite being beyond the summary prefix. Existing title/excerpt semantics remain unchanged. Indexing changes neither the Markdown nor database and creates no backup. Updating the matching saved document replaces or clears image references while preserving row metadata; updating a different article leaves it unchanged. Reloading the index agrees with the refreshed row. |
| Level | Integration |
| Path | CI |
| Data | Mixed: [Library](../../../Tests/Fixtures/Library) plus generated long Markdown and saved replacements |
