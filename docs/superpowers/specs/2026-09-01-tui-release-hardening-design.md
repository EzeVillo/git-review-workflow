# TUI Release Hardening Design

## Goal

Make every visible enabled TUI control perform its documented action and make refresh, watcher, finish outcome, version detection, and preview behavior safe for release.

## Scope

This change addresses all reported P0, P1, and P2 issues. It keeps `git review ... --porcelain` as the authority for review state and continues to use direct Git only for repository and diff delegation.

## Design

### Control dispatch

`activateControl` will route each enabled control to an observable behavior: native text overlays for help and reasons, the existing assistant/mutation machinery for draft starts, editor commands for reported file paths, clipboard copy for the walkthrough prompt, and browser/process delegation for installation and support URLs. Each route will have a behavior test that proves the control is no longer inert.

### Ordered reads and watcher lifecycle

Each scheduled read will receive a monotonically increasing generation. The model will publish only the newest completed generation, so concurrent focus, watcher, polling, and mutation reads cannot repaint stale state. The composition root will forward accepted read results to the watcher and call `Rebuild` with the Git roots plus every porcelain-reported draft path. The real fsnotify watcher becomes the default; an explicit environment switch preserves a deterministic no-op mode for tests and troubleshooting.

### Finish outcome correlation

The pending finish outcome will retain the finished review's source branch. The subsequent porcelain read resolves the outcome only when its pending record belongs to that source; another review's pending state remains a global situation but cannot suppress the finished review's ready message.

### Version and interactive invocation

The version probe will distinguish a verifiable executable-not-found error from a generic invocation failure, retry transient generic failures twice, and treat a blank successful version as invalid/outdated. `preview` will use a new interactive invoker that keeps its terminal but shares invocation environment and logging policy with normal `git review` invocations.

## Testing

Regression tests will first demonstrate each bug: stale read rejection, exact finish matching, dynamic watcher rebuild, default watcher selection, control effects, version classification/retry/blank handling, and interactive preview environment/logging. Existing TUI unit, race-compatible checks, vet, formatting, product-surface checker, and UI Bats tests will be run after the changes.
