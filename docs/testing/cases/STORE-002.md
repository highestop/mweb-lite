# STORE-002

## Given

A dirty draft conflicts with an externally edited file.

## When

Request creation and await pending writes.

## Then

Creation is blocked; the current document and draft remain, the article count does not grow, and external content is preserved.

## Level

Integration

## Path

CI

## Data

Inline

## Status

CI passed

## Verification

`LibraryStoreCreationTests/testConflictingDraftPreventsCreationAndPreservesDraft`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
