# Preview integration fixtures

These synthetic files are the source data for `scripts/test-preview.sh` and cases `PV-001`–`PV-005` in the [case index](../../../docs/testing/test-cases.md).

- `rendering.md`: headings, GFM table and task list, TOC, footnote, article link, image sizing, math, Swift code, Mermaid, ECharts, and deliberately unsafe HTML. The unsafe examples test sanitization; they are not instructions to execute.
- `media/test.png`: a 4 × 4 PNG used to verify local image loading and MWeb's image-width syntax.

The script passes this directory as `MWEB_PREVIEW_FIXTURES` and a fresh temporary directory as `MWEB_PREVIEW_RUNTIME_ROOT`. The harness copies the Markdown and media into that temporary library before reading them. The symlink and outside-library target used by `PV-001` are created only inside the temporary directory. The script deletes the directory and `PreviewTests.app` on exit; logs remain in ignored `build/test-results/`.

`PV-001`–`PV-004` use bundled preview resources. `PV-005` also needs the optional MathJax, Mermaid, ECharts, and Prism assets from a local MWeb Pro installation. Those assets are read from the installed app and are not copied into Git. Without the installation, the harness prints `SKIP PV-005`; a skip is not a pass.

Edit these source fixtures and their matching assertions together. Run the script again after changes and record the new results in the individual case files. Preserve the last recorded result until another execution replaces it. The harness is a WebKit component integration test; it does not launch the full MWeb Lite application or verify its user interface.
