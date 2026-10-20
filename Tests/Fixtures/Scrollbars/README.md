# Scrollbar fixture

This synthetic SQL overlay supports [E2E-017](../../../docs/testing/cases/E2E-017.md). It adds 30 empty categories, IDs 13001–13030, under the existing Empty Category (104). Their names are `Scrollbar Category 01` through `30`, in numeric order. Expanding Empty Category makes the category tree overflow; collapsing it restores a short tree without changing the selected Date Groups category. No articles, media, or category/article relationships are added.

Prepare a fresh run from committed source, following the [testing guide](../../../docs/testing/test-guide.md). Apply DateGroups before this overlay because its script requires a pristine Library copy. Use the same fresh run name throughout:

```sh
./scripts/run-preview-app.sh e2e-017 --prepare-only
python3 scripts/apply-timeline-fixture.py e2e-017 --date-groups
python3 - <<'PY'
from pathlib import Path
import sqlite3

library = Path("build/Test Runs/e2e-017/Library")
assert not library.is_symlink()
assert library.resolve().is_relative_to(Path("build/Test Runs").resolve())
assert (library / ".fixture-baseline.json").is_file()
database = (library / "mainlib.db").resolve()
assert database.parent == library.resolve()
with sqlite3.connect(database.as_uri() + "?mode=rw", uri=True) as connection:
    assert connection.execute("SELECT COUNT(*) FROM cat_article WHERE rid = 107").fetchone()[0] == 18
    connection.executescript(Path("Tests/Fixtures/Scrollbars/seed.sql").read_text())
PY
cp Tests/Fixtures/Scroll/long-a.md 'build/Test Runs/e2e-017/Library/docs/10001.md'
cp Tests/Fixtures/Scroll/long-b.md 'build/Test Runs/e2e-017/Library/docs/10002.md'
./scripts/run-preview-app.sh --reopen e2e-017
```

The overlaid run retains All 25 and Date Groups 18. Writing contains the two existing Selection articles with the [Scroll fixture](../Scroll/README.md)'s long text; Uncategorized Note remains a short document. The existing Image Demos category provides wide images in `版式实验 · 不同比例` (10007) for checking preview media bounds during scrolling. No personal data or downloaded assets are needed.

Only the ignored prepared run is writable. The database and two copied Markdown files intentionally differ from `.fixture-baseline.json`; retain that setup note with local observations. Do not apply the SQL twice, open a personal library, or replace source fixture files during a run. Use the actual app's full `run.json` `baseCommit` when recording an executed result. This setup does not establish an E2E outcome.
