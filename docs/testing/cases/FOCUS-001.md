# FOCUS-001

## Given

A native editor has marked Chinese text not yet committed to its binding.

## When

Resign first responder, then return focus.

## Then

Composition commits to the editor and binding, marked text clears, and the selection remains unchanged.

## Level

Integration

## Path

CI

## Data

Inline

## Status

CI passed

## Verification

`MarkdownEditorFocusTests/testResigningFocusCommitsCompositionToBinding`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
