# EDIT-004

## Given

Chinese/emoji content is already bold, with either its inner text or whole markup selected.

## When

Apply italic and then toggle it off.

## Then

Italic nests inside bold; toggling restores bold without removing its markers.

## Level

Unit

## Path

CI

## Data

Inline

## Status

CI passed

## Verification

`MarkdownEditingTests/testItalicCanBeAppliedInsideBoldAndToggledOff`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
