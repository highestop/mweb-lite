# Long-article scroll fixture

These synthetic Markdown files extend Selection A and Selection B for [E2E-013](../../../docs/testing/cases/E2E-013.md). Each has 100 numbered paragraphs, an opening marker, three section headings, a table of contents, and an ending marker. They provide several screens of content in both editor and preview without network resources.

| File | Runtime destination | Expected beginning |
| --- | --- | --- |
| `long-a.md` | `Library/docs/10001.md` | `Selection A`, followed by `Beginning of Selection A.` |
| `long-b.md` | `Library/docs/10002.md` | `Selection B`, followed by `Beginning of Selection B.` |

Use a new run and apply this overlay before launching its app. From the repository root:

```sh
./scripts/run-preview-app.sh e2e-013 --prepare-only
cp Tests/Fixtures/Scroll/long-a.md 'build/Test Runs/e2e-013/Library/docs/10001.md'
cp Tests/Fixtures/Scroll/long-b.md 'build/Test Runs/e2e-013/Library/docs/10002.md'
./scripts/run-preview-app.sh --reopen e2e-013
```

Build from committed source as required by the [testing guide](../../../docs/testing/test-guide.md). The `--reopen` command launches the prepared app without rebuilding it. Choose a new name for each independent run and use that name in all four commands.

The overlay changes only the two Markdown files in the ignored run copy. IDs, titles, category relationships, and timestamps remain those of the Library fixture, so Writing still contains exactly Selection A and Selection B. The run's `.fixture-baseline.json` continues to describe the original Library fixture; the two replaced file hashes are expected differences. Keep a note of this overlay with local observations and use the app's `run.json` `baseCommit` as the tested revision. Do not replace files under `Tests/Fixtures/Library/`, edit the source overlay during a run, or use a personal library.
