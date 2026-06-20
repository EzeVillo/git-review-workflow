# Contributing

Thanks for taking the time to contribute! Bug reports, fixes and ideas are all
welcome.

## Development

The commands are POSIX shell scripts under `bin/`. Run the checks locally before
opening a pull request:

```sh
shellcheck bin/* install.sh uninstall.sh web-install.sh web-uninstall.sh
bats tests/
```

CI runs both on every push and pull request (see
[`.github/workflows/ci.yml`](.github/workflows/ci.yml)). Please make sure both
pass before requesting a review.

## Releasing

> Maintainers only.

Releases are cut by pushing a `v*` tag.

1. Bump the version in everything that ships *inside* the tarball, then tag that
   commit — so the artifact GitHub builds for the tag carries the right version:

   ```sh
   V=0.0.3
   printf '%s\n' "$V" >VERSION
   sed -i -E "s#^(VERSION=\")[^\"]*(\")#\1${V}\2#" bin/git-review
   git commit -am "Release $V"
   git tag "v$V"
   git push origin HEAD --tags
   ```

2. The release workflow
   ([`.github/workflows/release.yml`](.github/workflows/release.yml)) then
   handles only the files that point *at* the tarball (they need its `sha256`
   and don't live inside it):

    - creates a GitHub Release for the tag with auto-generated notes, and
    - pins the Homebrew formula (`url`, `sha256`, `version`) to the tag on the
      default branch, so `brew install` (without `--HEAD`) installs that version.
