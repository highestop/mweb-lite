# CREATE-007

## Given

A deferred constraint will reject the creation commit after the Markdown file exists.

## When

Create in a category.

## Then

The commit error is reported; article, relationship, and audit rows roll back; the newly created Markdown is removed.

## Level

Integration

## Path

CI

## Data

Inline

## Status

CI passed

## Verification

`MWebDocumentCreationTests/testFailedCommitRemovesCreatedMarkdownAndRollsBackAllRows`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
