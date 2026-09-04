# Finish Cleanup Copy Design

## Goal

Make the completed-review state explain the consequence of its primary action
without exposing the temporary Git branch that implements undo.

## Scope

Apply identical user-facing language in the VS Code, Visual Studio, JetBrains,
and TUI clients. The CLI invocation and branch-cleanup behavior do not change.

## Copy contract

When a finish has completed, every client shows:

1. `Your edits are on {destination}, staged and ready to commit.`
2. `Commit and push them from Source Control. You can still undo this finish.`
3. Primary action: `Keep edits & remove Undo`
4. Secondary action: `Undo Finish`

The confirmation for the primary action shows:

- a title that says the reviewer will keep their edits and remove Undo;
- `Your edits stay on {destination} — commit and push them from Source Control. What goes away is the option to undo this finish.`
- confirmation button: `Keep edits & remove Undo`.

`{destination}` remains the PR branch for `--onto-source` and
`review-fixes/{source}` for a separate-branch finish.

## Interaction model

The primary action still invokes `clean --keep-fixes {source}`. It preserves
the staged edits and removes the state that makes Undo available. The interface
describes this visible consequence rather than naming the temporary review
branch. `Undo Finish` keeps its current behavior and label becomes explicit.

## Layout

The TUI must keep the 80-column finish-pending layout readable. The primary
label is intentionally short enough for the existing action row; no layout
behavior changes are required.

## Verification

Each client adds or updates focused tests for the banner labels and primary
confirmation. Existing command-argument tests continue to prove that the
action remains `clean --keep-fixes`, including the `--onto-source` case.
