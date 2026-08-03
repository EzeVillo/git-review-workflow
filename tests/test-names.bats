#!/usr/bin/env bats
#
# bats turns every @test name into a shell function name by escaping it byte by
# byte. The bats CI installs on Windows chokes on UTF-8 bytes and aborts the
# whole file with `unknown test name '...\342-80-94...'`, so an em dash or an
# accent in a name passes on Linux and macOS and only breaks on Windows — the
# slowest place to find out. This guard catches it on any OS in a second.

# LC_ALL=C makes `[ -~]` the printable ASCII range (0x20-0x7E) rather than
# whatever the locale considers printable, which is what bats actually cares
# about: the raw bytes of the name.
non_ascii_test_names() {
	LC_ALL=C grep -n '^[[:space:]]*@test' "$@" | LC_ALL=C grep '[^ -~]' || true
}

@test "test names: every @test name in the suite is pure ASCII" {
	cd "$BATS_TEST_DIRNAME"
	offenders="$(non_ascii_test_names ./*.bats)"
	if [ -n "$offenders" ]; then
		echo "Non-ASCII bytes in @test names (breaks bats on Windows):" >&2
		echo "$offenders" >&2
		return 1
	fi
}

@test "test names: the guard flags a name that is not ASCII" {
	# Without this the check above would keep passing even if the pattern broke.
	tmp="$(mktemp -d)"
	printf '@test "an em dash \xe2\x80\x94 in the name" {\n\ttrue\n}\n' >"$tmp/probe.bats"
	printf '@test "a plain ascii name" {\n\ttrue\n}\n' >"$tmp/clean.bats"

	flagged="$(non_ascii_test_names "$tmp/probe.bats")"
	ignored="$(non_ascii_test_names "$tmp/clean.bats")"
	rm -rf "$tmp"

	[ -n "$flagged" ]
	[ -z "$ignored" ]
}
