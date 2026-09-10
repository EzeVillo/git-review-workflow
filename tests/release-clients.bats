#!/usr/bin/env bats

# The store uploads must be the package that the tagged tree built. A workflow
# that publishes a rebuilt, unstamped or unrelated file can look green while
# shipping a different extension than the GitHub Release attaches.

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	CLI="$REPO/.github/workflows/release.yml"
	VSCODE="$REPO/.github/workflows/release-vscode.yml"
	VISUALSTUDIO="$REPO/.github/workflows/release-visualstudio.yml"
}

@test "release-clients: CLI tags start with a semver digit" {
	[ -f "$CLI" ]
	grep -Fq '"v[0-9]*"' "$CLI"
}

@test "release-clients: workflows use isolated client tag namespaces" {
	[ -f "$VSCODE" ]
	[ -f "$VISUALSTUDIO" ]
	grep -Fq '"vscode-v*"' "$VSCODE"
	grep -Fq '"visualstudio-v*"' "$VISUALSTUDIO"
}

@test "release-clients: workflows reject a missing Marketplace token before packaging" {
	for workflow in "$VSCODE" "$VISUALSTUDIO"; do
		grep -Fq 'PUBLISH_TOKEN_CONFIGURED: ${{ secrets.VS_MARKETPLACE_TOKEN !=' "$workflow"
		grep -Fq 'VS_MARKETPLACE_TOKEN is not set.' "$workflow"
	done
}

@test "release-clients: the raw Marketplace token reaches only each publish step" {
	for workflow in "$VSCODE" "$VISUALSTUDIO"; do
		count="$(grep -Fc 'PUBLISH_TOKEN: ${{ secrets.VS_MARKETPLACE_TOKEN }}' "$workflow")"
		[ "$count" -eq 1 ] || {
			echo "$workflow exposes the raw token $count times"
			return 1
		}
	done
}

@test "release-clients: token preflights precede dependency setup" {
	for workflow in "$VSCODE" "$VISUALSTUDIO"; do
		preflight="$(grep -n 'Check the Marketplace token is configured' "$workflow" | cut -d: -f1)"
		setup="$(grep -n 'actions/setup-' "$workflow" | head -n1 | cut -d: -f1)"
		[ -n "$preflight" ]
		[ -n "$setup" ]
		[ "$preflight" -lt "$setup" ]
	done
}

@test "release-clients: VS Code publishes and attaches its packaged VSIX" {
	grep -Fq 'npm run package' "$VSCODE"
	grep -Fq 'vsce publish --packagePath' "$VSCODE"
	grep -Fq 'git-review-workflow-${VERSION}.vsix' "$VSCODE"
	grep -Fq 'gh release create' "$VSCODE"
	grep -Fq -- '--latest=false' "$VSCODE"
}

@test "release-clients: Visual Studio publishes and attaches its built VSIX" {
	grep -Fq 'runs-on: windows-latest' "$VISUALSTUDIO"
	grep -Fq './build-vsix.ps1' "$VISUALSTUDIO"
	grep -Fq 'VsixPublisher.exe' "$VISUALSTUDIO"
	grep -Fq 'GitReview.VS.vsix' "$VISUALSTUDIO"
	grep -Fq 'publishmanifest.json' "$VISUALSTUDIO"
	grep -Fq 'gh release create' "$VISUALSTUDIO"
	grep -Fq -- '--latest=false' "$VISUALSTUDIO"
}

@test "release-clients: retries recover the Marketplace and GitHub release separately" {
	grep -Fq 'vsce show EzeVillo.git-review-workflow --json' "$VSCODE"
	grep -Fq 'marketplace-vsix-status.mjs' "$VSCODE"
	grep -Fq 'sha256sum "$vsix"' "$VSCODE"
	grep -Fq 'gh release download' "$VSCODE"
	grep -Fq 'gh release create "$GITHUB_REF_NAME" "$vsix"' "$VSCODE"
	grep -Fq -- '--draft=false' "$VSCODE"
	grep -Fq -- '--draft' "$VSCODE"
	grep -Fq 'gh release view' "$VSCODE"
	grep -Fq 'gh release view' "$VISUALSTUDIO"
	grep -Fq 'gh release upload' "$VISUALSTUDIO"
}

@test "release-clients: VS Code recovery publishes the draft asset before finalizing it" {
	download="$(grep -n 'gh release download' "$VSCODE" | cut -d: -f1)"
	output="$(grep -n 'echo "vsix=${vsix}" >>"$GITHUB_OUTPUT"' "$VSCODE" | cut -d: -f1)"
	marketplace="$(grep -n 'VSIX: ${{ steps.release_asset.outputs.vsix }}' "$VSCODE" | cut -d: -f1)"
	finalize="$(grep -n 'gh release edit "$GITHUB_REF_NAME"' "$VSCODE" | tail -n1 | cut -d: -f1)"

	[ -n "$download" ]
	[ -n "$output" ]
	[ -n "$marketplace" ]
	[ -n "$finalize" ]
	[ "$download" -lt "$output" ]
	[ "$output" -lt "$marketplace" ]
	[ "$marketplace" -lt "$finalize" ]
	block="$(sed -n "${marketplace},${finalize}p" "$VSCODE")"
	[[ "$block" == *'vsix="$VSIX"'* ]]
	[[ "$block" == *'exit "$status"'* ]]
}

@test "release-clients: Visual Studio publish manifest exposes the intended listing" {
	manifest="$REPO/visualstudio-extension/marketplace/publishmanifest.json"
	[ -f "$manifest" ]
	grep -Fq '"publisher": "EzeVillo"' "$manifest"
	grep -Fq '"internalName": "gitreviewworkflow"' "$manifest"
	grep -Fq '"overview": "overview.md"' "$manifest"
	grep -Fq '"private": false' "$manifest"
}
