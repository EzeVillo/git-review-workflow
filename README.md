# git-review-workflow

Git aliases to review a pull request branch locally as a single, staged diff —
make fixes inline, then split your changes onto a clean branch ready to push.

Aliases de git para revisar la rama de un pull request localmente como un único
diff staged — hacer correcciones inline y luego separar tus cambios en una rama
limpia lista para subir.

---

## English

### What it does

When you review a PR, you usually want to see **all** of its changes at once and
poke at them. These aliases create a `review/<branch>` branch whose working tree
holds the PR tip, but whose `HEAD` sits at the merge-base with your base branch.
The result: the entire PR shows up as **staged, uncommitted changes**. You read
it, edit it, run it — and when you are done, your edits are extracted onto a
separate `review-fixes/<branch>` branch on top of the original PR tip.

### Install

```sh
./install.sh
```

This registers three global aliases. Remove them with `./uninstall.sh`.

### Commands

| Command | What it does |
| --- | --- |
| `git review-pr <branch> [base]` | Fetch `origin`, then stage the whole PR diff on a new `review/<branch>` branch. `base` defaults to `develop`. |
| `git finish-review` | From a `review/*` branch, extract your edits onto a new `review-fixes/<branch>` branch based on the PR tip. |
| `git clean-review [branch]` | Delete the `review/*` and `review-fixes/*` branches for `<branch>`, or all of them if no argument is given. |

### Typical workflow

```sh
# 1. Start reviewing PR branch "feature/login" against develop
git review-pr feature/login

# 2. Inspect the staged diff, edit files, leave fixes, run tests...
git status
git diff --cached

# 3. Extract your fixes onto review-fixes/feature/login
git finish-review

# 4. Review and commit your fixes, then push if you want
git diff --cached
git commit -m "address review comments"

# 5. Clean up the temporary review branches
git clean-review feature/login
```

### Notes

- `review-pr` **always updates from `origin` first** and fails if it cannot. The
  review is built from `origin/<branch>`, never a stale local copy.
- `review-pr` refuses to run if you have local changes — start from a clean
  branch (for example `develop`).
- `finish-review` records the exact PR tip it reviewed, so your fixes always
  apply cleanly even if the PR moved on `origin` in the meantime.
- `clean-review` will not delete the branch you are currently on; switch away
  first.

### Requirements

- Git 2.23+ (uses `git switch`).
- A remote named `origin`.

---

## Español

### Qué hace

Cuando revisás un PR normalmente querés ver **todos** sus cambios de una y
toquetearlos. Estos aliases crean una rama `review/<rama>` cuyo working tree
tiene el tip del PR, pero con el `HEAD` parado en el merge-base con tu rama base.
El resultado: todo el PR aparece como **cambios staged sin commitear**. Lo leés,
lo editás, lo corrés — y cuando terminás, tus ediciones se extraen a una rama
separada `review-fixes/<rama>` sobre el tip original del PR.

### Instalación

```sh
./install.sh
```

Registra tres aliases globales. Para quitarlos: `./uninstall.sh`.

### Comandos

| Comando | Qué hace |
| --- | --- |
| `git review-pr <rama> [base]` | Hace fetch de `origin` y deja todo el diff del PR staged en una nueva rama `review/<rama>`. `base` por defecto es `develop`. |
| `git finish-review` | Desde una rama `review/*`, extrae tus ediciones a una nueva rama `review-fixes/<rama>` basada en el tip del PR. |
| `git clean-review [rama]` | Borra las ramas `review/*` y `review-fixes/*` de `<rama>`, o todas si no pasás argumento. |

### Flujo típico

```sh
# 1. Empezar a revisar la rama del PR "feature/login" contra develop
git review-pr feature/login

# 2. Inspeccionar el diff staged, editar archivos, dejar fixes, correr tests...
git status
git diff --cached

# 3. Extraer tus fixes a review-fixes/feature/login
git finish-review

# 4. Revisar y commitear tus fixes, después subir si querés
git diff --cached
git commit -m "address review comments"

# 5. Limpiar las ramas temporales de review
git clean-review feature/login
```

### Notas

- `review-pr` **siempre actualiza desde `origin` primero** y falla si no puede.
  La revisión se arma desde `origin/<rama>`, nunca desde una copia local vieja.
- `review-pr` no corre si tenés cambios locales — arrancá desde una rama limpia
  (por ejemplo `develop`).
- `finish-review` guarda el tip exacto del PR que revisaste, así tus fixes
  siempre aplican limpio aunque el PR se haya movido en `origin`.
- `clean-review` no borra la rama en la que estás parado; cambiate de rama
  primero.

### Requisitos

- Git 2.23+ (usa `git switch`).
- Un remoto llamado `origin`.
