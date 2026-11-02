#!/usr/bin/env bats

setup_file() { bats_require_minimum_version 1.13.0; }

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	WORKFLOW="$REPO/.github/workflows/release-landing.yml"
	export GITHUB_REF_NAME=landing-v1.2.3
	export GITHUB_SHA=0123456789abcdef0123456789abcdef01234567
	export GITHUB_WORKSPACE="$BATS_TEST_TMPDIR/tagged checkout"
	export CLOUDFLARE_API_TOKEN_CONFIGURED=true
	export CLOUDFLARE_ACCOUNT_ID=cloudflare-account-id
	export DEPLOY_ARGS="$BATS_TEST_TMPDIR/deploy-args"
	export DEPLOY_CONTENT="$BATS_TEST_TMPDIR/deployed.html"
	mkdir -p "$BATS_TEST_TMPDIR/bin" "$GITHUB_WORKSPACE/docs"
	printf 'tagged landing\n' >"$GITHUB_WORKSPACE/docs/index.html"
	cat >"$BATS_TEST_TMPDIR/bin/npx" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$@" >"$DEPLOY_ARGS"
while [ "$#" -gt 0 ]; do
	if [ "$1" = --assets ]; then
		shift
		cp "$1/index.html" "$DEPLOY_CONTENT"
		break
	fi
	shift
done
exit "${FAKE_DEPLOY_STATUS:-0}"
SH
	chmod +x "$BATS_TEST_TMPDIR/bin/npx"
	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# Execute the actual workflow shell blocks, including on Windows checkouts.
workflow_step() {
	awk -v step="      - name: $1" '
		{ sub(/\r$/, "") }
		$0 == step { found = 1; next }
		found && /^      - / { exit }
		found && /^        run: \|$/ { body = 1; next }
		body { sub(/^          /, ""); print }
	' "$WORKFLOW"
}

@test "release-landing: only landing tag pushes trigger publication" {
	run awk '
		{ sub(/\r$/, "") }
		/^permissions:/ { exit }
		/^on:/ { body = 1 }
		body && NF { print }
	' "$WORKFLOW"
	[ "$status" -eq 0 ]
	[ "$output" = 'on:
  push:
    tags:
      - "landing-v*"' ]
	grep -Fq 'ref: ${{ github.sha }}' "$WORKFLOW"
	grep -Fq 'group: landing-production' "$WORKFLOW"
	grep -Fq 'cancel-in-progress: false' "$WORKFLOW"
}

@test "release-landing: valid independent landing versions pass validation" {
	script="$(workflow_step 'Validate landing tag')"
	[ -n "$script" ]
	for tag in landing-v0.1.0 landing-v1.2.3 landing-v10.20.30; do
		run --separate-stderr env GITHUB_REF_NAME="$tag" sh -c "$script"
		[ "$status" -eq 0 ]
		[ -z "$output" ]
		[ -z "$stderr" ]
	done
}

@test "release-landing: branches client tags and malformed versions are rejected" {
	script="$(workflow_step 'Validate landing tag')"
	[ -n "$script" ]
	for tag in main v1.2.3 vscode-v1.2.3 landing-v1.2 landing-v01.2.3 landing-v1.2.3-beta; do
		run --separate-stderr env GITHUB_REF_NAME="$tag" sh -c "$script"
		[ "$status" -eq 1 ]
		[ -z "$output" ]
		[ "$stderr" = "Expected a landing-vX.Y.Z tag; got $tag." ]
		[ ! -e "$DEPLOY_ARGS" ]
	done
}

@test "release-landing: missing token fails with a configuration error" {
	script="$(workflow_step 'Check Cloudflare configuration')"
	[ -n "$script" ]
	run --separate-stderr env CLOUDFLARE_API_TOKEN_CONFIGURED=false sh -c "$script"
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[ "$stderr" = 'CLOUDFLARE_API_TOKEN is not set. Add the repository secret before tagging.' ]
	[ ! -e "$DEPLOY_ARGS" ]
}

@test "release-landing: missing account fails instead of selecting an account interactively" {
	script="$(workflow_step 'Check Cloudflare configuration')"
	[ -n "$script" ]
	run --separate-stderr env CLOUDFLARE_ACCOUNT_ID= sh -c "$script"
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[ "$stderr" = 'CLOUDFLARE_ACCOUNT_ID is not set. Add the repository secret before tagging.' ]
	[ ! -e "$DEPLOY_ARGS" ]
}

@test "release-landing: configured credentials pass preflight" {
	script="$(workflow_step 'Check Cloudflare configuration')"
	[ -n "$script" ]
	run --separate-stderr sh -c "$script"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
}

@test "release-landing: deploy uploads tagged docs without building and records tag and SHA" {
	script="$(workflow_step 'Deploy tagged landing')"
	[ -n "$script" ]
	run --separate-stderr sh -c "$script"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ "$(cat "$DEPLOY_ARGS")" = "--yes
wrangler@4.148.0
deploy
--config
$GITHUB_WORKSPACE/wrangler.jsonc
--assets
$GITHUB_WORKSPACE/docs
--message
$GITHUB_REF_NAME ($GITHUB_SHA)" ]
	cmp "$GITHUB_WORKSPACE/docs/index.html" "$DEPLOY_CONTENT"
}

@test "release-landing: deploy failure propagates to the workflow" {
	script="$(workflow_step 'Deploy tagged landing')"
	[ -n "$script" ]
	run --separate-stderr env FAKE_DEPLOY_STATUS=17 sh -c "$script"
	[ "$status" -eq 17 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ -s "$DEPLOY_ARGS" ]
}
