#!/usr/bin/env bats
#
# Tests for git review config: reading and writing the product's own
# configuration keys (base, remote) in their human, single-key, write and
# --unset forms. --porcelain lives in its own file (tests/config-porcelain.bats)
# because it has its own risk surface (candidate branches, bytes, cost).

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global init.defaultBranch develop

	ORIGIN="$TMP/origin.git"
	WORK="$TMP/work"
	git init --quiet --bare "$ORIGIN"
	git init --quiet "$WORK"
	cd "$WORK"
	git remote add origin "$ORIGIN"

	printf 'base\n' >base.txt
	git add base.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop
}

teardown() {
	rm -rf "$TMP"
}

# ── human form (no key): aligned, omits base when unset, never lists branches ─

@test "config with no arguments and nothing set reports only remote, at the default" {
	run git review config
	[ "$status" -eq 0 ]
	[ "$output" = "remote  origin" ]
}

@test "config with no arguments reports base and remote when both are set" {
	git config reviewworkflow.base develop
	git config reviewworkflow.remote upstream
	run git review config
	[ "$status" -eq 0 ]
	[ "$output" = "$(printf 'base    develop\nremote  upstream')" ]
}

@test "config with no arguments never lists candidate branches" {
	git switch --quiet -c feature/x
	run git review config
	[ "$status" -eq 0 ]
	[ "$output" = "remote  origin" ]
}

# ── reading a single key ──────────────────────────────────────────────────────

@test "config base with nothing set prints nothing and exits 0" {
	run git review config base
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "config base prints the effective value" {
	git config reviewworkflow.base develop
	run git review config base
	[ "$status" -eq 0 ]
	[ "$output" = "develop" ]
}

@test "config remote with nothing set prints the default, not empty" {
	run git review config remote
	[ "$status" -eq 0 ]
	[ "$output" = "origin" ]
}

@test "config remote prints the configured value, overriding the default" {
	git config reviewworkflow.remote upstream
	run git review config remote
	[ "$status" -eq 0 ]
	[ "$output" = "upstream" ]
}

# ── writing a key ──────────────────────────────────────────────────────────────

@test "config base <value> sets it, verified by reading git config directly" {
	run git review config base develop
	[ "$status" -eq 0 ]
	[ "$(git config --get reviewworkflow.base)" = "develop" ]
}

@test "config remote <value> sets it, verified by reading git config directly" {
	run git review config remote upstream
	[ "$status" -eq 0 ]
	[ "$(git config --get reviewworkflow.remote)" = "upstream" ]
}

@test "config base -- -foo sets the base to a branch literally named -foo" {
	run git review config base -- -foo
	[ "$status" -eq 0 ]
	[ "$(git config --get reviewworkflow.base)" = "-foo" ]
}

# ── unsetting a key ────────────────────────────────────────────────────────────

@test "config --unset base removes it" {
	git config reviewworkflow.base develop
	run git review config --unset base
	[ "$status" -eq 0 ]
	run git config --get reviewworkflow.base
	[ "$status" -ne 0 ]
}

@test "config --unset remote removes the override, falling back to the default" {
	git config reviewworkflow.remote upstream
	run git review config --unset remote
	[ "$status" -eq 0 ]
	run git config --get reviewworkflow.remote
	[ "$status" -ne 0 ]
	run git review config remote
	[ "$status" -eq 0 ]
	[ "$output" = "origin" ]
}

# ── unknown key: exit 1, no side effect ────────────────────────────────────────

@test "config with an unknown key on write exits 1, names the key, and writes nothing" {
	run git review config bese main
	[ "$status" -eq 1 ]
	[[ "$output" == *bese* ]]
	run git config --get reviewworkflow.bese
	[ "$status" -ne 0 ]
}

@test "config with an unknown key on read exits 1 and names the key" {
	run git review config bese
	[ "$status" -eq 1 ]
	[[ "$output" == *bese* ]]
}

@test "config --unset with an unknown key exits 1 and writes nothing" {
	run git review config --unset bese
	[ "$status" -eq 1 ]
	[[ "$output" == *bese* ]]
}

# ── outside a git repository ───────────────────────────────────────────────────

@test "config outside a git repository exits 1 with the same diagnostic as other verbs" {
	norepo="$(mktemp -d)"
	cd "$norepo"
	run git review config
	[ "$status" -eq 1 ]
	[[ "$output" == *"not a git repository"* ]]
	cd "$WORK"
	rm -rf "$norepo"
}

# ── works the same regardless of HEAD / an active review ─────────────────────

@test "config keeps working the same with a review active (does not depend on HEAD)" {
	git switch --quiet -c feature/x
	printf 'a\n' >a.txt
	git add a.txt
	git commit --quiet -m c1
	git push --quiet -u origin feature/x
	git switch --quiet develop
	git config reviewworkflow.base develop
	git review start feature/x

	run git review config base
	[ "$status" -eq 0 ]
	[ "$output" = "develop" ]

	run git review config remote upstream
	[ "$status" -eq 0 ]
	[ "$(git config --get reviewworkflow.remote)" = "upstream" ]
}
