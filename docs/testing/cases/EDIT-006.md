# EDIT-006

## Given

The caret sits inside leading whitespace that will be removed.

## When

Outdent the line.

## Then

Text loses the indentation and the caret clamps to the beginning rather than becoming invalid.

## Level

Unit

## Path

CI

## Data

Inline

## Status

CI passed

## Verification

`MarkdownEditingTests/testOutdentClampsCursorInsideRemovedIndentation`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
