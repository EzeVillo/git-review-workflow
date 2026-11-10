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

@test "release-tui: pin advances the stable formula to the published assets" {
	work="$BATS_TEST_TMPDIR"
	export GIT_CONFIG_GLOBAL="$work/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file
	export GH_TOKEN=fixture DEFAULT_BRANCH=main GITHUB_REPOSITORY=example/git-review-workflow
	export GITHUB_REF_NAME=tui-v9.8.7 GITHUB_WORKSPACE="$work"
	mkdir -p "$work/source/Formula" "$work/dist"
	formula=Formula/git-review-ui.rb
	cp "$REPO/$formula" "$work/source/$formula"
	git -C "$work/source" init -q -b main
	git -C "$work/source" add "$formula"
	git -C "$work/source" -c user.name=fixture -c user.email=fixture@example.com commit -qm stable
	git clone -q --bare "$work/source" "$work/remote.git"
	remote="$(git -C "$work/remote.git" rev-parse --absolute-git-dir)"
	git config --global "url.$remote.insteadOf" "https://x-access-token:fixture@github.com/$GITHUB_REPOSITORY.git"

	i=1
	for suffix in darwin_arm64 darwin_amd64 linux_amd64 linux_arm64; do
		printf '%064d  git-review-ui_9.8.7_%s.tar.gz\n' "$i" "$suffix"
		i=$((i + 1))
	done >"$work/dist/SHA256SUMS"
	awk '
		{ sub(/\r$/, "") }
		/^      - name: Pin the Homebrew formula on the default branch$/ { step=1 }
		step && /^        run: \|$/ { body=1; next }
		body && /^          / { print substr($0, 11); next }
		body && NF { exit }
	' "$WORKFLOW" >"$work/pin.sh"
	[ -s "$work/pin.sh" ]

	run bash -e "$work/pin.sh"
	[ "$status" -eq 0 ]
	git -C "$remote" show "main:$formula" >"$work/pinned.rb"
	grep -Fxq '  version "9.8.7"' "$work/pinned.rb"
	while read -r sum asset; do
		pinned="$(awk -v asset="$asset" 'index($0, asset) { print; getline; print }' "$work/pinned.rb")"
		expected="      url \"https://github.com/$GITHUB_REPOSITORY/releases/download/$GITHUB_REF_NAME/$asset\"
      sha256 \"$sum\""
		[ "$pinned" = "$expected" ] || {
			printf 'expected for %s:\n%s\nactual:\n%s\n' "$asset" "$expected" "$pinned"
			return 1
		}
	done <"$work/dist/SHA256SUMS"
	pin="$(git -C "$remote" rev-parse main)"
	run bash -e "$work/pin.sh"
	[ "$status" -eq 0 ]
	[ "$(git -C "$remote" rev-parse main)" = "$pin" ]
}
