# SELECT-004

## Given

A selection change from A to B is already busy.

## When

Request A and then nil before B finishes loading.

## Then

The pending target remains B and B becomes the loaded document.

## Level

Integration

## Path

CI

## Data

Inline

## Status

CI passed

## Verification

`LibraryStoreSelectionTests/testSelectionWhileBusyDoesNotReplaceThePendingTarget`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
