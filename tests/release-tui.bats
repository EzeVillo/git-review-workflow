#!/usr/bin/env bats

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	WORKFLOW="$REPO/.github/workflows/release-tui.yml"
}

@test "release-tui: workflow has isolated tag namespace and three jobs" {
	[ -f "$WORKFLOW" ]
	grep -q '"tui-v\*"' "$WORKFLOW"
	jobs="$(sed -n '/^jobs:/,$p' "$WORKFLOW" | sed -nE 's#^  ([a-z]+):$#\1#p')"
	[ "$jobs" = "verify
build
release" ]
}

@test "release-tui: release is not latest and publishes all checksum-verified assets" {
	grep -q -- '--latest=false' "$WORKFLOW"
	grep -q 'gh release create' "$WORKFLOW"
	grep -q 'sha256sum --check SHA256SUMS' "$WORKFLOW"
	for asset in \
		darwin_arm64.tar.gz darwin_amd64.tar.gz \
		linux_amd64.tar.gz linux_arm64.tar.gz linux_armv7.tar.gz \
		windows_amd64.zip windows_arm64.zip; do
		grep -q "$asset" "$WORKFLOW" || {
			echo "release workflow misses target suffix: $asset"
			false
		}
	done
}

@test "release-tui: verify runs Go and surface gates on tagged checkout" {
	grep -q 'gofmt -l' "$WORKFLOW"
	grep -q 'go vet ./...' "$WORKFLOW"
	grep -q 'go test ./...' "$WORKFLOW"
	grep -q 'node scripts/check-client-product-surface.mjs' "$WORKFLOW"
}

@test "release-tui: build commands run from the tui Go module" {
	build_block="$(sed -n '/      - name: Build seven static binaries/,/      - uses: actions\/upload-artifact/p' "$WORKFLOW")"
	[[ "$build_block" == *"working-directory: tui"* ]]
	[ "$(printf '%s\n' "$build_block" | grep -c 'go build .* ./cmd/git-review-ui')" -eq 2 ]
	[[ "$build_block" != *"./tui/cmd/git-review-ui"* ]]
}

@test "release-tui: upload artifact follows the build working directory" {
	build_block="$(sed -n '/      - name: Build seven static binaries/,/          if-no-files-found: error/p' "$WORKFLOW")"
	[[ "$build_block" == *"working-directory: tui"* ]]
	[[ "$build_block" == *"mkdir -p dist work"* ]]
	[[ "$build_block" == *"path: tui/dist/"* ]]
}

@test "release-tui: formula pin handles every platform indentation" {
	# Linux arm URLs are nested one level deeper than the other platforms. The
	# replacement must preserve arbitrary leading spaces or those checksums stay
	# placeholders after a successful release.
	grep -Fq 's#^([ ]+sha256 ).*#\1' "$WORKFLOW"
}
