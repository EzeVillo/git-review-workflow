#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	COMMENTS_BASE_TREE=$(git rev-parse "$COMMENTS_BASE^{tree}")
	COMMENTS_HEAD_TREE=$(git rev-parse "$COMMENTS_TIP^{tree}")
	run --separate-stderr git review comments add --document local --base "$COMMENTS_BASE_TREE" --head "$COMMENTS_HEAD_TREE" --path sample.txt --text 'Historical tree pair.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	export COMMENTS_REAL_GIT COMMENTS_DIFF_ARGV="$COMMENTS_TMP/diff-argv"
	COMMENTS_REAL_GIT=$(command -v git)
	mkdir "$COMMENTS_TMP/trace-bin"
	cat >"$COMMENTS_TMP/trace-bin/git" <<'WRAPPER'
#!/bin/sh
set -eu
[ "${GIT_NO_LAZY_FETCH:-}" = 1 ] || { printf 'lazy fetch guard missing\n' >&2; exit 84; }
case "$1" in log|rev-list|shortlog|range-diff|fetch|push) printf 'forbidden history operation\n' >&2; exit 85 ;; esac
for argument do
    case "$argument" in *..*) printf 'combined range argument forbidden\n' >&2; exit 86 ;; esac
done
if [ "$1" = --no-pager ] && [ "${2:-}" = diff ]; then printf '%s\n' "$@" >"$COMMENTS_DIFF_ARGV"; fi
exec "$COMMENTS_REAL_GIT" "$@"
WRAPPER
	chmod +x "$COMMENTS_TMP/trace-bin/git"
	export PATH="$COMMENTS_TMP/trace-bin:$PATH"
}
teardown() { comments_teardown; }

@test "comments historical human diff uses root literal paths and separate tree arguments from a deep cwd" {
	local deep=$COMMENTS_WORK i
	for ((i=0;i<16;i++)); do deep=$deep/deepdir; done
	mkdir -p "$deep"
	cd "$deep"
	run --separate-stderr git-review comments diff --document local --entry 1
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[[ "$output" == *'-second'* ]]
	[[ "$output" == *'+changed'* ]]
	printf -- '--no-pager\ndiff\n--no-ext-diff\n--no-textconv\n%s\n%s\n--\n:(top,literal)sample.txt\n' "$COMMENTS_BASE_TREE" "$COMMENTS_HEAD_TREE" >"$COMMENTS_TMP/expected-argv"
	cmp "$COMMENTS_TMP/expected-argv" "$COMMENTS_DIFF_ARGV"
}

@test "comments historical diff disables configured external diff and text conversion" {
	# Configure hooks without calling wrapped Git outside the guarded query.
	"$COMMENTS_REAL_GIT" config diff.sample.textconv "touch '$COMMENTS_TMP/textconv-ran'"
	printf 'sample.txt diff=sample\n' >.gitattributes
	export GIT_EXTERNAL_DIFF="touch '$COMMENTS_TMP/external-diff-ran'"
	run --separate-stderr git-review comments diff --document local --entry 1
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[[ "$output" == *'+changed'* ]]
	[ ! -e "$COMMENTS_TMP/textconv-ran" ]
	[ ! -e "$COMMENTS_TMP/external-diff-ran" ]
}
