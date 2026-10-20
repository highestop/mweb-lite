# EDIT-005

## Given

A multiline selection ends exactly at the next line's start.

## When

Indent and then outdent.

## Then

Only selected lines change; the following line remains unchanged and the original text/selection are restored.

## Level

Unit

## Path

CI

## Data

Inline

## Status

CI passed

## Verification

`MarkdownEditingTests/testIndentExcludesNextLineAtSelectionBoundary`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
