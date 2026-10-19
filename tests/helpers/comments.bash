# Test-only oracles. No product parsing, object writes or index refresh here.
# This file is sourced by bats (Bash); product commands remain POSIX sh.

comments_setup() {
	COMMENTS_TMP=$(mktemp -d)
	export COMMENTS_TMP
	export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$COMMENTS_TMP/global.config"
	export GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0
	export GIT_ALLOW_PROTOCOL=file LC_ALL=C
	unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
	unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_COUNT
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"
	git config --global user.name 'Comments tester'
	git config --global user.email comments@example.invalid
	git config --global core.autocrlf false
	git config --global init.defaultBranch main
	git config --global protocol.allow never
	git config --global protocol.file.allow always
	COMMENTS_WORK="$COMMENTS_TMP/work"
	export COMMENTS_WORK
	git init --quiet "$COMMENTS_WORK"
	cd "$COMMENTS_WORK" || return
	# Match Git's wire paths (including native Windows spelling), not a logical
	# shell alias. Fault wrappers must hit the actual destination on every OS.
	COMMENTS_WORK=$(git rev-parse --show-toplevel) || return
	git config reviewworkflow.base main
	printf 'first\nsecond\nthird\n' >sample.txt
	git add sample.txt
	git commit --quiet -m base
	COMMENTS_BASE=$(git rev-parse HEAD)
	git switch --quiet -c feature/comments
	printf 'first\nchanged\nthird\n' >sample.txt
	git commit --quiet -am first
	printf 'another file\n' >'other file.txt'
	git add 'other file.txt'
	git commit --quiet -m second
	COMMENTS_TIP=$(git rev-parse HEAD)
	export COMMENTS_BASE COMMENTS_TIP
	git switch --quiet main
}

comments_symlink() {
	# Git Bash otherwise may silently copy instead of creating a link. A fake
	# symlink fixture must not be mistaken for a product safety failure.
	MSYS=winsymlinks:nativestrict ln -s "$1" "$2" || return 1
	if [ ! -L "$2" ]; then printf 'fixture requires an actual symbolic link\n' >&2; return 1; fi
}

comments_teardown() {
	cd "$BATS_TEST_DIRNAME" || return
	rm -rf "$COMMENTS_TMP"
}

# Each caller still asserts the operation's exact status via bats run.
comments_start() {
	case "$1" in
		whole) git review start --offline --no-walk feature/comments ;;
		step) git review start --offline --step feature/comments ;;
		walk)
			git switch --quiet feature/comments || return
			mkdir -p .review
			printf '# Walkthrough\n\n## 1. sample.txt\n\nRead the changed line.\n\n## 2. other file.txt\n\nRead the second commit.\n' >.review/walkthrough.md
			git add .review/walkthrough.md
			git commit --quiet -m walkthrough || return
			git switch --quiet main || return
			git review start --offline feature/comments
			;;
		compare) git review compare --no-walk main feature/comments ;;
		*) printf 'unknown fixture mode: %s\n' "$1" >&2; return 1 ;;
	esac
}

# Hashing without -w reads bytes without adding objects. NUL-separated records
# preserve names and distinguish directories, symlinks, empty and absent files.
comments_inventory() (
	if [ ! -e "$1" ] && [ ! -L "$1" ]; then
		printf 'absent\000'
		exit
	fi
	cd "$1" || exit
	find . -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' item; do
		if [ -L "$item" ]; then
			printf 'link\000%s\000%s\000' "$item" "$(readlink "$item")"
		elif [ -f "$item" ]; then
			printf 'file\000%s\000%s\000' "$item" "$(git hash-object --no-filters -- "$item")"
		elif [ -d "$item" ]; then
			printf 'directory\000%s\000' "$item"
		else
			printf 'special\000%s\000' "$item"
		fi
	done
)

comments_capture_file() {
	if [ -L "$1" ]; then
		printf 'symlink\n' >"$2.presence"
		readlink "$1" >"$2.bytes"
	elif [ -f "$1" ]; then
		printf 'present\n' >"$2.presence"
		cp "$1" "$2.bytes"
	elif [ -e "$1" ]; then
		printf 'unsafe\n' >"$2.presence"
	else
		printf 'absent\n' >"$2.presence"
	fi
}

comments_assert_file() {
	local actual="$1" expected="$2" scratch
	scratch=$(mktemp -d "$COMMENTS_TMP/file-check.XXXXXX")
	comments_capture_file "$actual" "$scratch/actual"
	comments_capture_file "$expected" "$scratch/expected"
	if ! cmp -s "$scratch/actual.presence" "$scratch/expected.presence"; then
		printf 'file presence differs\n' >&2
		return 1
	fi
	if [ -f "$scratch/expected.bytes" ] && ! cmp -s "$scratch/actual.bytes" "$scratch/expected.bytes"; then
		printf 'file bytes differ\n' >&2
		return 1
	fi
}

# Snapshot outputs MUST stay outside the worktree and observed gitdir. Calling
# git status/write-tree is deliberately avoided: both can change observed state.
comments_snapshot() {
	local destination="$1" gitdir common
	gitdir=$(git rev-parse --absolute-git-dir) || return
	common=$(git rev-parse --path-format=absolute --git-common-dir) || return
	case "$destination/" in
		"$COMMENTS_WORK/"*|"$gitdir/"*|"$common/"*) printf 'snapshot must be outside observed storage\n' >&2; return 1 ;;
	esac
	mkdir -p "$destination" || return
	git symbolic-ref -q HEAD >"$destination/branch" || :
	git rev-parse HEAD >"$destination/head" || return
	git for-each-ref --format='%(refname) %(objectname)' | LC_ALL=C sort >"$destination/refs"
	git config --null --list >"$destination/config" || return
	git ls-files --stage -z >"$destination/index" || return
	comments_capture_file "$gitdir/index" "$destination/raw-index"
	git diff --no-ext-diff --no-textconv --binary >"$destination/unstaged" || return
	git diff --cached --no-ext-diff --no-textconv --binary >"$destination/staged" || return
	comments_inventory "$gitdir/review-comments" >"$destination/comments" || return
	comments_inventory "$common/objects" >"$destination/objects" || return
	# All working files, including untracked files, without walking .git internals.
	(
		find . -name .git -prune -o -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' item; do
			if [ -L "$item" ]; then
				printf 'link\000%s\000%s\000' "$item" "$(readlink "$item")"
			elif [ -f "$item" ]; then
				printf 'file\000%s\000%s\000' "$item" "$(git hash-object --no-filters -- "$item")"
			else
				printf 'directory\000%s\000' "$item"
			fi
		done
	) >"$destination/worktree"
}

# With no component arguments compare every field; callers can compare exactly
# the fields their operation promises to preserve and assert changes separately.
comments_assert_snapshot() {
	local expected="$1" actual="$2" component
	shift 2
	if [ "$#" -eq 0 ]; then
		set -- branch head refs config index raw-index.presence raw-index.bytes unstaged staged comments objects worktree
	fi
	for component in "$@"; do
		if ! cmp -s "$expected/$component" "$actual/$component"; then
			printf 'snapshot differs: %s\n' "$component" >&2
			return 1
		fi
	done
}

# FIFO barriers use actual rendezvous, never timing as evidence of concurrency.
comments_barrier_create() {
	mkdir -p "$1" && mkfifo "$1/ready" "$1/release"
}

comments_barrier_wait() {
	printf 'arrived\n' >"$1/arrived"
	# shellcheck disable=SC2016 # $1 belongs to the timeout's child shell.
	if ! timeout "${2:-5}" sh -c 'printf "ready\n" >"$1/ready"; read -r message < "$1/release" && [ "$message" = release ]' sh "$1"; then
		printf 'barrier not released: %s\n' "$1" >&2
		return 1
	fi
}

comments_barrier_arrived() {
	# shellcheck disable=SC2016 # The complete FIFO handshake is bounded.
	if ! timeout "${2:-5}" sh -c 'read -r message <"$1/ready" && [ "$message" = ready ]' sh "$1"; then
		printf 'barrier not reached: %s\n' "$1" >&2
		return 1
	fi
}

comments_barrier_resume() {
	# shellcheck disable=SC2016 # Pass the path as data to the child shell.
	timeout "${2:-5}" sh -c 'printf "release\n" > "$1/release"' sh "$1"
}

comments_barrier_release() {
	comments_barrier_arrived "$1" "${2:-5}" || return 1
	comments_barrier_resume "$1" "${2:-5}"
}

# Test PATH wrappers inject exactly one observed failure or rendezvous at an
# operation/path, even when tests run as root. They do not depend on chmod.
comments_inject_operation() {
	local operation="$1" pattern="$2" action="$3" real
	real=$(command -v "$operation") || return
	mkdir -p "$COMMENTS_TMP/inject"
	export COMMENTS_INJECT_REAL="$real" COMMENTS_INJECT_PATTERN="$pattern"
	export COMMENTS_INJECT_ACTION="$action" COMMENTS_INJECT_ROOT="$COMMENTS_TMP/inject"
	cat >"$COMMENTS_TMP/inject/$operation" <<'WRAPPER'
#!/bin/sh
set -eu
for argument do
	case "$argument" in
		$COMMENTS_INJECT_PATTERN)
			if mkdir "$COMMENTS_INJECT_ROOT/hit" 2>/dev/null; then
				printf '%s\n' "$argument" >"$COMMENTS_INJECT_ROOT/hit/argument"
				case "$COMMENTS_INJECT_ACTION" in
					fail) printf 'injected operation failure\n' >&2; exit 73 ;;
					barrier)
						if ! timeout 5 sh -c 'printf "ready\n" >"$1/ready"; read -r message < "$1/release" && [ "$message" = release ]' sh "$COMMENTS_INJECT_ROOT"; then
							printf 'injected barrier not released\n' >&2; exit 74
						fi
						;;
					*) printf 'invalid injection action\n' >&2; exit 75 ;;
				esac
			fi
			;;
	esac
done
exec "$COMMENTS_INJECT_REAL" "$@"
WRAPPER
	chmod +x "$COMMENTS_TMP/inject/$operation"
	if [ "$action" = barrier ]; then mkfifo "$COMMENTS_TMP/inject/ready" "$COMMENTS_TMP/inject/release"; fi
	export PATH="$COMMENTS_TMP/inject:$PATH"
}

# Independent on-disk fixtures, never produced by the writer under test.
comments_fixture_context() {
	local token="$1" kind="${2:-review}" gitdir
	gitdir=$(git rev-parse --absolute-git-dir)
	COMMENTS_CONTEXT="$token"
	COMMENTS_ROOT="$gitdir/review-comments"
	export COMMENTS_CONTEXT COMMENTS_ROOT
	mkdir -p "$COMMENTS_ROOT/contexts/$token"
	printf 'context\t%s\nkind\t%s\nsource\tfeature/comments\ntarget\tmain\nfull_base\t%s\nlast_tip\t%s\nowner_gitdir\t%s\n' \
		"$token" "$kind" "$COMMENTS_BASE" "$COMMENTS_TIP" "$gitdir" >"$COMMENTS_ROOT/contexts/$token/manifest"
}

comments_fixture_session() {
	local gitdir branch
	gitdir=$(git rev-parse --absolute-git-dir)
	branch=$(git symbolic-ref --short HEAD)
	COMMENTS_SESSION=3333333333333333333333333333333333333333
	COMMENTS_SESSION_DIR="$COMMENTS_ROOT/sessions/$COMMENTS_SESSION"
	export COMMENTS_SESSION COMMENTS_SESSION_DIR
	mkdir -p "$COMMENTS_SESSION_DIR/baseline"
	printf 'session\t%s\ncontext\t%s\nowner_gitdir\t%s\ncustodian\t%s\n' \
		"$COMMENTS_SESSION" "$COMMENTS_CONTEXT" "$gitdir" "$branch" >"$COMMENTS_SESSION_DIR/manifest"
	git config "branch.$branch.reviewcommentscontext" "$COMMENTS_CONTEXT"
	git config "branch.$branch.reviewcommentssession" "$COMMENTS_SESSION"
	git config "branch.$branch.reviewcommentsowner" "$gitdir"
}

comments_fixture_result() {
	local generation=4444444444444444444444444444444444444444
	COMMENTS_RESULT_DIR="$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/$generation"
	export COMMENTS_RESULT_DIR
	mkdir -p "$COMMENTS_RESULT_DIR"
	printf '%s\n' "$generation" >"$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current"
	printf 'context\t%s\nlocal\tabsent\nshared\tabsent\n' "$COMMENTS_CONTEXT" >"$COMMENTS_RESULT_DIR/manifest"
}

comments_driver() {
	sh -eu "$BATS_TEST_DIRNAME/helpers/comments-driver.sh" "$@"
}

comments_fixture_baseline() {
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_result
	local document presence=absent
	for document in local shared; do
		case "$1" in
			absent) ;;
			empty) : >"$COMMENTS_RESULT_DIR/$document.md"; presence=present ;;
			present) printf 'Previous %s prose.\n' "$document" >"$COMMENTS_RESULT_DIR/$document.md"; presence=present ;;
			*) printf 'unknown baseline state\n' >&2; return 1 ;;
		esac
		if [ -f "$COMMENTS_RESULT_DIR/$document.md" ]; then cp "$COMMENTS_RESULT_DIR/$document.md" "$COMMENTS_TMP/baseline-$document"; fi
	done
	printf 'context\t%s\nlocal\t%s\nshared\t%s\n' "$COMMENTS_CONTEXT" "$presence" "$presence" >"$COMMENTS_RESULT_DIR/manifest"
}

comments_assert_baseline() {
	comments_assert_file "$COMMENTS_RESULT_DIR/local.md" "$COMMENTS_TMP/baseline-local" || return 1
	comments_assert_file "$COMMENTS_RESULT_DIR/shared.md" "$COMMENTS_TMP/baseline-shared"
}

# shellcheck disable=SC2154,SC2034 # bats assigns status/output; callers consume the paths and guard.
comments_refresh_paths() {
	run --separate-stderr git review comments status --porcelain
	if [ "$status" -ne 0 ]; then
		printf 'comments status failed with exit %s\nstdout:\n%s\nstderr:\n%s\n' "$status" "$output" "$stderr" >&2
		return 1
	fi
	COMMENTS_LOCAL=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" && $4=="local" {print $2}')
	COMMENTS_SHARED=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" && $4=="shared" {print $2}')
	COMMENTS_GUARD=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-guard" {print $2}')
	COMMENTS_CONTEXT=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-context" {print $2}')
	[ -n "$COMMENTS_LOCAL" ] && [ -n "$COMMENTS_SHARED" ]
}
