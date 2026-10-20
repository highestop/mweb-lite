# Project instructions

- Follow the [testing guide](docs/testing/test-guide.md) and [case specification](docs/testing/test-cases.md). Use isolated fixture copies for local app tests; never open or modify a personal MWeb library for testing.
- Only executing the real Preview or Release app's documented GWT flow can establish an end-to-end result. Unit tests, component integration tests, and builds cannot substitute for it.
- Build from committed source. Only `docs/testing/ci-test-result.md` and `docs/testing/e2e-test-result.md` may be dirty; commit other changes before building.
- For Preview app tests, capture the actual tested full SHA from `run.json` `baseCommit`. If its dirty flag is set, verify the dirty paths and recorded source hashes/fingerprint against the build inputs. For REL-001, record `git rev-parse HEAD` before the Release build and ensure the installed app is that exact build; Release builds have no `run.json`.
- After an actual local E2E attempt, update only that case's observed outcome and full tested SHA in [E2E results](docs/testing/e2e-test-result.md) using `scripts/update-e2e-results.py`, then refresh freshness against a newly fetched `origin/main`. Follow the guide for the command and full-history requirements. Do not substitute the commit that records the result for the commit tested.
- Preserve unexecuted cases as `—` and preserve previous outcomes, including failures, until rerun. Freshness refresh may change only Outdated. Never invent an execution or add a pending result.
- Keep detailed run reports, logs, screenshots, app bundles, and mutable fixture copies in ignored `build/`. Only the two Markdown result summaries are tracked.
- Include changes through the normal `code-committer` skill workflow. Do not merge a feature PR without the user's authorization; automated result-only publication follows its documented workflow.
