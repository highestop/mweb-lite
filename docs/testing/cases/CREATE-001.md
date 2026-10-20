# CREATE-001

## Given

A temporary library has parent/child categories, an existing article, unknown columns/defaults, and an unrelated table.

## When

Create in the child category at a fixed time, reopen, and edit the new document.

## Then

A unique numeric UUID, default title/content, timestamps, and child UUID relationship are written; unrelated rows/defaults survive; backup represents the pre-create database; the document reopens and saves.

## Level

Integration

## Path

CI

## Data

Inline

## Status

CI passed

## Verification

`MWebDocumentCreationTests/testCreateUsesSelectedCategoryUUIDAndReopensAsEditableDocument`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
