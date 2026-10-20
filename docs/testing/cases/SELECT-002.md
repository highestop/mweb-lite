# SELECT-002

## Given

A's draft conflicts with an external edit.

## When

Select B and await the failed save.

## Then

Selection initially targets B, then returns to A with its draft and error; neither external A nor B is overwritten.

## Level

Integration

## Path

CI

## Data

Inline

## Status

CI passed

## Verification

`LibraryStoreSelectionTests/testSaveConflictRestoresSelectionAndPreservesTheDraft`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
