# Walkthrough authoring guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hacer que `git review walkthrough init` y `draft` señalen un guide opcional del repo (`.review/walkthrough-guide.md`) para criterios de contenido, sin cambiar el formato del walkthrough.

**Architecture:** Un bullet en el HTML comment del skeleton compartido, más una `note:` en stderr según exista o no el archivo en el work tree; docs en ambos README. La CLI no lee ni valida el guide.

**Tech Stack:** shell POSIX (`bin/git-review-verbs/walkthrough`), bats, Markdown (README.md / README.es.md).

**Spec:** [docs/superpowers/specs/2026-08-11-walkthrough-guide-design.md](../specs/2026-08-11-walkthrough-guide-design.md)

## Global Constraints

- Solo shell POSIX con `set -eu`; nada de bashisms.
- Mensajes de producto en inglés (como el resto del verbo).
- Nombres de `@test` en ASCII puro (sin em dashes ni acentos).
- Actualizar **ambos** README en el mismo cambio.
- No tocar landing, extensión, IntelliJ, ni reglas de `build`.
- Path fijo: `.review/walkthrough-guide.md` (work tree del repo donde se corre el comando).
- En Windows, tests vía `./tests/run-docker.sh`.

## File map

| File | Responsibility |
|------|----------------|
| `bin/git-review-verbs/walkthrough` | Skeleton comment + note de presencia al final de init/draft |
| `tests/walkthrough.bats` | Tests init: skeleton path + notes found/optional |
| `tests/walkthrough-draft.bats` | Tests draft: same notes (work tree guide) |
| `README.md` / `README.es.md` | Documentar el guide opcional |

---

### Task 1: Tests + CLI (init y draft)

**Files:**
- Modify: `tests/walkthrough.bats` (agregar tests al final de la sección init, o junto a los de init)
- Modify: `tests/walkthrough-draft.bats` (agregar tests de notes)
- Modify: `bin/git-review-verbs/walkthrough` (skeleton + note tras el write)

**Interfaces:**
- Path canónico: `.review/walkthrough-guide.md`
- Note si existe: `note: authoring guide found at .review/walkthrough-guide.md; use it for keys/whys (it cannot change the format)`
- Note si no existe: `note: optional authoring guide: create .review/walkthrough-guide.md for team rules on keys/whys (it cannot change the format)`
- Bullet del skeleton debe contener la subcadena `.review/walkthrough-guide.md` y dejar claro content-only / cannot change format

- [x] **Step 1: Write failing tests in `tests/walkthrough.bats`**

Agregar (nombres ASCII):

```bash
@test "init skeleton mentions the optional authoring guide path" {
	run git review walkthrough init
	[ "$status" -eq 0 ]
	grep -q '\.review/walkthrough-guide\.md' .review/walkthrough.md
	grep -qi 'cannot change' .review/walkthrough.md
}

@test "init notes optional guide when none exists" {
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" == *"optional authoring guide"* ]]
	[[ "$output" == *".review/walkthrough-guide.md"* ]]
	[[ "$output" != *"authoring guide found"* ]]
}

@test "init notes found guide when the file exists" {
	mkdir -p .review
	printf '# team rules\nmark entry points as key\n' >.review/walkthrough-guide.md
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" == *"authoring guide found at .review/walkthrough-guide.md"* ]]
	[[ "$output" != *"optional authoring guide: create"* ]]
}
```

- [x] **Step 2: Write failing tests in `tests/walkthrough-draft.bats`**

```bash
@test "draft skeleton mentions the optional authoring guide path" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	grep -q '\.review/walkthrough-guide\.md' "$DRAFT"
	grep -qi 'cannot change' "$DRAFT"
}

@test "draft notes optional guide when none exists in the work tree" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"optional authoring guide"* ]]
	[[ "$output" == *".review/walkthrough-guide.md"* ]]
	[[ "$output" != *"authoring guide found"* ]]
}

@test "draft notes found guide when the work tree has one" {
	mkdir -p .review
	printf '# team rules\n' >.review/walkthrough-guide.md
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"authoring guide found at .review/walkthrough-guide.md"* ]]
	[[ "$output" != *"optional authoring guide: create"* ]]
}
```

- [x] **Step 3: Run tests to verify they fail**

```sh
./tests/run-docker.sh walkthrough.bats walkthrough-draft.bats
```

Expected: nuevos tests FAIL (skeleton sin path del guide / notes ausentes).

- [x] **Step 4: Implement in `bin/git-review-verbs/walkthrough`**

1. En el bloque del HTML comment del skeleton (antes del Heads-up bullet o después de keys), agregar un bullet, p.ej. después del bullet de Heads-up y **antes** del blank line que cierra la lista compartida:

```sh
printf '       * Optional authoring guide: if .review/walkthrough-guide.md exists\n'
printf '         in this repository, follow it for content choices only (which\n'
printf '         entries are key, how to write whys / Heads-up, team conventions).\n'
printf '         It cannot change this format, the file list, or the numbering\n'
printf '         rules above.\n\n'
```

(El bullet de Heads-up hoy termina con `\n\n` — insertar el guide **antes** de ese cierre doble, o reemplazar el cierre del Heads-up por un solo `\n` y cerrar con `\n\n` tras el guide.)

2. Tras el `echo "wrote ..."` y las notes existentes de draft/dirty, **antes** de `exit 0`, emitir la note de presencia. Resolver el path desde el top-level del repo:

```sh
guide_path="$(git rev-parse --show-toplevel)/.review/walkthrough-guide.md"
if [ -f "$guide_path" ]; then
	echo "note: authoring guide found at .review/walkthrough-guide.md; use it for keys/whys (it cannot change the format)" >&2
else
	echo "note: optional authoring guide: create .review/walkthrough-guide.md for team rules on keys/whys (it cannot change the format)" >&2
fi
```

Colocar esto **una sola vez** al final del bloque init/draft (después del if draft/else init), para que init y draft lo compartan.

- [x] **Step 5: Run tests to verify they pass**

```sh
./tests/run-docker.sh walkthrough.bats walkthrough-draft.bats
```

Expected: PASS (incluidos los tests previos de init/draft).

- [x] **Step 6: Commit**

```bash
git add bin/git-review-verbs/walkthrough tests/walkthrough.bats tests/walkthrough-draft.bats
git commit -m "feat: point walkthrough init/draft at optional authoring guide"
```

---

### Task 2: README EN + ES

**Files:**
- Modify: `README.md` (sección `git review walkthrough`)
- Modify: `README.es.md` (misma sección)

- [x] **Step 1: Document the guide in both READMEs**

Después del bullet de `> key` (o tras la descripción de `init`), agregar un bullet espejo:

**EN** (idea):

- **Authoring guide (optional):** commit `.review/walkthrough-guide.md` with team rules for content only — which files to mark `> key`, how to write whys and Heads-up. It does not change the walkthrough format; `build` does not validate it. `init` and `draft` note whether the file is present and mention the path in the skeleton instructions.

**ES** (idea):

- **Guide de autoría (opcional):** commiteá `.review/walkthrough-guide.md` con las reglas del equipo solo de *contenido* — qué marcar `> key`, cómo escribir los porqués y el Heads-up. No cambia el formato del walkthrough; `build` no lo valida. `init` y `draft` avisan si el archivo está y lo mencionan en las instrucciones del esqueleto.

No tocar `docs/index.html`.

- [x] **Step 2: Commit**

```bash
git add README.md README.es.md
git commit -m "docs: document optional walkthrough authoring guide"
```

---

## Self-review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| Path fijo `.review/walkthrough-guide.md` | Task 1 |
| Bullet en skeleton (content-only, cannot change format) | Task 1 |
| Note found / optional create | Task 1 |
| init y draft | Task 1 |
| Work tree, no tip del PR | Task 1 (draft test con guide local) |
| README EN+ES | Task 2 |
| No build/landing/UIs/subcomando | fuera de plan a propósito |
