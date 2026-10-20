# SELECT-003

## Given

B is indexed but its Markdown file has been removed.

## When

Select B and await loading.

## Then

An error appears in the store; selection and document return to A with A's content intact.

## Level

Integration

## Path

CI

## Data

Inline

## Status

CI passed

## Verification

`LibraryStoreSelectionTests/testLoadFailureRestoresSelectionWithoutReplacingTheDocument`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
