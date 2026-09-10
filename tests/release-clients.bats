#!/usr/bin/env bats

# The store uploads must be the package that the tagged tree built. A workflow
# that publishes a rebuilt, unstamped or unrelated file can look green while
# shipping a different extension than the GitHub Release attaches.

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	VSCODE="$REPO/.github/workflows/release-vscode.yml"
	VISUALSTUDIO="$REPO/.github/workflows/release-visualstudio.yml"
}

@test "release-clients: workflows use isolated client tag namespaces" {
	[ -f "$VSCODE" ]
	[ -f "$VISUALSTUDIO" ]
	grep -Fq '"vscode-v*"' "$VSCODE"
	grep -Fq '"visualstudio-v*"' "$VISUALSTUDIO"
}

@test "release-clients: workflows reject a missing Marketplace token before packaging" {
	for workflow in "$VSCODE" "$VISUALSTUDIO"; do
		grep -Fq 'secrets.VS_MARKETPLACE_TOKEN' "$workflow"
		grep -Fq 'VS_MARKETPLACE_TOKEN is not set.' "$workflow"
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

@test "release-clients: Visual Studio publish manifest exposes the intended listing" {
	manifest="$REPO/visualstudio-extension/marketplace/publishmanifest.json"
	[ -f "$manifest" ]
	grep -Fq '"publisher": "EzeVillo"' "$manifest"
	grep -Fq '"internalName": "git-review-workflow-vs"' "$manifest"
	grep -Fq '"overview": "overview.md"' "$manifest"
	grep -Fq '"private": false' "$manifest"
}
