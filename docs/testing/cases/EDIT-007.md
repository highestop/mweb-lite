| Field | Content |
| --- | --- |
| ID | EDIT-007 |
| Given | Chinese text is selected. |
| When | Insert a Markdown link. |
| Then | The text becomes the link label and only the `https://` destination is selected for replacement. |
| Level | Unit |
| Path | CI |
| Data | Inline |
| Status | CI passed |
| Verification | `MarkdownEditingTests/testLinkSelectsDestinationForImmediateReplacement` |
| Evidence | [2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845) |
