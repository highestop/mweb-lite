# FIXTURE-001

## Given

The committed Library fixture's Markdown/media are copied into a temporary directory, and its schema/seed SQL builds a fresh database there.

## When

Open that copy through production `MWebLibrary` and load its index and active documents.

## Then

Active, trashed, and uncategorized IDs match the manifest; category hierarchy, article memberships, and newest article match the fixture; documents have nonempty content and matching titles; manifest media exists; opening creates no backup directory.

## Level

Integration

## Path

CI

## Data

Fixture: [Library](../../../Tests/Fixtures/Library)

## Status

CI passed

## Verification

`SharedFixtureTests/testEndToEndFixtureLoadsWithExpectedDocumentsAndCategories`; fixture `Tests/Fixtures/Library`

## Evidence

[2026-10-20 · 78de482](https://github.com/highestop/mweb-lite/actions/runs/39355435845)
