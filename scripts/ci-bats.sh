#!/bin/sh
set -eu

# Keep argv short on Windows, preserve each selected file's hooks, and never
# eval test names. Finish the other files even when one reports a failure.
scratch=$(mktemp -d)
trap 'rm -f "$scratch/manifest" "$scratch/output" "$scratch/status"; rmdir "$scratch"' EXIT HUP INT TERM
manifest="$scratch/manifest"
node scripts/ci-shards.cjs bats "${TEST_SHARD:?}" "${TEST_SHARDS:?}" "${RUNNER_OS:?}" >"$manifest"
tab=$(printf '\t')
failed=0
expected_files=$(awk 'END { print NR }' "$manifest")
processed_files=0
while IFS="$tab" read -r file filter expected; do
	[ -n "$file" ] || continue
	processed_files=$((processed_files + 1))
	printf '\nCI file: %s; filter: %s\n' "$file" "$filter"
	# Preserve the producer's exit status without pipefail (not POSIX), while
	# tee keeps live CI output. Check this run's TAP plan instead of invoking
	# --count: preprocessing each excluded case again is expensive on Windows.
	# Tests get EOF, never the manifest that this loop is still reading.
	printf '1\n' >"$scratch/status"
	if {
		if bats --formatter tap --timing --print-output-on-failure --filter "$filter" "$file" </dev/null; then
			printf '0\n' >"$scratch/status"
		fi
	} 2>&1 | tee "$scratch/output"; then
		:
	else
		failed=1
	fi
	if [ "$(cat "$scratch/status")" != 0 ]; then failed=1; fi
	if [ "$expected" != - ]; then
		count=$(awk '/^1\.\./ { sub(/\r$/, ""); if ($0 ~ /^1\.\.[0-9]+$/) { sub(/^1\.\./, ""); print } }' "$scratch/output")
		if [ "$count" != "$expected" ]; then
			printf 'error: %s selected %s cases; expected %s\n' "$file" "$count" "$expected" >&2
			failed=1
		fi
	fi
done <"$manifest"
if [ "$processed_files" != "$expected_files" ]; then
	printf 'error: processed %s test files; expected %s\n' "$processed_files" "$expected_files" >&2
	failed=1
fi
exit "$failed"
