# CREATE-008

## Given

The next document destination is a symlink to an outside path.

## When

Attempt creation.

## Then

Creation fails, no outside file is created, and the article count stays unchanged.

## Level

Integration

## Path

CI

## Data

Inline

## Status

CI passed

## Verification

`MWebDocumentCreationTests/testSymlinkDestinationCannotCreateFileOutsideLibrary`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
