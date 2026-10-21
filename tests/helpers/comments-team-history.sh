#!/bin/sh
set -eu
# Git-only history fixture used by client integration tests. Product operations
# are deliberately performed by each client's real invoker, outside this file.
phase=$1
root=$2
case "$phase" in
	init)
		git init --quiet --bare --initial-branch=main "$root/remote.git"
		git clone --quiet "$root/remote.git" "$root/author"
		cd "$root/author"
		git config user.name Author
		git config user.email author@example.invalid
		git config core.autocrlf false
		printf 'base\n' >sample.txt
		git add sample.txt
		git commit --quiet -m Base
		git push --quiet origin main
		git switch --quiet -c before-merge
		printf 'before\n' >before.txt
		git add before.txt
		git commit --quiet -m Before
		git push --quiet origin before-merge
		git switch --quiet -c feature/team main
		printf 'changed\n' >sample.txt
		git commit --quiet -am Feature
		git push --quiet origin feature/team
		git switch --quiet main
		git clone --quiet "$root/remote.git" "$root/reviewer"
		cd "$root/reviewer"
		git config user.name Reviewer
		git config user.email reviewer@example.invalid
		git config core.autocrlf false
		git config reviewworkflow.base main
		;;
	publish)
		cd "$root/reviewer"
		git add .review/comments.md
		git commit --quiet -m 'Reviewer feedback'
		git push --quiet origin HEAD:refs/heads/feedback
		git switch --quiet main
		cd "$root/author"
		git fetch --quiet origin
		git switch --quiet feature/team
		git merge --quiet --ff-only origin/feedback
		sed 's/Reviewer question/Author response/' .review/comments.md >"$root/response.md"
		cp "$root/response.md" .review/comments.md
		git add .review/comments.md
		git commit --quiet -m 'Author response'
		git push --quiet origin feature/team
		;;
	merge)
		cd "$root/author"
		git switch --quiet main
		case "$3" in
			ff) git merge --quiet --ff-only feature/team ;;
			merge) git merge --quiet --no-ff feature/team -m Merge ;;
			squash) git merge --quiet --squash feature/team; git commit --quiet -m Squash ;;
			*) exit 2 ;;
		esac
		git push --quiet origin main
		git switch --quiet -c after-merge
		printf 'after\n' >after.txt
		git add after.txt
		git commit --quiet -m After
		git push --quiet origin after-merge
		cd "$root/reviewer"
		git switch --quiet main
		# A remote review must use the fetched base even when the reviewer's
		# checked-out main has not been pulled after somebody else's merge.
		git fetch --quiet origin
		;;
	*) exit 2 ;;
esac
