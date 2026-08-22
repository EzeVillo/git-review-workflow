#!/bin/sh
#
# Turn what the JetBrains verifications had to say into something CI shows.
#
# Why this exists: the three verification tasks of the IntelliJ Platform Gradle
# plugin report two very different kinds of thing, and only one of them fails a
# build. `verifyPluginProjectConfiguration` and `verifyPluginStructure` print
# their findings to stdout and end in BUILD SUCCESSFUL -- a since-build below
# the target platform, a plugin name the Marketplace will object to, a
# descriptor the store reads differently than the IDE does. `verifyPlugin` does
# fail on compatibility problems, but its deprecated / internal / experimental
# API usages ride along in the verdict and in the report files, and a green
# release step says nothing about them. Every one of those is a thing you find
# out about when the version is already published.
#
# So: the tasks run in CI, their failures still fail the job on their own, and
# this script reads what they said and re-emits it as GitHub warning
# annotations plus a job summary. It never exits non-zero -- a warning is a
# warning, and turning one into a red build is the opposite of the point.
#
# Usage:
#   ./verification-report.sh <gradle-log> [<pluginVerifier-reports-dir>]
#
# Outside GitHub Actions the annotations are just lines on stdout, so running it
# over a local `./gradlew ... | tee log` works the same way.
set -eu

log="${1:?usage: verification-report.sh <gradle-log> [<reports-dir>]}"
reports="${2:-build/reports/pluginVerifier}"

# Collected here first so the annotations can be capped and the summary can
# carry every one of them.
findings="$(mktemp)"
trap 'rm -f "$findings"' EXIT INT TERM

# What the Gradle log had to say.
#
# The two cheap tasks tag their own lines with the plugin id, so the filter is
# an ALLOWLIST OF BENIGN LINES rather than a list of known warnings: a message
# shape nobody anticipated should show up as noise, not disappear. Extend the
# `benign` list when one turns out to be chatter.
#
# One message spans several lines -- "The following plugin configuration issues
# were found:" followed by one `- ` item each -- and those items carry no tag of
# their own, hence the small state machine.
if [ -f "$log" ]; then
	awk -v tag="[org.jetbrains.intellij.platform] " '
		BEGIN {
			# Progress chatter of the tasks themselves, not findings.
			benign[1] = "Patching plugin.xml"
			benign[2] = "The verifyPlugin task is about to resolve"
			benign[3] = "The IntelliJ Platform dependency"
			nbenign = 3
			header = "The following plugin configuration issues were found:"
		}
		function emit(kind, text) {
			if (text ~ /[^ \t]/) print kind "\t" text
		}
		{ line = $0; sub(/\r$/, "", line) }
		# The multi-line block: its items are the warnings, the header is not.
		items && line ~ /^- / { emit("config", substr(line, 3)); next }
		items { items = 0 }
		index(line, tag) == 1 {
			msg = substr(line, length(tag) + 1)
			if (index(msg, header) == 1) { items = 1; next }
			for (i = 1; i <= nbenign; i++)
				if (index(msg, benign[i]) == 1) next
			emit("gradle", msg)
		}
	' "$log" >>"$findings" || true
fi

# What the plugin verifier wrote to disk.
#
# Three files always come out per verified IDE (dependencies, telemetry and the
# verdict); ANY OTHER file is the verifier having found something to say, so the
# scan does not need to know their names in advance -- which is just as well,
# since the set grows with the verifier. The verdict itself is the summary line
# ("Compatible", or "Compatible" followed by the usage counts), so anything that
# is not a bare "Compatible" is worth a line of its own.
if [ -d "$reports" ]; then
	for verdict in "$reports"/*/plugins/*/*/verification-verdict.txt; do
		[ -f "$verdict" ] || continue
		dir="$(dirname "$verdict")"
		# .../pluginVerifier/<IDE>/plugins/<id>/<version>/ -- the IDE build is
		# what names the finding, and it is four levels up.
		ide="$(basename "$(dirname "$(dirname "$(dirname "$dir")")")")"
		text="$(tr -d '\r' <"$verdict" | tr '\n' ' ' | sed 's/  */ /g; s/ *$//')"
		if [ "$text" != "Compatible" ]; then
			printf 'verifier\t%s: %s\n' "$ide" "$text" >>"$findings"
		fi
		for extra in "$dir"/*.txt; do
			[ -f "$extra" ] || continue
			case "$(basename "$extra")" in
			dependencies.txt | telemetry.txt | verification-verdict.txt) continue ;;
			esac
			printf 'verifier\t%s: %s (%s lines)\n' \
				"$ide" "$(basename "$extra")" \
				"$(wc -l <"$extra" | tr -d ' ')" >>"$findings"
		done
	done
fi

total="$(wc -l <"$findings" | tr -d ' ')"
if [ "$total" -eq 0 ]; then
	echo "JetBrains verification: nothing to report."
	exit 0
fi

tab="$(printf '\t')"

# GitHub shows at most ten annotations per step; the rest would be dropped
# without a word, so the count says so and the summary carries all of them.
shown=0
while IFS="$tab" read -r kind text; do
	shown=$((shown + 1))
	if [ "$shown" -le 10 ]; then
		printf '::warning title=JetBrains %s::%s\n' "$kind" "$text"
	fi
done <"$findings"
if [ "$total" -gt 10 ]; then
	printf '::warning title=JetBrains verification::%s more, in the job summary\n' \
		"$((total - 10))"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### JetBrains verification: $total warning(s)"
		echo
		echo "Not blocking. Each line is something a verification task said"
		echo "while still exiting zero."
		echo
		while IFS="$tab" read -r kind text; do
			echo "- \`$kind\` — $text"
		done <"$findings"
	} >>"$GITHUB_STEP_SUMMARY"
fi
