#!/bin/sh
set -eu
# Test-only adapter for foundational doors before public mutation handlers exist.
# shellcheck disable=SC1007 # Empty CDPATH prevents inherited directory search.
GIT_REVIEW_LIBEXEC=$(CDPATH= cd -- "$(dirname "$0")/../../bin" && pwd)
export GIT_REVIEW_LIBEXEC
# shellcheck source=../../bin/git-review-lib.sh
. "$GIT_REVIEW_LIBEXEC/git-review-lib.sh"

# A test-only write fault for the builtin redirection phase; unlike chmod it
# works under root. Match only the generation manifest, never comment bodies.
if [ "${COMMENTS_FAIL_MANIFEST:-0}" = 1 ]; then
	printf() {
		case "$1" in
			'context\t%s\nlocal\t%s\nshared\t%s\n')
				command printf 'hit\n' >"$COMMENTS_TMP/manifest-write.hit"
				return 73
				;;
		esac
		command printf "$@"
	}
fi
operation=$1
shift
case "$operation" in
	status) comments_status '' 1 ;;
	token) comments_token_valid "$1" ;;
	path) comments_state; comments_safe_path "$1" ;;
	guard) comments_state; printf '%s\n' "$cm_guard" ;;
	check) comments_state; comments_check_guards "$1" "$2" "$3" ;;
	lock)
		comments_state
		comments_lock "$1"
		trap 'comments_unlock' 0
		trap 'exit 1' 1 2 15
		printf 'locked\n'
		if [ "$#" -gt 1 ]; then
			printf 'arrived\n' >"$2/arrived"
			# shellcheck disable=SC2016 # Positional path belongs to the child.
			timeout 5 sh -c 'printf "ready\n" >"$1/ready"; read -r release <"$1/release" && [ "$release" = release ]' sh "$2"
		fi
		;;
	write)
		comments_state
		comments_lock "$1"
		trap 'comments_unlock' 0
		trap 'exit 1' 1 2 15
		comments_replace "$2" "$3" "$4" "${5:-}"
		;;
	publish)
		comments_state
		comments_lock "$1"
		trap 'comments_unlock' 0
		trap 'exit 1' 1 2 15
		comments_publish "$1" "$2"
		;;
	*) printf 'unknown test driver operation\n' >&2; exit 1 ;;
esac
