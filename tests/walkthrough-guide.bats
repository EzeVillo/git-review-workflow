#!/usr/bin/env bats
#
# Tests for git review walkthrough guide: the two authoring guides, the command
# that creates and removes them, and the porcelain records the panels read.
#
# The guides are prose about CONTENT (which entries are key, how to write a why,
# what belongs in the heads-up). Nothing in this suite reads, parses or validates
# one, so every test here is about custody: where the file lives, who may make it,
# who may remove it, and what is reported about it.

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global init.defaultBranch develop
	git config --global core.autocrlf false

	ORIGIN="$TMP/origin.git"
	WORK="$TMP/work"
	git init --quiet --bare "$ORIGIN"
	git init --quiet "$WORK"
	cd "$WORK"
	git remote add origin "$ORIGIN"
	git config reviewworkflow.base develop

	printf 'a1\n' >a.txt
	git add a.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/plain
	printf 'a1\na2\n' >a.txt
	git add -A
	git commit --quiet -m work
	git push --quiet -u origin feature/plain
	git switch --quiet develop

	OWN="$(git rev-parse --git-dir)/review-walkthrough-guide.md"
	TEAM="$WORK/.review/walkthrough-guide.md"
	DRAFT="$(git rev-parse --git-dir)/review-walkthrough/feature/plain.md"
}

teardown() {
	rm -rf "$TMP"
}

# ── creating ──────────────────────────────────────────────────────────────────

@test "guide creates your own guide empty and outside the work tree" {
	run git review walkthrough guide
	[ "$status" -eq 0 ]
	[[ "$output" == *"created your guide"* ]]
	[ -f "$OWN" ]
	# Empty on purpose: a skeleton with placeholders would be read by the next
	# agent as if the instructions were the conventions themselves.
	[ ! -s "$OWN" ]
	# The whole reason it is in the gitdir: git must not see it at all.
	run git status --porcelain
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "guide names the path it created" {
	run git review walkthrough guide
	[ "$status" -eq 0 ]
	[[ "$output" == *"review-walkthrough-guide.md"* ]]
}

@test "guide refuses to overwrite your existing guide" {
	printf 'my rules\n' >"$OWN"
	run git review walkthrough guide
	[ "$status" -eq 1 ]
	[[ "$output" == *"already exists"* ]]
	# Refusing means the prose survives byte for byte.
	[ "$(cat "$OWN")" = "my rules" ]
}

@test "guide --force is refused rather than honoured" {
	printf 'my rules\n' >"$OWN"
	run git review walkthrough guide --force
	[ "$status" -eq 1 ]
	[[ "$output" == *"--force does not apply"* ]]
	[ "$(cat "$OWN")" = "my rules" ]
}

@test "guide --team creates the shared guide in the work tree" {
	run git review walkthrough guide --team
	[ "$status" -eq 0 ]
	[[ "$output" == *".review/walkthrough-guide.md"* ]]
	[ -f "$TEAM" ]
	[ ! -s "$TEAM" ]
	# Untracked, so it does show up: it is meant to be committed with the code.
	run git status --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *".review/"* ]]
}

@test "guide --team refuses to overwrite the shared guide" {
	mkdir -p .review
	printf 'team rules\n' >"$TEAM"
	run git review walkthrough guide --team
	[ "$status" -eq 1 ]
	[[ "$output" == *"already exists"* ]]
	[ "$(cat "$TEAM")" = "team rules" ]
}

@test "guide --team is refused inside a review" {
	# finish extracts with git add -A, so a file created in the work tree now
	# would ride out on review-fixes/ into somebody else's PR.
	run git review start feature/plain
	[ "$status" -eq 0 ]
	run git review walkthrough guide --team
	[ "$status" -eq 1 ]
	[[ "$output" == *"inside a review"* ]]
	[[ "$output" == *"git review walkthrough guide"* ]]
	[ ! -e "$TEAM" ]
}

@test "guide creates your own guide inside a review" {
	# The other half of the rule: yours is not in the work tree, so a review is
	# exactly when writing it is useful.
	run git review start feature/plain
	[ "$status" -eq 0 ]
	run git review walkthrough guide
	[ "$status" -eq 0 ]
	[ -f "$OWN" ]
}

# ── removing ──────────────────────────────────────────────────────────────────

@test "guide --delete removes your own guide" {
	printf 'my rules\n' >"$OWN"
	run git review walkthrough guide --delete
	[ "$status" -eq 0 ]
	[[ "$output" == *"removed your guide"* ]]
	[ ! -e "$OWN" ]
}

@test "guide --delete refuses when you have no guide" {
	run git review walkthrough guide --delete
	[ "$status" -eq 1 ]
	[[ "$output" == *"no guide to remove"* ]]
}

@test "guide --delete --team refuses and names git rm" {
	mkdir -p .review
	printf 'team rules\n' >"$TEAM"
	printf 'my rules\n' >"$OWN"
	run git review walkthrough guide --delete --team
	[ "$status" -eq 1 ]
	[[ "$output" == *"git rm .review/walkthrough-guide.md"* ]]
	# Neither file is touched.
	[ "$(cat "$TEAM")" = "team rules" ]
	[ "$(cat "$OWN")" = "my rules" ]
}

# ── flag and argument discipline ──────────────────────────────────────────────

@test "guide takes no branch argument" {
	run git review walkthrough guide feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"only git review walkthrough draft takes a branch"* ]]
	[ ! -e "$OWN" ]
}

@test "guide rejects --check and --base" {
	run git review walkthrough guide --check
	[ "$status" -eq 1 ]
	[[ "$output" == *"--check applies only"* ]]
	run git review walkthrough guide --base develop
	[ "$status" -eq 1 ]
	[[ "$output" == *"--base applies only"* ]]
	[ ! -e "$OWN" ]
}

@test "--team and --delete are rejected on the other subcommands" {
	run git review walkthrough init --team
	[ "$status" -eq 1 ]
	[[ "$output" == *"--team and --delete apply only"* ]]
	run git review walkthrough draft --delete feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"--team and --delete apply only"* ]]
}

@test "an unknown subcommand names guide among the four" {
	run git review walkthrough nope
	[ "$status" -eq 1 ]
	[[ "$output" == *"init, build, draft or guide"* ]]
}

# ── porcelain ─────────────────────────────────────────────────────────────────

@test "config --porcelain reports both guides as absent when there are none" {
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"guide	team	"*"/.review/walkthrough-guide.md	absent"* ]]
	[[ "$output" == *"guide	own	"*"/review-walkthrough-guide.md	absent"* ]]
}

@test "config --porcelain tells empty apart from in-force" {
	git review walkthrough guide >/dev/null
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"/review-walkthrough-guide.md	empty"* ]]
	printf 'my rules\n' >"$OWN"
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"/review-walkthrough-guide.md	in-force"* ]]
}

@test "config --porcelain reads whitespace-only as empty, not in-force" {
	printf '   \n\t\n' >"$OWN"
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"/review-walkthrough-guide.md	empty"* ]]
}

@test "config --porcelain reports the guides with a branch argument too" {
	# A guide is a fact about the repository, not about the branch asked after.
	printf 'my rules\n' >"$OWN"
	run git review config --porcelain feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"/review-walkthrough-guide.md	in-force"* ]]
}

@test "the guide paths reported are absolute and openable" {
	printf 'my rules\n' >"$OWN"
	mkdir -p .review
	printf 'team rules\n' >"$TEAM"
	run git review config --porcelain
	[ "$status" -eq 0 ]
	# Every guide row's path column exists on disk exactly as reported. A client
	# opens what the CLI printed, so a path it cannot open is the bug this catches.
	printf '%s\n' "$output" >"$TMP/rows"
	n=0
	while IFS='	' read -r kind _ path _; do
		[ "$kind" = guide ] || continue
		n=$((n + 1))
		[ -f "$path" ]
	done <"$TMP/rows"
	[ "$n" -eq 2 ]
}

# ── custody: the guides are nobody else's business ────────────────────────────

@test "your guide is not mistaken for a draft" {
	# It lives beside review-walkthrough/, never inside it: walk_draft_list takes
	# every *.md in that directory as a branch name, so a guide filed there would
	# surface as a phantom draft.
	printf 'my rules\n' >"$OWN"
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" != *"draft	"* ]]
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" != *"guide"* ]]
}

@test "clean leaves your guide alone" {
	# Same rule that already covers the reviewer's draft, the --delta markers and
	# the saved reviews: clean prunes what it created, never prose somebody typed.
	# Only yours is asserted here -- the shared one is an ordinary file of the work
	# tree, which clean has no reach into at all.
	printf 'my rules\n' >"$OWN"
	run git review start feature/plain
	[ "$status" -eq 0 ]
	run git review abort
	[ "$status" -eq 0 ]
	run git review clean
	[ "$status" -eq 0 ]
	[ "$(cat "$OWN")" = "my rules" ]
}

@test "finish never carries your guide into review-fixes" {
	# The reason the reviewer's guide is in the gitdir at all: finish extracts the
	# working tree with git add -A, untracked files included.
	run git review start feature/plain
	[ "$status" -eq 0 ]
	run git review walkthrough guide
	[ "$status" -eq 0 ]
	printf 'my rules\n' >"$OWN"
	printf 'a1\na2\nfix\n' >a.txt
	run git review finish
	[ "$status" -eq 0 ]
	run git ls-tree -r --name-only review-fixes/feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" != *"review-walkthrough-guide"* ]]
	# And it is still there afterwards.
	[ "$(cat "$OWN")" = "my rules" ]
}

# ── el circuito con un agente: --stdout inlinea, el archivo apunta ────────────

@test "draft --stdout inlines the guide instead of naming its path" {
	# Ese esqueleto viaja por un pipe: el path absoluto de un gitdir no es algo
	# que el agente del otro lado pueda abrir necesariamente, y apuntarle a un
	# archivo que no alcanza falla en silencio -- nada verifica que lo leyo.
	printf 'marca key solo las migraciones\n' >"$OWN"
	run git review walkthrough draft --stdout --offline feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"marca key solo las migraciones"* ]]
	[[ "$output" == *"----- end -----"* ]]
	# La cerca igual nombra el archivo, para cuando SI se puede abrir.
	[[ "$output" == *"review-walkthrough-guide.md (the reviewer, private)"* ]]
}

@test "the written skeleton names the path and does not inline" {
	# El archivo aterriza al lado de las guias que nombra, y una copia embebida
	# en algo que sobrevive a esta corrida se pondria vieja sin que nadie mire.
	printf 'marca key solo las migraciones\n' >"$OWN"
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	grep -q 'review-walkthrough-guide\.md  (the reviewer, private)' "$DRAFT"
	run grep -c 'marca key solo las migraciones' "$DRAFT"
	[ "$output" = "0" ]
}

@test "an arrow in the guide cannot close the instruction block early" {
	# El bloque ES un comentario HTML: un "-->" literal adentro de la guia lo
	# cerraria antes de tiempo y volcaria el resto al preambulo.
	printf 'escribi asi: entrada --> porque\n' >"$OWN"
	run git review walkthrough draft --stdout --offline feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"entrada -- > porque"* ]]
	# El literal ya no esta, asi que el comentario no cierra ahi...
	[[ "$output" != *"entrada --> porque"* ]]
	# ...y la cerca de la guia sigue cerrando despues de esa linea.
	printf '%s\n' "$output" >"$TMP/sk"
	run awk '/entrada -- > porque/ { seen = 1 } seen && /----- end -----/ { print "closed"; exit }' "$TMP/sk"
	[ "$output" = "closed" ]
}

@test "an oversized guide is truncated instead of eating the whole output" {
	i=1
	while [ "$i" -le 200 ]; do
		printf 'regla %s\n' "$i" >>"$OWN"
		i=$((i + 1))
	done
	run git review walkthrough draft --stdout --offline feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"regla 120"* ]]
	[[ "$output" != *"regla 121"* ]]
	[[ "$output" == *"truncated at 120 lines"* ]]
}

@test "--stdout with no guide inlines nothing at all" {
	run git review walkthrough draft --stdout --offline feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" != *"Authoring guide"* ]]
	[[ "$output" != *"----- end -----"* ]]
}

# ── build tambien nombra la guia ──────────────────────────────────────────────

@test "build names the guide in force" {
	# Es el verbo que hace cumplir la regla que una guia mas suele llevar --
	# "marca pocas key" -- porque el aviso que salta cuando estan todas marcadas
	# es el suyo. Nombrarla solo en init/draft dejaba mudo justo a ese paso.
	git switch --quiet feature/plain
	mkdir -p .review
	printf 'marca pocas key\n' >"$TEAM"
	printf '# Walkthrough\n\n## Heads-up\n\nojo\n\n## 1. a.txt\nporque si\n' >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"authoring guide in force at .review/walkthrough-guide.md"* ]]
}

@test "build says how to create a guide when there is none" {
	git switch --quiet feature/plain
	mkdir -p .review
	printf '# Walkthrough\n\n## Heads-up\n\nojo\n\n## 1. a.txt\nporque si\n' >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"no authoring guide"* ]]
	[[ "$output" == *"git review walkthrough guide"* ]]
}

@test "the note is several short lines, not one long one" {
	# Con las dos en vigor la linea unica pasaba los 300 caracteres, que en una
	# terminal angosta es un paredon.
	mkdir -p .review
	printf 'team\n' >"$TEAM"
	printf 'mine\n' >"$OWN"
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" >"$TMP/note"
	run awk 'length($0) > 200 { n++ } END { print n + 0 }' "$TMP/note"
	[ "$output" = "0" ]
}

# ── el registro es de config --porcelain, y solo de ahi ─────────────────────

@test "status --porcelain does not report the guides inside a review" {
	# Las guias se dibujan en el pie del panel y una review no tiene pie, asi que
	# el reporte que se lee adentro de una review no las nombra: es un dato que
	# nadie pide en el camino que tiene que salir barato.
	printf 'my rules\n' >"$OWN"
	run git review start feature/plain
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" != *"guide	"* ]]
	# Y el dato sigue estando donde el panel lo lee: config --porcelain se
	# invoca igual desde adentro de una review y contesta lo mismo de siempre.
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"guide	team	"*"/.review/walkthrough-guide.md	absent"* ]]
	[[ "$output" == *"guide	own	"*"/review-walkthrough-guide.md	in-force"* ]]
}
