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

**Via web (no git clone needed):**

```sh
curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.sh | sh
```

Copies the commands into `~/.local/bin`. Make sure that directory is on your
`PATH`. To update, re-run the same command — it always installs the latest
release.

**From a local clone:**

```sh
./install.sh
```

This symlinks `git-review-pr`, `git-finish-review` and `git-clean-review` into
`~/.local/bin` (override with `PREFIX=/usr/local/bin ./install.sh`). Make sure
that directory is on your `PATH`. Remove them with `./uninstall.sh`.

To update, just `git pull` inside the repo — the symlinks pick up changes
automatically.

For tab completion, source the completion script from your shell rc:

```sh
source /path/to/git-review-workflow/completions/git-review-workflow.bash
```

### Commands

| Command | What it does |
| --- | --- |
| `git review-pr <branch> [base] [--delta\|--from <commit>] [--step]` | Fetch `origin`, then stage the PR diff on a new `review/<branch>` branch. |
| `git review-next` / `git review-prev` | Move a `--step` review to the next / previous commit. |
| `git review-status` | Show the state of the review on the current branch. |
| `git finish-review [--onto-source] [--push] [--resume]` | From a `review/*` branch, extract your edits onto `review-fixes/<branch>` (or the PR branch). |
| `git review-abort` | Cancel the current review and return to where you started. |
| `git clean-review [branch] [--forget]` | Delete the `review/*` and `review-fixes/*` branches for `<branch>`, or all of them. |

**`git review-pr`** has two independent axes — **range** (where the review
starts) and **layout** (`--step` or not), which compose freely.

- `base` — branch to diff against, taken from `reviewworkflow.base` (see below);
  a positional argument overrides it. **Required for a full review** — there is
  no built-in default, so a full review with no base set fails and asks you to
  configure one. Not used with `--delta` or `--from`, which carry their own
  starting point — passing an explicit base alongside them is an error (a base
  from config is simply ignored).
- `--delta` — review only the commits added **since your last review** of this
  branch, instead of the whole PR. Perfect for re-reviewing an updated PR. The
  recorded tip survives `clean-review` (unless `--forget`), so this works even
  after you deleted the review branches.
- `--from <commit>` — review only the commits **after `<commit>`**. Handy when
  there is no recorded review to delta from, or to pick an exact starting point.
  Mutually exclusive with `--delta`.
- `--step` — review the range **one commit at a time** (combine with `--delta`
  or `--from` to walk just those commits). You start on the first
  commit after the merge-base; the command prints its author message. Edit
  files, then run `git review-next` to bank your edits and move to the next
  commit with a clean tree (no leftover from earlier commits or your own
  edits). When the commits run out, run `git finish-review` and all your banked
  edits are replayed onto the PR tip — exactly as in a whole-PR review.
- Always updates from `origin` first and **fails** if it cannot. The review is
  built from `origin/<branch>`, never a stale local copy.
- Refuses to run if you have local changes — start from a clean branch.

**`git review-next` / `git review-prev`** move a `--step` review forward or
backward. Each move banks the current commit's edits and restores any edits you
had banked on the commit you move to, so you can walk back and forth without
losing work.

**`git review-status`** shows the current review: source PR, mode, and — in
`--step` mode — which commit you are on (`[k/N]`) and which steps have banked
edits. Useful for picking up where you left off.

**`git finish-review`**
- Default — create `review-fixes/<branch>` on top of the PR tip with your edits
  staged, so you can review and commit them yourself.
- `--onto-source` — add your edits as a commit on the PR branch itself.
- `--push` — push the resulting branch to `origin`. With `--onto-source` it
  refuses to push if `origin/<branch>` moved since your review.
- `--resume` — in `--step` mode, if banked edits overlap the PR tip, the replay
  leaves conflict markers and stops. Resolve them in the working tree, then run
  `git finish-review --resume` (with the same flags) to continue.

**`git review-abort`** cancels the current review in one step: it returns you to
the branch you started from, then deletes the `review/<branch>` branch and its
banked edits. Because the review was cancelled (not completed), it rolls the
`--delta` marker back to your last actual review, so a later `--delta` does not
skip commits you never reviewed. (`clean-review`, by contrast, keeps the marker —
cleaning up after a real review is not the same as cancelling one.)

**`git clean-review`**
- With no `<branch>`, deletes every `review/*` and `review-fixes/*` branch.
- Never deletes the branch you are currently on.
- `--forget` also discards the recorded last-reviewed tip (which disables
  `--delta` for that branch).

### Configuring the base branch

The base branch is where PRs are integrated (`develop`, `main`, `master`, …) and
varies per team, so there is no default — set it once per repository:

```sh
git config reviewworkflow.base develop
```

Resolution order: positional `base` argument → `reviewworkflow.base`. If neither
is set, a full review fails and asks you to configure one.

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
git review-pr feature/login --delta --step   # ...and walk them one by one

# Or walk the PR commit by commit from the start:
git review-pr feature/login --step           # start on the first commit
# ...edit, then...
git review-next                              # bank edits, move to the next commit
git review-next                              # ...until "no more commits"
git finish-review                            # replay all your edits onto the tip

# Pick an explicit starting commit:
git review-pr feature/login --from a1b2c3d
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

**Por web (sin necesidad de clonar el repo):**

```sh
curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.sh | sh
```

Copia los comandos en `~/.local/bin`. Asegurate de que ese directorio esté en tu
`PATH`. Para actualizar, volvé a correr el mismo comando — siempre instala la
última versión.

**Desde un clon local:**

```sh
./install.sh
```

Hace symlink de `git-review-pr`, `git-finish-review` y `git-clean-review` en
`~/.local/bin` (cambialo con `PREFIX=/usr/local/bin ./install.sh`). Asegurate de
que ese directorio esté en tu `PATH`. Para quitarlos: `./uninstall.sh`.

Para actualizar, simplemente hacé `git pull` dentro del repo — los symlinks
toman los cambios automáticamente.

Para autocompletado, sourceá el script de completion desde tu rc:

```sh
source /ruta/a/git-review-workflow/completions/git-review-workflow.bash
```

### Comandos

| Comando | Qué hace |
| --- | --- |
| `git review-pr <rama> [base] [--delta\|--from <commit>] [--step]` | Hace fetch de `origin` y deja el diff del PR staged en una nueva rama `review/<rama>`. |
| `git review-next` / `git review-prev` | Mueve una review `--step` al commit siguiente / anterior. |
| `git review-status` | Muestra el estado de la review en la rama actual. |
| `git finish-review [--onto-source] [--push] [--resume]` | Desde una rama `review/*`, extrae tus ediciones a `review-fixes/<rama>` (o la rama del PR). |
| `git review-abort` | Cancela la review actual y vuelve a donde empezaste. |
| `git clean-review [rama] [--forget]` | Borra las ramas `review/*` y `review-fixes/*` de `<rama>`, o todas. |

**`git review-pr`** tiene dos ejes independientes — **rango** (desde dónde
empieza) y **layout** (`--step` o no), que se combinan libremente.

- `base` — rama contra la que comparar, tomada de `reviewworkflow.base` (ver
  abajo); el argumento posicional la sobreescribe. **Obligatoria para una review
  completa** — no hay default, así que una review completa sin base configurada
  falla y te pide que la configures. No se usa con `--delta` ni `--from`, que ya
  traen su propio punto de inicio — pasar una base explícita junto con ellos es
  un error (una base que viene de config simplemente se ignora).
- `--delta` — revisar solo los commits agregados **desde tu última review** de
  esta rama, en vez de todo el PR. Ideal para re-revisar un PR actualizado. El
  tip registrado sobrevive a `clean-review` (salvo `--forget`), así que funciona
  aunque hayas borrado las ramas de review.
- `--from <commit>` — revisar solo los commits **después de `<commit>`**. Útil
  cuando no hay review registrada para usar `--delta`, o para elegir un punto de
  inicio exacto. Mutuamente excluyente con `--delta`.
- `--step` — revisar el rango **de a un commit por vez** (combinalo con
  `--delta` o `--from` para recorrer solo esos commits). Arrancás en el primer
  commit después del merge-base y el comando imprime el mensaje del autor.
  Editás y corrés `git review-next` para bancar tus cambios y pasar al siguiente
  commit con el árbol limpio (sin nada de los commits anteriores ni de tus
  propias ediciones). Cuando se acaban los commits, corrés `git finish-review` y
  todas tus ediciones bancadas se re-aplican sobre el tip del PR — igual que en
  una review completa.
- Siempre actualiza desde `origin` primero y **falla** si no puede. La revisión
  se arma desde `origin/<rama>`, nunca desde una copia local vieja.
- No corre si tenés cambios locales — arrancá desde una rama limpia.

**`git review-next` / `git review-prev`** mueven una review `--step` para
adelante o para atrás. Cada movimiento banca las ediciones del commit actual y
restaura las que tenías bancadas en el commit al que vas, así podés ir y venir
sin perder trabajo.

**`git review-status`** muestra la review actual: PR de origen, modo, y — en modo
`--step` — en qué commit estás (`[k/N]`) y qué pasos tienen ediciones bancadas.
Útil para retomar donde dejaste.

**`git finish-review`**
- Por defecto — crea `review-fixes/<rama>` sobre el tip del PR con tus ediciones
  staged, para que las revises y commitees vos.
- `--onto-source` — agrega tus ediciones como un commit sobre la rama del PR
  misma.
- `--resume` — en modo `--step`, si las ediciones bancadas chocan con el tip del
  PR, el replay deja marcadores de conflicto y se detiene. Resolvélos en el
  árbol y corré `git finish-review --resume` (con los mismos flags) para seguir.
- `--push` — pushea la rama resultante a `origin`. Con `--onto-source` se niega a
  pushear si `origin/<rama>` se movió desde tu review.

**`git review-abort`** cancela la review actual en un paso: te devuelve a la rama
desde la que empezaste y borra la rama `review/<rama>` y sus ediciones bancadas.
Como la review se canceló (no se completó), vuelve el marcador de `--delta` a tu
última review real, así un `--delta` posterior no se saltea commits que nunca
revisaste. (`clean-review`, en cambio, conserva el marcador — limpiar después de
una review real no es lo mismo que cancelarla.)

**`git clean-review`**
- Sin `<rama>`, borra todas las ramas `review/*` y `review-fixes/*`.
- Nunca borra la rama en la que estás parado.
- `--forget` además descarta el tip de la última review (lo que desactiva
  `--delta` para esa rama).

### Configurar la rama base

La rama base es donde se integran los PRs (`develop`, `main`, `master`, …) y
varía por equipo, así que no hay default — configurala una vez por repositorio:

```sh
git config reviewworkflow.base develop
```

Orden de resolución: argumento posicional `base` → `reviewworkflow.base`. Si no
hay ninguno, una review completa falla y te pide que la configures.

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
git review-pr feature/login --delta --step   # ...y recorrerlos de a uno

# O recorrer el PR commit por commit desde el principio:
git review-pr feature/login --step           # arrancar en el primer commit
# ...editar, y después...
git review-next                              # bancar cambios, pasar al siguiente
git review-next                              # ...hasta "no more commits"
git finish-review                            # re-aplicar todos tus cambios sobre el tip

# Elegir un commit de inicio explícito:
git review-pr feature/login --from a1b2c3d
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
