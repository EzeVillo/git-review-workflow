# Set up the checked-out state left by older clients when they changed steps.
# The checkout helpers are still used by Start, Finish, Save, Continue and Undo.
legacy_review_step() (
	set -eu
	. "$BATS_TEST_DIRNAME/../bin/git-review-lib.sh"
	load_step_review_meta ''
	case "$1" in
			next) target=$((step + 1)) ;;
			prev) target=$((step - 1)) ;;
			*) exit 2 ;;
	esac
	[ "$target" -ge 1 ] && [ "$target" -le "$total" ] || exit 2
	from=$(printf '%s\n' "$commits" | sed -n "${step}p")
	to=$(printf '%s\n' "$commits" | sed -n "${target}p")
	review_guard_checkout_paths "$to" || exit 1
	review_worktree_files stage
	tree=$(git write-tree)
	ref="refs/review-edits/$src/$step"
	if [ "$tree" = "$(git rev-parse "$from^{tree}")" ]; then
		git update-ref -d "$ref"
	else
		git update-ref "$ref" "$(git commit-tree "$tree" -p "$from" -m 'legacy review edit')"
	fi
	review_checkout_tree "$to" reset -q --hard "$to" || exit 1
	ref="refs/review-edits/$src/$target"
	if git show-ref --verify --quiet "$ref"; then apply_review_patch "$ref^" "$ref" || exit 1; fi
	git reset -q --soft "$to^" || exit 1
	git config "branch.$cur.reviewstep" "$target"
	git config --unset "branch.$cur.reviewreadstep" || true
	show_commit "$to" "$target" "$count"
)
