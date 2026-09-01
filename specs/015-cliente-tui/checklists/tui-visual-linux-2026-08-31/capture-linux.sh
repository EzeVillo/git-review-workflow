#!/bin/sh
set -eu

root=/repo
out="$root/specs/015-cliente-tui/checklists/tui-visual-linux-2026-08-31/frames"
helpers="$root/specs/015-cliente-tui/checklists/tui-visual-linux-2026-08-31/helpers"
bin=/tmp/git-review-ui
full=/tmp/t119-visual-full/work
minimal=/tmp/t119-visual-min/work
base_path=/repo/bin:/usr/local/go/bin:/usr/bin:/bin

mkdir -p "$out"
chmod +x "$helpers/delay/git" "$helpers/outdated/git-review" "$helpers/finish-pending/git-review"

for session in $(tmux list-sessions -F '#S' 2>/dev/null | sed -n '/^t119v-/p'); do
	tmux kill-session -t "$session"
done

capture() {
	name="$1"
	session="$2"
	tmux capture-pane -e -p -t "$session:0.0" >"$out/$name.ansi"
	tmux capture-pane -p -t "$session:0.0" >"$out/$name.txt"
}

stop() {
	session="$1"
	tmux send-keys -t "$session:0.0" q
	sleep 1
	tmux kill-session -t "$session" 2>/dev/null || true
}

start() {
	name="$1"
	cols="$2"
	rows="$3"
	cwd="$4"
	path="$5"
	extra="${6:-}"
	session="t119v-$name"
	tmux kill-session -t "$session" 2>/dev/null || true
	tmux new-session -d -s "$session" -x "$cols" -y "$rows" \
		"cd '$cwd' && env PATH='$path' TERM=xterm-256color LANG=C.UTF-8 GIT_REVIEW_UI_WATCH=1 $extra '$bin'"
	printf '%s\n' "$session"
}

cd "$root/tui"
go build -o "$bin" ./cmd/git-review-ui
cd "$root"
./tests/sandbox-min.sh -d /tmp/t119-visual-min >/tmp/t119-visual-min.log
./tests/sandbox.sh -d /tmp/t119-visual-full >/tmp/t119-visual-full.log

# Environment and error surfaces.
session=$(start waiting-80x24 80 24 "$minimal" "$helpers/delay:$base_path")
sleep 1
capture waiting-80x24 "$session"
stop "$session"

session=$(start cli-missing-80x24 80 24 "$minimal" /usr/bin:/bin)
sleep 2
capture cli-missing-80x24 "$session"
stop "$session"

session=$(start cli-outdated-80x24 80 24 "$minimal" "$helpers/outdated:/usr/bin:/bin")
sleep 2
capture cli-outdated-80x24 "$session"
stop "$session"

session=$(start error-outside-repo-80x24 80 24 /tmp "$base_path")
sleep 2
capture error-outside-repo-80x24 "$session"
stop "$session"

# Setup and the start assistant, all against the real minimal sandbox.
session=$(start no-review-setup-80x24 80 24 "$minimal" "$base_path")
sleep 2
capture no-review-setup-80x24 "$session"
stop "$session"

cd "$minimal"
git config reviewworkflow.base develop
git config reviewui.startsource offline
session=$(start no-review-minimal-80x24 80 24 "$minimal" "$base_path")
sleep 2
capture no-review-minimal-80x24 "$session"
tmux send-keys -t "$session:0.0" Enter
sleep 1
capture overlay-start-branch-80x24 "$session"
tmux send-keys -t "$session:0.0" Down Enter
sleep 1
capture overlay-start-source-80x24 "$session"
tmux send-keys -t "$session:0.0" Enter
sleep 1
capture overlay-start-range-80x24 "$session"
tmux send-keys -t "$session:0.0" Enter
sleep 1
capture overlay-start-layout-80x24 "$session"
tmux send-keys -t "$session:0.0" Escape
sleep 1
stop "$session"

# Full no-review footer at both contract sizes.
cd "$full"
git switch -q develop
session=$(start no-review-80x24 80 24 "$full" "$base_path")
sleep 2
capture no-review-80x24 "$session"
stop "$session"
session=$(start no-review-120x40 120 40 "$full" "$base_path")
sleep 2
capture no-review-120x40 "$session"
stop "$session"

# Active walk plus every transient overlay type reachable from it.
git review start --offline feature/checkout >/tmp/t119-start-walk.out 2>/tmp/t119-start-walk.err
session=$(start review-walk-80x24 80 24 "$full" "$base_path")
sleep 2
capture review-walk-80x24 "$session"
tmux send-keys -t "$session:0.0" ':'
sleep 1
capture overlay-actions-80x24 "$session"
tmux send-keys -t "$session:0.0" -l log
tmux send-keys -t "$session:0.0" Enter
sleep 1
capture overlay-cli-log-80x24 "$session"
tmux send-keys -t "$session:0.0" Escape
sleep 1
tmux send-keys -t "$session:0.0" g
sleep 1
capture overlay-entry-picker-80x24 "$session"
tmux send-keys -t "$session:0.0" Escape
sleep 1
tmux send-keys -t "$session:0.0" a
sleep 1
capture overlay-confirm-abort-80x24 "$session"
tmux send-keys -t "$session:0.0" Escape
sleep 1
tmux send-keys -t "$session:0.0" f
sleep 1
capture overlay-finish-destination-80x24 "$session"
tmux send-keys -t "$session:0.0" Escape
sleep 1
tmux send-keys -t "$session:0.0" m
sleep 1
capture review-walk-mouse-off-80x24 "$session"
stop "$session"
git review abort >/tmp/t119-abort-walk.out 2>/tmp/t119-abort-walk.err

git review start --offline feature/checkout >/tmp/t119-start-walk-120.out 2>/tmp/t119-start-walk-120.err
session=$(start review-walk-120x40 120 40 "$full" "$base_path")
sleep 2
capture review-walk-120x40 "$session"
stop "$session"
git review abort >/tmp/t119-abort-walk-120.out 2>/tmp/t119-abort-walk-120.err

# Step, its corrupted cursor, and whole mode are real repository states.
git review start --offline --step feature/checkout >/tmp/t119-start-step.out 2>/tmp/t119-start-step.err
session=$(start review-step-80x24 80 24 "$full" "$base_path")
sleep 2
capture review-step-80x24 "$session"
stop "$session"
session=$(start review-step-120x40 120 40 "$full" "$base_path")
sleep 2
capture review-step-120x40 "$session"
stop "$session"
git config branch.review/feature/checkout.reviewstep 99
session=$(start out-of-range-80x24 80 24 "$full" "$base_path")
sleep 2
capture out-of-range-80x24 "$session"
stop "$session"
git config branch.review/feature/checkout.reviewstep 1
git review abort >/tmp/t119-abort-step.out 2>/tmp/t119-abort-step.err

git review start --offline --no-walk feature/telemetry >/tmp/t119-start-whole.out 2>/tmp/t119-start-whole.err
session=$(start review-whole-80x24 80 24 "$full" "$base_path")
sleep 2
capture review-whole-80x24 "$session"
stop "$session"
session=$(start review-whole-120x40 120 40 "$full" "$base_path")
sleep 2
capture review-whole-120x40 "$session"
stop "$session"
session=$(start review-whole-ascii-nocolor-80x24 80 24 "$full" "$base_path" 'NO_COLOR=1 GIT_REVIEW_UI_ASCII=1')
sleep 2
capture review-whole-ascii-nocolor-80x24 "$session"
stop "$session"
git review abort >/tmp/t119-abort-whole.out 2>/tmp/t119-abort-whole.err

# Conflict is produced by sandbox.sh itself.
git switch -q review/feature/conflict
session=$(start finish-conflict-80x24 80 24 "$full" "$base_path")
sleep 2
capture finish-conflict-80x24 "$session"
stop "$session"
session=$(start finish-conflict-120x40 120 40 "$full" "$base_path")
sleep 2
capture finish-conflict-120x40 "$session"
stop "$session"
git switch -q develop

# The contractual pending panel needs a controlled porcelain fixture. A second
# live frame on the real pending branch is captured to expose any projection
# mismatch between the real CLI and the controlled state.
session=$(start finish-pending-fixture-80x24 80 24 "$full" "$helpers/finish-pending:$base_path")
sleep 2
capture finish-pending-fixture-80x24 "$session"
stop "$session"

git switch -q review-fixes/feature/shipping
session=$(start finish-pending-real-80x24 80 24 "$full" "$base_path")
sleep 2
capture finish-pending-real-80x24 "$session"
stop "$session"
git switch -q develop

printf 'captured %s ANSI frames\n' "$(find "$out" -name '*.ansi' -type f | wc -l)"
