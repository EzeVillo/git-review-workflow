#!/usr/bin/env bats
#
# Tests for git-review — the dispatcher that routes `git review <verb>` to the
# private verb implementations under git-review-verbs/.
#
# Each test runs against a throwaway copy of the dispatcher in $LIBEXEC with its
# own writable git-review-verbs/ directory, so routing tests can drop in a fake
# verb without touching the repo (the Docker harness mounts it read-only). The
# fake verb echoes $0, $GIT_REVIEW_LIBEXEC and its argument vector and exits 7,
# so every routing assert checks the *exact* thing the dispatcher passed through
# and that the verb's exit code is propagated verbatim.

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	VERSION="$(cat "$REPO/VERSION")"

	TMP="$(mktemp -d)"
	LIBEXEC="$TMP/bin"
	mkdir -p "$LIBEXEC/git-review-verbs"
	cp "$REPO/bin/git-review" "$LIBEXEC/git-review"
	chmod +x "$LIBEXEC/git-review"
	export PATH="$LIBEXEC:$PATH"
}

teardown() {
	rm -rf "$TMP"
}

# Drop an executable fake verb into the libexec verbs dir.
make_verb() {
	cat > "$LIBEXEC/git-review-verbs/$1" <<'VERB'
#!/usr/bin/env sh
printf 'VERB self=%s\n' "$0"
printf 'VERB libexec=%s\n' "${GIT_REVIEW_LIBEXEC:-UNSET}"
printf 'VERB args=[%s]\n' "$*"
printf 'VERB count=%s\n' "$#"
exit 7
VERB
	chmod +x "$LIBEXEC/git-review-verbs/$1"
}

# ── listing (-h / --h / no args) ───────────────────────────────────────────────

@test "dispatcher: no arguments prints help and exits 0" {
	run git-review
	[ "$status" -eq 0 ]
	[[ "$output" == *"git review workflow"* ]]
}

@test "dispatcher: -h and --h both print help and exit 0" {
	run git-review -h
	[ "$status" -eq 0 ]
	[[ "$output" == *"git review workflow"* ]]

	run git-review --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"git review workflow"* ]]
}

# ── version (--version / -V) ───────────────────────────────────────────────────

@test "dispatcher: --version prints exactly VERSION and exits 0" {
	run git-review --version
	[ "$status" -eq 0 ]
	[ "$output" = "$VERSION" ]
}

@test "dispatcher: -V prints exactly VERSION and exits 0" {
	run git-review -V
	[ "$status" -eq 0 ]
	[ "$output" = "$VERSION" ]
}

# ── routing a verb ─────────────────────────────────────────────────────────────

@test "dispatcher: routes a known verb and propagates its exit code verbatim" {
	make_verb echoer
	run git-review echoer
	# exec replaces the dispatcher with the verb, so the verb's exit 7 is ours
	[ "$status" -eq 7 ]
	[[ "$output" == *"VERB self="* ]]
}

@test "dispatcher: exports GIT_REVIEW_LIBEXEC pointing at its own resolved dir" {
	make_verb echoer
	run git-review echoer
	[ "$status" -eq 7 ]
	[[ "$output" == *"VERB libexec=$LIBEXEC"* ]]
	[[ "$output" != *"libexec=UNSET"* ]]
}

@test "dispatcher: passes every argument after the verb through unchanged" {
	make_verb echoer
	run git-review echoer --step --base develop -- a b
	[ "$status" -eq 7 ]
	# the verb is dropped from argv; everything after it survives in order,
	# including the -- end-of-options marker
	[[ "$output" == *"VERB args=[--step --base develop -- a b]"* ]]
	[[ "$output" == *"VERB count=6"* ]]
}

@test "dispatcher: -h after the verb goes to the verb, not the dispatcher" {
	make_verb echoer
	run git-review echoer -h
	# routed to the verb (exit 7), NOT the dispatcher's own help (exit 0)
	[ "$status" -eq 7 ]
	[[ "$output" == *"VERB args=[-h]"* ]]
	[[ "$output" != *"git review workflow"* ]]
}

@test "dispatcher: routes through git's own subcommand discovery too" {
	make_verb echoer
	run git review echoer ping
	[ "$status" -eq 7 ]
	[[ "$output" == *"VERB args=[ping]"* ]]
}

# ── unknown verbs ──────────────────────────────────────────────────────────────

@test "dispatcher: unknown verb errors, names the verb, suggests -h, exits non-zero" {
	run git-review frobnicate
	[ "$status" -ne 0 ]
	[[ "$output" == *"error:"* ]]
	[[ "$output" == *"'frobnicate' is not a git review command"* ]]
	[[ "$output" == *"git review -h"* ]]
}

@test "dispatcher: unknown verb writes only to stderr, nothing to stdout" {
	# stdout alone must be empty — the diagnostic belongs on stderr
	run sh -c 'git-review frobnicate 2>/dev/null'
	[ "$status" -ne 0 ]
	[ -z "$output" ]
	# stderr alone must carry it
	run sh -c 'git-review frobnicate 2>&1 1>/dev/null'
	[ "$status" -ne 0 ]
	[[ "$output" == *"is not a git review command"* ]]
}

@test "dispatcher: no abbreviation - a verb prefix is not resolved" {
	# 'stat' must not resolve to a hypothetical 'status'; mirrors git bisect
	make_verb status
	run git-review stat
	[ "$status" -ne 0 ]
	[[ "$output" == *"'stat' is not a git review command"* ]]
	[[ "$output" != *"VERB self="* ]]
}

# ── path-escape guard ──────────────────────────────────────────────────────────

@test "dispatcher: rejects a verb containing a path separator" {
	make_verb real
	# even though git-review-verbs/real exists and is executable, a slashed verb
	# must be refused rather than path-resolved to it (or to any sibling)
	run git-review ../bin/git-review-verbs/real
	[ "$status" -ne 0 ]
	[[ "$output" == *"is not a git review command"* ]]
	[[ "$output" != *"VERB self="* ]]
}

@test "dispatcher: rejects a dot-path verb" {
	run git-review ..
	[ "$status" -ne 0 ]
	[[ "$output" == *"is not a git review command"* ]]
}
