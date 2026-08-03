#!/usr/bin/env sh
#
# Build a throwaway repo to exercise --step and walk mode by hand.
#
# Why: the only fixtures for those two modes live inside the bats setup()
# functions (tests/step.bats, tests/walk.bats) and are deleted by teardown, so
# there is nothing left to poke at with real commands. This builds the same kind
# of pull request in a directory that survives the run, and rebuilds it from
# scratch every time it is called — break the sandbox as hard as you like, then
# run this again to get the exact same starting state back.
#
# Usage:
#   tests/sandbox.sh              # (re)build in the default directory
#   tests/sandbox.sh -d /tmp/box  # somewhere else
#   tests/sandbox.sh -f           # rebuild over a directory this did not create
#
# The sandbox is a full pull request against `develop`: four commits touching
# five files (one of them twice, so --step and walk disagree), a committed
# walkthrough whose reading order is deliberately not the diff order, and a
# couple of paths carrying a space and a non-ASCII byte — the shape that keeps
# breaking path comparison in silence.
set -eu

prog="tests/sandbox.sh"

die() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

usage() {
	cat <<EOF
usage: $prog [-d <dir>] [-f]

  -d <dir>  where to build the sandbox
            (default: \$GIT_REVIEW_SANDBOX, or ~/.cache/git-review-sandbox)
  -f        rebuild even if <dir> exists and was not created by this script
  -h        show this help
EOF
}

dir=""
force=0
while [ $# -gt 0 ]; do
	case "$1" in
	-d | --dir)
		if [ $# -lt 2 ] || [ -z "$2" ]; then die "-d needs a directory"; fi
		dir="$2"
		shift 2
		;;
	-f | --force)
		force=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	--)
		shift
		break
		;;
	-*)
		die "unknown option: $1"
		;;
	*)
		die "unexpected argument: $1"
		;;
	esac
done

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

if [ -z "$dir" ]; then
	dir="${GIT_REVIEW_SANDBOX:-$HOME/.cache/git-review-sandbox}"
fi

# The marker is what makes `rm -rf` safe to run unattended: without it the
# script refuses to touch a directory it did not build itself.
marker_name=".git-review-sandbox"
if [ -e "$dir" ] && [ ! -e "$dir/$marker_name" ] && [ "$force" -eq 0 ]; then
	die "$dir exists and was not built by $prog (pass -f to overwrite it)"
fi

rm -rf "$dir"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"

origin="$dir/origin.git"
work="$dir/work"

git init --quiet --bare "$origin"
git init --quiet "$work"
cd "$work"

# Everything is set per-repo: the sandbox must not depend on (or be broken by)
# the user's global git config. gpgsign off in particular, so a globally signed
# setup does not make every fixture commit fail.
git config user.email sandbox@example.com
git config user.name "review sandbox"
git config commit.gpgsign false
git config core.autocrlf false
git remote add origin "$origin"
git config reviewworkflow.base develop

# ── base branch ───────────────────────────────────────────────────────────────

mkdir -p src docs
cat >src/cart.js <<'EOF'
export function total(items) {
	return items.reduce((sum, item) => sum + item.price, 0);
}
EOF
cat >src/pricing.js <<'EOF'
export function price(item) {
	return item.base;
}
EOF
cat >"docs/guía de estilo.md" <<'EOF'
# Guía de estilo

- Prices are integers, in cents. Never floats.
EOF
cat >README.md <<'EOF'
# checkout

A toy package. This file is not part of the pull request under review.
EOF
git add .
git commit --quiet -m "base: cart and pricing"
git branch -M develop
git push --quiet -u origin develop

# ── the pull request ──────────────────────────────────────────────────────────
#
# Three commits over five files, plus a fourth adding the walkthrough — the way
# a real author lands one. pricing.js is touched by two of them on purpose: in
# --step you see it twice (once per commit), in walk exactly once (its whole
# change at the entry), which is the difference between the modes.

git switch --quiet -c feature/checkout

cat >src/discounts.js <<'EOF'
// Discounts are expressed in basis points: 1500 = 15%.
export function discountBps(customer) {
	return customer.tier === "gold" ? 1500 : 0;
}
EOF
cat >src/pricing.js <<'EOF'
import { discountBps } from "./discounts.js";

export function price(item, customer) {
	const bps = discountBps(customer);
	return item.base - (item.base * bps) / 10000;
}
EOF
git add src/discounts.js src/pricing.js
git commit --quiet -m "feat: add the discount table"

cat >src/cart.js <<'EOF'
import { price } from "./pricing.js";

export function total(items, customer) {
	return items.reduce((sum, item) => sum + price(item, customer), 0);
}
EOF
cat >src/pricing.js <<'EOF'
import { discountBps } from "./discounts.js";

export function price(item, customer) {
	const bps = discountBps(customer);
	// Round half up, in cents, before anything else adds up.
	return Math.round(item.base - (item.base * bps) / 10000);
}
EOF
git add src/cart.js src/pricing.js
git commit --quiet -m "feat: apply discounts in the cart"

cat >"src/café.js" <<'EOF'
export const catalogue = [{ sku: "cafe-500", base: 1290 }];
EOF
cat >"docs/guía de estilo.md" <<'EOF'
# Guía de estilo

- Prices are integers, in cents. Never floats.
- Discounts are integers too, in basis points.
EOF
git add "src/café.js" "docs/guía de estilo.md"
git commit --quiet -m "docs: catalogue and style guide"

# ── the walkthrough ───────────────────────────────────────────────────────────
#
# Reading order is neither the diff order (docs, café, cart, discounts, pricing)
# nor the commit order: it is the order the change actually makes sense in. Two
# entries are marked "> key". The preamble is what `start` prints once on entry.

mkdir -p .review
cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## Heads-up

Discounts moved from percentages to basis points in this PR. Every number that
crosses a module boundary is now an integer, and the single rounding site is in
pricing.js — if you find a second place that rounds, that is the bug.

## 1. src/discounts.js
> key

Start here: this is the new unit. Basis points instead of percentages, so the
0.1% steps the pricing team asked for are representable without floats.

## 2. src/pricing.js
The only place that rounds, and it rounds last. Read it against discounts.js:
the division by 10000 is what makes the integer maths exact.

## 3. src/cart.js
Now the caller. The customer argument had to be threaded through — that is the
whole reason this PR touches the cart at all.

## 4. src/café.js
> key

The catalogue fixture, and the one file whose name is not ASCII. Worth opening
just to confirm your terminal and your editor agree on it.

## 5. docs/guía de estilo.md
Last: the rule the rest of the PR follows, written down. The filename carries
both a space and an accent, on purpose.
EOF
git add .review/walkthrough.md
git commit --quiet -m "docs: walkthrough"

git push --quiet -u origin feature/checkout

# Leave the reviewer where a reviewer starts: on the base branch.
git switch --quiet develop

# ── entry points ──────────────────────────────────────────────────────────────
#
# The sandbox must run the commands from *this* checkout, not whatever version
# happens to be installed, so both helpers put bin/ in front of PATH.

winpath() {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -w "$1"
	else
		printf '%s\n' "$1"
	fi
}

cat >"$dir/env.sh" <<EOF
# Source this (do not run it): . "$dir/env.sh"
# Puts this checkout's bin/ first on PATH and drops you in the sandbox repo.
PATH="$repo_root/bin:\$PATH"
export PATH
cd "$work"
EOF

cat >"$dir/env.ps1" <<EOF
# Dot-source this: . "$(winpath "$dir")\\env.ps1"
# Puts this checkout's bin\\ first on PATH and drops you in the sandbox repo.
\$env:PATH = "$(winpath "$repo_root")\\bin;\$env:PATH"
Set-Location "$(winpath "$work")"
EOF

date >"$dir/$marker_name"

cat <<EOF
Sandbox ready: $dir

  work/        the repo you review in (on develop, base = develop)
  origin.git/  its remote
  env.sh       . env.sh    -> bin/ on PATH + cd work   (bash / Git Bash)
  env.ps1      . env.ps1   -> the same, in PowerShell

The pull request (feature/checkout): 5 walkthrough entries over 4 commits,
the last of which is the walkthrough itself — so --step shows [n/4] and walk
shows [n/5], over the same range.

  src/discounts.js        added
  src/pricing.js          changed by two commits
  src/cart.js             added a caller
  src/café.js             added, non-ASCII name
  docs/guía de estilo.md  changed, space + accent in the name

Try it:

  . "$dir/env.sh"
  git review start feature/checkout          # walk: the committed walkthrough
  git review start feature/checkout --step   # commit by commit
  git review start feature/checkout --whole  # the plain full diff
  git review status / list / next / prev
  git review finish        # extracts your edits to review-fixes/feature/checkout
  git review abort         # throws the review away

Rebuild from scratch at any time with: $prog
EOF
