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
#
# Around it, one branch per state that a single well-formed pull request cannot
# show: a partial walkthrough (unannotated files at the end of the reading
# order), no walkthrough (whole), a stale one (degraded), and three saved
# reviews — resumable, blocked, and orphaned —
# for the inventory that `git review list` and the extension's empty state read.
# That last group is the only part built by running the commands rather than by
# writing the repository directly; it fails soft, see the phase itself.
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

# ── the other pull requests ───────────────────────────────────────────────────
#
# feature/checkout above is the fixture for --step and walk, and it stays exactly
# as it was. Everything from here down is additive: one branch per state that the
# panel (and the commands) can reach but that a single well-formed pull request
# never shows — a partial walkthrough, no walkthrough at all, a stale one.

pr() {
	git switch --quiet -c "$1" develop
}

publish() {
	git push --quiet -u origin "$1"
}

# A pull request whose walkthrough covers two of its four files: the rest are
# appended to the end of the reading order, unannotated — `git review next`
# still reaches them, marked `(uncovered)` instead of `(key)`.
pr feature/notifications

cat >src/notify.js <<'EOF'
import { render } from "./templates/email.js";

export function notify(order, customer) {
	return { to: customer.email, body: render(order) };
}
EOF
mkdir -p src/templates
cat >src/templates/email.js <<'EOF'
export function render(order) {
	return `Order ${order.id}: ${order.total} cents.`;
}
EOF
git add src/notify.js src/templates/email.js
git commit --quiet -m "feat: notify the customer on checkout"

cat >src/queue.js <<'EOF'
// Retries are capped: a notification is worth less the later it arrives.
export function enqueue(job, attempts = 3) {
	return { job, attempts };
}
EOF
cat >docs/notificaciones.md <<'EOF'
# Notificaciones

Los mensajes salen por la cola, nunca en el request del checkout.
EOF
git add src/queue.js docs/notificaciones.md
git commit --quiet -m "feat: queue the notifications"

mkdir -p .review
cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## Heads-up

Only the two files that carry the decision are written up here. The template and
the note are follow-the-nose changes: read them if you want, in any order.

## 1. src/notify.js
> key

The whole feature in one function. Note that it returns the message instead of
sending it — the sending lives in the queue, one entry down.

## 2. src/queue.js
The retry cap is the only number worth arguing about. Three is what the ops
runbook already assumes for every other job.
EOF
git add .review/walkthrough.md
git commit --quiet -m "docs: walkthrough"
publish feature/notifications

# A pull request with no walkthrough at all: `git review start` enters whole mode
# on its own, without --whole.
pr feature/telemetry

cat >src/metrics.js <<'EOF'
export function timing(name, ms) {
	return `${name}:${ms}|ms`;
}
EOF
cat >src/sampler.js <<'EOF'
import { timing } from "./metrics.js";

// One in ten: enough signal for the checkout funnel, cheap enough to leave on.
export function sample(name, ms, rate = 0.1) {
	return Math.random() < rate ? timing(name, ms) : null;
}
EOF
git add src/metrics.js src/sampler.js
git commit --quiet -m "feat: sample checkout timings"
publish feature/telemetry

# A pull request whose walkthrough went stale: every path it names was renamed
# away, so it covers nothing in the range and the review degrades to whole with a
# note. This is the failure mode that must never fail a review, only degrade it.
pr feature/legacy

git mv src/cart.js src/basket.js
cat >>src/basket.js <<'EOF'

// Renamed from cart.js: "basket" is the word the rest of the shop uses.
EOF
git add src/basket.js
git commit --quiet -m "refactor: rename cart to basket"

mkdir -p .review
cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## Heads-up

This walkthrough was written before the rename and never updated: the paths
below no longer exist in the range.

## 1. src/cart.js
The old name. Nothing in the range matches this path any more.

## 2. src/carrito.js
Neither does this one.
EOF
git add .review/walkthrough.md
git commit --quiet -m "docs: walkthrough (stale on purpose)"
publish feature/legacy

# Two more, small on purpose: they exist to be reviewed and put aside below.
pr feature/search

cat >src/search.js <<'EOF'
export function find(catalogue, term) {
	return catalogue.filter((item) => item.sku.includes(term));
}
EOF
cat >src/index-catalogue.js <<'EOF'
export function index(catalogue) {
	return new Map(catalogue.map((item) => [item.sku, item]));
}
EOF
git add src/search.js src/index-catalogue.js
git commit --quiet -m "feat: search the catalogue"

mkdir -p .review
cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. src/index-catalogue.js
The index first: everything else assumes lookups are free.

## 2. src/search.js
> key

The search itself. Substring for now — the ranking discussion is a separate PR.
EOF
git add .review/walkthrough.md
git commit --quiet -m "docs: walkthrough"
publish feature/search

pr feature/i18n

cat >src/messages.js <<'EOF'
export const es = { total: "Total", checkout: "Finalizar compra" };
EOF
git add src/messages.js
git commit --quiet -m "feat: spanish strings"
publish feature/i18n

pr feature/refunds

cat >src/refunds.js <<'EOF'
export function refund(order) {
	return { order: order.id, cents: order.total };
}
EOF
git add src/refunds.js
git commit --quiet -m "feat: refund an order"
publish feature/refunds

# Leave the reviewer where a reviewer starts: on the base branch.
git switch --quiet develop

# ── saved reviews ─────────────────────────────────────────────────────────────
#
# The one part of the sandbox that runs the commands instead of building the repo
# behind their back: review-saved/* carries branch config that only `git review
# start` + `git review save` know how to write, and fabricating it here would be
# a second copy of the state model — the kind that goes stale in silence.
#
# That makes this the only phase that can fail because a verb is broken, so it
# does not abort the build: everything above is a plain git repository and stays
# usable either way.

review() {
	PATH="$repo_root/bin:$PATH" git review "$@"
}

# A saved review that can be resumed, left on entry 2 so the inventory shows a
# position that is not the first one.
bank_search() {
	review start feature/search >/dev/null || return 1
	review next >/dev/null || return 1
	review save >/dev/null || return 1
}

# A second one, blocked: `review/<src>` exists alongside it, which is what the
# continue verb refuses with "is already active". The branch is made by hand
# because the commands deliberately cannot produce both at once.
bank_i18n() {
	review start feature/i18n >/dev/null || return 1
	review save >/dev/null || return 1
	git branch --quiet review/feature/i18n develop || return 1
}

if bank_search && bank_i18n; then
	# A saved branch with no metadata behind it: hand-made, or left by an older
	# version. The inventory shows it as an orphan and offers nothing.
	git branch --quiet review-saved/feature/refunds develop
	saved_reviews=1
else
	printf 'warning: could not build the saved reviews (is %s working?)\n' "$repo_root/bin/git-review" >&2
	saved_reviews=0
fi

# Whatever happened above, the reviewer starts on the base branch with a clean
# working tree: `git review continue` refuses to run against local changes.
git switch --quiet develop
git reset --quiet --hard
git clean --quiet -fd

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

if [ "$saved_reviews" -eq 1 ]; then
	saved_note="  git review continue feature/search         # resumes it on entry 2/2"
else
	saved_note="  (the saved reviews could not be built — see the warning above)"
fi

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

The other branches, one per state that feature/checkout cannot show:

  feature/notifications   walk over 4 entries, the last 2 unannotated
  feature/telemetry       no walkthrough at all -> whole, without --whole
  feature/legacy          walkthrough naming paths the rename removed -> degrades
                          to whole with a note, never fails
  feature/search          reviewed and put aside (see below)
  feature/i18n            the same, but blocked
  feature/refunds         only its leftover branch, no review

And, on develop, the inventory that \`git review list\` (and the extension's empty
state) reads — three saved reviews, one resumable and two not:

  review-saved/feature/search   walk 2/2, resumable
  review-saved/feature/i18n     blocked: review/feature/i18n is already active
  review-saved/feature/refunds  no metadata behind it (hand-made branch)

Try it:

  . "$dir/env.sh"
  git review start feature/checkout          # walk: the committed walkthrough
  git review start feature/checkout --step   # commit by commit
  git review start feature/checkout --whole  # the plain full diff
  git review start feature/notifications     # then: git review status --porcelain
  git review status / list / next / prev
$saved_note
  git review finish        # extracts your edits to review-fixes/feature/checkout
  git review abort         # throws the review away

Rebuild from scratch at any time with: $prog
EOF
