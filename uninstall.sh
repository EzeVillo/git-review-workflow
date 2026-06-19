#!/usr/bin/env sh
#
# Removes the git review aliases (review-pr, finish-review, clean-review).
# It does not touch any review/* or review-fixes/* branches you may have created.
#
set -e

git config --global --unset alias.review-pr || true
git config --global --unset alias.finish-review || true
git config --global --unset alias.clean-review || true

echo "Removed git aliases: review-pr, finish-review, clean-review"
