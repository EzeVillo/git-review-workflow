#!/usr/bin/env sh
#
# Build a throwaway repo with nothing in it but a pull request to review.
#
# Why: tests/sandbox.sh next door carries one branch per state the product can
# reach — partial walkthroughs, stale ones, saved reviews, a finish stopped
# mid-conflict, hostile bytes in commit subjects. That is the right fixture for
# reaching a specific state on purpose, and the wrong one for the question this
# script answers: what does someone who just installed this see, before any of
# those states exist? Here there is no walkthrough, no draft, no saved review,
# no marker, no leftover branch — and no base configured either, because
# configuring it is the first thing that happens to anybody starting from zero.
#
# It is also the only sandbox that cannot fail because a verb is broken: nothing
# below runs `git review`, it is a plain git repository written directly.
#
# Usage:
#   tests/sandbox-min.sh              # (re)build in the default directory
#   tests/sandbox-min.sh -d /tmp/box  # somewhere else
#   tests/sandbox-min.sh -f           # rebuild over a directory this did not create
#
# The whole fixture is two branches: `develop` with three files, and
# `feature/discount` changing three of them over two commits. Everything is
# plain ASCII with no spaces in any path — the opposite choice from the other
# sandbox, on purpose: nothing here should ever be the interesting part.
set -eu

prog="tests/sandbox-min.sh"

die() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

usage() {
	cat <<EOF
usage: $prog [-d <dir>] [-f]

  -d <dir>  where to build the sandbox
            (default: \$GIT_REVIEW_SANDBOX_MIN, or ~/.cache/git-review-sandbox-min)
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
	dir="${GIT_REVIEW_SANDBOX_MIN:-$HOME/.cache/git-review-sandbox-min}"
fi

# The marker is what makes `rm -rf` safe to run unattended: without it the
# script refuses to touch a directory it did not build itself. It carries its
# own name, so pointing this at the full sandbox (or the other way round) asks
# for -f instead of quietly replacing one with the other.
marker_name=".git-review-sandbox-min"
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
#
# Note what is NOT set here: reviewworkflow.base. A repository that has never
# been configured is the whole point of this sandbox — it is the state where the
# panel draws its setup screen and offers "Set the base branch", which the full
# sandbox can never show because it arrives configured.
git config user.email sandbox@example.com
git config user.name "review sandbox"
git config commit.gpgsign false
git config core.autocrlf false
git remote add origin "$origin"

# Los IDEs escriben su carpeta de estado en cualquier directorio que abren, y el
# sandbox es justamente el repo contra el que se prueban los clientes a mano
# (`./gradlew runIde` -> abrir work/ en IntelliJ, `devenv /rootsuffix Exp` ->
# Open Folder sobre work/ en Visual Studio). Sin ignorarlos, esos archivos quedan
# untracked: bloquean `git review start` con "you have local changes" y el
# `git add -A` de finish se los lleva puestos a review-fixes/. Son de la
# herramienta, no del fixture, así que van en .git/info/exclude y no en un
# .gitignore committeado: el pull request bajo revisión queda exactamente igual
# que antes.
cat >>.git/info/exclude <<'EOF'

# IntelliJ IDEA
.idea/
*.iml
*.ipr
*.iws

# Visual Studio
.vs/
*.suo
*.user
*.userosscache
*.sln.docstates
*.VC.db
*.VC.opendb
EOF

# ── base branch ───────────────────────────────────────────────────────────────

mkdir -p src
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
# Two commits over three files, and nothing else: no walkthrough, so `start`
# enters whole mode on its own with no flag and no note. Small enough that the
# whole diff fits on a screen — the point is to look at the panel, not at the
# change.

git switch --quiet -c feature/discount

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
	// Round half up, in cents, before anything else adds up.
	return Math.round(item.base - (item.base * bps) / 10000);
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
git add src/cart.js
git commit --quiet -m "feat: apply discounts in the cart"

git push --quiet -u origin feature/discount

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
Minimal sandbox ready: $dir

  work/        the repo you review in (on develop, no base configured yet)
  origin.git/  its remote
  env.sh       . env.sh    -> bin/ on PATH + cd work   (bash / Git Bash)
  env.ps1      . env.ps1   -> the same, in PowerShell

Two branches and nothing else:

  develop             README.md, src/cart.js, src/pricing.js
  feature/discount    2 commits over 3 files, no walkthrough -> whole mode

Nothing else exists on purpose — no walkthrough, no reviewer draft, no authoring
guide, no saved review, no --delta marker, no leftover review branch. This is
what someone sees on the day they install: the panel opens on its setup screen,
because reviewworkflow.base is not set.

  git config reviewworkflow.base develop   # or press "Set the base branch"

For the states this cannot show — partial and stale walkthroughs, saved reviews,
a finish stopped mid-conflict, hostile bytes — build the full one instead:
tests/sandbox.sh

Try it, in the order someone new would:

  . "$dir/env.sh"
  git review start feature/discount           # whole: the full diff, staged
  git review status                           # then edit a file and look again
  git review finish        # extracts your edits to review-fixes/feature/discount
  git review abort         # throws the review away

And, with an empty repository, the two sides of the walkthrough from scratch:

  git switch feature/discount
  git review walkthrough init                 # author: the skeleton to fill in
  git switch develop
  git review walkthrough draft feature/discount   # reviewer: your own reading order

Rebuild from scratch at any time with: $prog
EOF
