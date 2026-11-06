#!/bin/sh
set -eu

# Keep argv short on Windows, preserve each selected file's hooks, and never
# eval test names. Finish the other files even when one reports a failure.
manifest=$(mktemp)
trap 'rm -f "$manifest"' EXIT HUP INT TERM
node scripts/ci-shards.cjs bats "${TEST_SHARD:?}" "${TEST_SHARDS:?}" "${RUNNER_OS:?}" >"$manifest"
tab=$(printf '\t')
failed=0
while IFS="$tab" read -r file filter expected; do
	[ -n "$file" ] || continue
	printf '\nCI file: %s; filter: %s\n' "$file" "$filter"
	if [ "$expected" != - ]; then
		if count=$(bats --count --filter "$filter" "$file"); then
			if [ "$count" != "$expected" ]; then
				printf 'error: %s selected %s cases; expected %s\n' "$file" "$count" "$expected" >&2
				failed=1
				continue
			fi
		else
			failed=1
			continue
		fi
	fi
	if bats --timing --print-output-on-failure --filter "$filter" "$file"; then
		:
	else
		failed=1
	fi
done <"$manifest"
exit "$failed"
