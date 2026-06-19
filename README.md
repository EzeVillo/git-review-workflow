# git-review-workflow

Git commands to review a pull request branch locally as a single, staged diff —
make fixes inline, then split your changes onto a clean branch (or straight onto
the PR branch) ready to push.

Comandos de git para revisar la rama de un pull request localmente como un único
diff staged — hacer correcciones inline y luego separar tus cambios en una rama
limpia (o directo sobre la rama del PR) lista para subir.

---

## English

### What it does

When you review a PR you usually want to see **all** of its changes at once and
poke at them. `git review-pr` creates a `review/<branch>` branch whose working
tree holds the PR tip, but whose `HEAD` sits at the merge-base with your base
branch. The result: the entire PR shows up as **staged, uncommitted changes**.
You read it, edit it, run it — and when you are done, `git finish-review`
extracts your edits onto a separate `review-fixes/<branch>` branch (or onto the
PR branch itself).

### Install

```sh
./install.sh
```

This symlinks `git-review-pr`, `git-finish-review` and `git-clean-review` into
`~/.local/bin` (override with `PREFIX=/usr/local/bin ./install.sh`). Make sure
that directory is on your `PATH`. Remove them with `./uninstall.sh`.

For tab completion, source the completion script from your shell rc:

```sh
source /path/to/git-review-workflow/completions/git-review-workflow.bash
```

### Commands

| Command | What it does |
| --- | --- |
| `git review-pr <branch> [base] [--delta]` | Fetch `origin`, then stage the whole PR diff on a new `review/<branch>` branch. |
| `git finish-review [--onto-source] [--push]` | From a `review/*` branch, extract your edits onto `review-fixes/<branch>` (or the PR branch). |
| `git clean-review [branch] [--forget]` | Delete the `review/*` and `review-fixes/*` branches for `<branch>`, or all of them. |

**`git review-pr`**
- `base` — branch to diff against. Defaults to `reviewworkflow.base` (see below),
  otherwise `develop`. A positional argument overrides it.
- `--delta` — review only the commits added **since your last review** of this
  branch, instead of the whole PR. Perfect for re-reviewing an updated PR.
- Always updates from `origin` first and **fails** if it cannot. The review is
  built from `origin/<branch>`, never a stale local copy.
- Refuses to run if you have local changes — start from a clean branch.

**`git finish-review`**
- Default — create `review-fixes/<branch>` on top of the PR tip with your edits
  staged, so you can review and commit them yourself.
- `--onto-source` (alias `--rebase`) — add your edits as a commit on the PR
  branch itself.
- `--push` — push the resulting branch to `origin`. With `--onto-source` it
  refuses to push if `origin/<branch>` moved since your review.

**`git clean-review`**
- With no `<branch>`, deletes every `review/*` and `review-fixes/*` branch.
- Never deletes the branch you are currently on.
- `--forget` also discards the recorded last-reviewed tip (which disables
  `--delta` for that branch).

### Configuring the base branch

The base branch is where PRs are integrated (`develop`, `main`, `master`, …) and
varies per team. Set it once per repository:

```sh
git config reviewworkflow.base develop
```

Resolution order: positional `base` argument → `reviewworkflow.base` → `develop`.

### Typical workflow

```sh
git config reviewworkflow.base develop      # once per repo

git review-pr feature/login                 # stage the whole PR
git status                                   # inspect the staged diff
# ...edit files, leave fixes, run tests...
git finish-review                            # extract fixes to review-fixes/feature/login
git diff --cached && git commit -m "address review comments"
git clean-review feature/login              # tidy up

# Re-review after the author pushes more commits:
git review-pr feature/login --delta          # only the new commits
```

### Requirements

- Git 2.23+ (uses `git switch`).
- A remote named `origin`.

---

## Español

### Qué hace

Cuando revisás un PR normalmente querés ver **todos** sus cambios de una y
toquetearlos. `git review-pr` crea una rama `review/<rama>` cuyo working tree
tiene el tip del PR, pero con el `HEAD` parado en el merge-base con tu rama base.
El resultado: todo el PR aparece como **cambios staged sin commitear**. Lo leés,
lo editás, lo corrés — y cuando terminás, `git finish-review` extrae tus
ediciones a una rama separada `review-fixes/<rama>` (o directo sobre la rama del
PR).

### Instalación

```sh
./install.sh
```

Hace symlink de `git-review-pr`, `git-finish-review` y `git-clean-review` en
`~/.local/bin` (cambialo con `PREFIX=/usr/local/bin ./install.sh`). Asegurate de
que ese directorio esté en tu `PATH`. Para quitarlos: `./uninstall.sh`.

Para autocompletado, sourceá el script de completion desde tu rc:

```sh
source /ruta/a/git-review-workflow/completions/git-review-workflow.bash
```

### Comandos

| Comando | Qué hace |
| --- | --- |
| `git review-pr <rama> [base] [--delta]` | Hace fetch de `origin` y deja todo el diff del PR staged en una nueva rama `review/<rama>`. |
| `git finish-review [--onto-source] [--push]` | Desde una rama `review/*`, extrae tus ediciones a `review-fixes/<rama>` (o la rama del PR). |
| `git clean-review [rama] [--forget]` | Borra las ramas `review/*` y `review-fixes/*` de `<rama>`, o todas. |

**`git review-pr`**
- `base` — rama contra la que comparar. Por defecto `reviewworkflow.base` (ver
  abajo), si no `develop`. El argumento posicional la sobreescribe.
- `--delta` — revisar solo los commits agregados **desde tu última review** de
  esta rama, en vez de todo el PR. Ideal para re-revisar un PR actualizado.
- Siempre actualiza desde `origin` primero y **falla** si no puede. La revisión
  se arma desde `origin/<rama>`, nunca desde una copia local vieja.
- No corre si tenés cambios locales — arrancá desde una rama limpia.

**`git finish-review`**
- Por defecto — crea `review-fixes/<rama>` sobre el tip del PR con tus ediciones
  staged, para que las revises y commitees vos.
- `--onto-source` (alias `--rebase`) — agrega tus ediciones como un commit sobre
  la rama del PR misma.
- `--push` — pushea la rama resultante a `origin`. Con `--onto-source` se niega a
  pushear si `origin/<rama>` se movió desde tu review.

**`git clean-review`**
- Sin `<rama>`, borra todas las ramas `review/*` y `review-fixes/*`.
- Nunca borra la rama en la que estás parado.
- `--forget` además descarta el tip de la última review (lo que desactiva
  `--delta` para esa rama).

### Configurar la rama base

La rama base es donde se integran los PRs (`develop`, `main`, `master`, …) y
varía por equipo. Configurala una vez por repositorio:

```sh
git config reviewworkflow.base develop
```

Orden de resolución: argumento posicional `base` → `reviewworkflow.base` →
`develop`.

### Flujo típico

```sh
git config reviewworkflow.base develop      # una vez por repo

git review-pr feature/login                 # dejar todo el PR staged
git status                                   # inspeccionar el diff staged
# ...editar archivos, dejar fixes, correr tests...
git finish-review                            # extraer fixes a review-fixes/feature/login
git diff --cached && git commit -m "address review comments"
git clean-review feature/login              # limpiar

# Re-revisar después de que el autor pushea más commits:
git review-pr feature/login --delta          # solo los commits nuevos
```

### Requisitos

- Git 2.23+ (usa `git switch`).
- Un remoto llamado `origin`.

---

## Development

Run the checks locally:

```sh
shellcheck bin/* install.sh uninstall.sh
bats tests/
```

CI runs both on every push and pull request (see `.github/workflows/ci.yml`).
