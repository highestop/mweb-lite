| Field | Content |
| --- | --- |
| ID | MEDIA-001 |
| Verification | `MarkdownImageReferencesTests/test_MEDIA_001_ImageReferencesFollowMarkdownOrderAndIgnoreCode` |
| Given | Inline Markdown contains fenced, indented, and inline code, comments, escaped image markers, a normal list image, nested alt text with MWeb width hints, balanced/escaped destination parentheses, reference-style images, HTML image tags, and more than four visible images. |
| When | Extract image references using the default limit, a smaller limit, zero, and an excessive limit; also parse collapsed/shortcut references, repeated destinations, remote URLs, and malformed or unresolved images. |
| Then | At most the first four rendered image destinations are returned in source order, including repeated occurrences. Code, comments, escaped image markers, malformed images, and reference-definition titles do not become thumbnails. Definitions are resolved without case or whitespace differences; Markdown escapes and common HTML entities are decoded, width hints stay out of the destination, and extraction performs no file or network resolution. |
| Level | Unit |
| Path | CI |
| Data | Inline |
