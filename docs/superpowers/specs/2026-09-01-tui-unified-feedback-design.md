# TUI Unified Feedback Design

## Goal

Make every asynchronous TUI interaction visibly accountable from the moment the reviewer acts until the operation either changes the panel or reports an outcome. The behavior must follow the existing VS Code, JetBrains, and Visual Studio clients while using terminal-native presentation.

The reviewer must never have to infer whether Enter was accepted, whether a command is still running, or whether a result was clipped below the viewport.

## Existing client pattern

The three editor clients use the same product grammar:

- Before the first resolved state they show `Reading the review state…`.
- Mutations publish `busy`, disable stale controls, and show action-specific progress such as `Starting the review of <branch>…`, `Continuing the review of <source>…`, and `Creating the authoring guide…`.
- Fast operations avoid a loading flash. Review panels keep the previous surface for 120 ms before replacing stale content with a loading surface.
- Wizard probes have an explicit progress surface instead of exposing the panel beneath the wizard.
- CLI failures always reach an error surface. Successful operations rely on the changed panel when that change is self-evident; otherwise they show a concise acknowledgement.
- Creating a guide opens the newly created empty file. If opening is unavailable, creation is still acknowledged.

The TUI will preserve those semantics, not copy IDE-specific notification widgets.

## Unified activity model

The UI model will own one optional activity value with:

- a monotonically increasing generation;
- a phase: `reading`, `assistant`, `mutation`, or `delegated`;
- user-facing progress text;
- whether stale body controls must be disabled;
- whether the activity has crossed the 120 ms visibility threshold.

Only the current generation may reveal or clear an activity. A late timer or result from an older operation is inert.

The mutation lock remains the concurrency authority. Activity is presentation state and does not create a second lock or change command ordering.

## Presentation

### First read

Before any state has resolved, the existing whole-frame `Reading the review state…` surface remains immediate. There is no 120 ms delay because no truthful previous surface exists.

### Refreshes and mutations

Once a panel exists, the last truthful panel stays visible. Its controls become non-activatable as soon as the operation starts. If the operation is still pending after 120 ms, a fixed activity line appears at the bottom with action-specific text.

The fixed bottom area is outside the scrollable/capped content budget. It always reserves room for:

1. one status or activity line when present;
2. the key bar.

Neither a long inventory nor the 55% tools footer may clip those lines. Errors and acknowledgements use the same fixed status slot after activity ends.

There is no animated spinner. Stable text avoids unnecessary terminal repainting, remains readable through logs and screen readers, and matches the editor clients' textual progress titles.

### Start assistant

A config probe never uncovers the old base panel. Activating Start immediately opens an assistant progress overlay. Picking an option that needs another probe replaces the picker with the same progress overlay until the next picker is ready.

The progress copy is product-facing (`Reading the available review options…`), not an argv such as `git review config`.

The final layout choice closes the assistant and enters the normal mutation activity `Starting the review of <branch>…`.

### Delegated actions

File-opening failures are reported immediately in the fixed status slot. Returning from an editor/diff/browser child refreshes the state as today. A child that could not be spawned reports what did not happen; an editor's ordinary non-zero exit remains non-fatal.

## Outcomes

### Failures

CLI stderr remains authoritative and is flattened into the fixed status slot. Timeout and spawn fallbacks retain the existing product vocabulary. A new action replaces an older acknowledgement, but errors remain until the next deliberate action or successful state-changing outcome.

### Successes

- Start and Continue need no extra success sentence because the entire situation changes to the review panel.
- Cursor movement needs no success sentence because the entry changes.
- Create Guide refreshes the panel and then opens the reported guide path. If no editor is configured or the editor cannot start, the status says the guide was created and names the path.
- Successful actions whose result is not otherwise visible use an action-specific acknowledgement in the fixed status slot.
- Copy actions keep their existing honest OSC 52 acknowledgement, now guaranteed visible.

## Busy behavior

While an activity invalidates the current controls:

- Enter and mouse clicks cannot activate body controls;
- mutation and navigation keys do not dispatch;
- the action palette omits actions requiring `not busy` through its existing canonical gate;
- refresh, Show CLI Log, mouse toggle, and quit remain available where they are safe.

A second mutation still follows the mutation lock's existing discard rule and reports `Another operation is already in progress`.

## Product copy

Progress strings live in `tui/internal/domain/usercopy.go`. They mirror the established strings in the editor clients for equivalent actions. Technical command lines remain exclusive to Show CLI Log.

The Continue confirmation interpolates the source in both title and detail; no literal `{source}` may reach the terminal.

## Data flow

1. A gesture resolves to an intent.
2. Before returning its command, the handler starts a generated activity and returns a repaintable model.
3. A 120 ms timer reveals the progress line only if that generation is still pending.
4. The command completes and returns a typed result message carrying the same activity generation.
5. The result clears activity, records an error/acknowledgement when needed, and schedules the authoritative read.
6. The accepted read projects the new panel without allowing an older timer or read to repaint it.

Assistant probes follow the same generation rule but resolve into the next overlay instead of a repository mutation.

## Testing

Tests will cover behavior rather than only internal fields:

- initial waiting surface;
- no loading flash for an operation completing before 120 ms;
- visible delayed progress for reads, assistant probes, and mutations;
- stale timer rejection;
- controls disabled immediately while active;
- fixed error/status visibility at 80x24 and 120x40 with a long inventory/footer;
- Start assistant never exposing the base panel between questions;
- exact action-specific progress copy;
- Continue detail interpolation;
- Open with no `$EDITOR` visibly reporting the failure without a refresh;
- Create Guide success opening the reported path or visibly acknowledging creation;
- existing mutation lock, refresh generation, watcher, confirmation, keyboard, mouse, golden, and product-surface tests remaining green.

An integration test will reproduce the supplied sandbox sequence and assert that Continue/Start's dirty-tree stderr is visible in the rendered frame rather than only in Show CLI Log.

## Scope boundaries

- No second concurrency mechanism.
- No polling beyond the existing opt-in refresh floor.
- No internal diff viewer or editor.
- No change to CLI behavior or porcelain formats.
- No new confirmation dialogs.
- No progress percentages the CLI cannot truthfully provide.
