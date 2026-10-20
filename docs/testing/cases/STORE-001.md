# STORE-001

## Given

A store has an edited article, selected category, and search text that would hide a new article.

## When

Request creation and await pending writes.

## Then

The old draft saves before creation; the new article inherits the category, is visible with cleared search, and opens in editor mode; busy/pending flags clear.

## Level

Integration

## Path

CI

## Data

Inline

## Status

CI passed

## Verification

`LibraryStoreCreationTests/testPendingCreationWaitsForPriorSaveAndInheritsCategory`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
