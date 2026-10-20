# EDIT-003

## Given

Selected text contains Chinese characters and an emoji.

## When

Wrap it in bold markers, then toggle bold off.

## Then

Text and UTF-16 selection ranges remain correct after both operations.

## Level

Unit

## Path

CI

## Data

Inline

## Status

CI passed

## Verification

`MarkdownEditingTests/testFormattingPreservesUTF16Selections`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
