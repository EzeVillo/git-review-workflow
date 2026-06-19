# git-review-workflow

Git commands to review a pull request branch locally as a single, staged diff —
make fixes inline, then split your changes onto a clean branch (or straight onto
the PR branch) ready to push.

Comandos de git para revisar la rama de un pull request localmente como un único
diff staged — hacer correcciones inline y luego separar tus cambios en una rama
limpia (o directo sobre la rama del PR) lista para subir.

**Version:** `0.0.1` (see [`VERSION`](VERSION)).

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

These commands plug into `git` — you run them as `git review-pr`,
`git finish-review`, and so on. Pick whichever method matches your setup. The
first options are the easiest and **set everything up for you**.

#### Easiest: a package manager (handles your PATH for you)

**macOS or Linux — [Homebrew](https://brew.sh):**

```sh
brew tap EzeVillo/git-review-workflow https://github.com/EzeVillo/git-review-workflow
brew install EzeVillo/git-review-workflow/git-review-workflow
```

**Windows — PowerShell** (no Scoop needed; you still need
[Git for Windows](https://gitforwindows.org), which provides the shell these
commands run in). Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.ps1 | iex
```

This installs the commands into `~\.local\bin` and adds that folder to your
user `PATH` automatically. Open a new terminal after it finishes.

**Windows — [Scoop](https://scoop.sh)** (alternative if you already have it):

```powershell
scoop bucket add git-review-workflow https://github.com/EzeVillo/git-review-workflow
scoop install git-review-workflow/git-review-workflow
```

With Homebrew, the PowerShell installer, or Scoop you can stop here — they put
the commands somewhere your terminal already looks, so `git review-pr` just
works. Everything below only matters if you install manually.

#### One-line install (Linux, macOS, WSL, Git Bash)

No package manager? This downloads the commands and installs them for you — you
don't even need to download the project first:

```sh
curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.sh | sh
```

It installs into the folder `~/.local/bin`. If that folder isn't on your `PATH`,
the installer will tell you — see [About your PATH](#about-your-path-command-not-found).

> **Git Bash on Windows — SSL error?** If you see a message like
> `schannel: next InitializeSecurityContext failed` or `revocation check`, your
> Git for Windows is using the Windows SSL backend. Fix it once with:
> ```sh
> git config --global http.sslBackend openssl
> ```
> Then re-run the installer.

#### From a downloaded copy

If you cloned or downloaded the project, open its folder in a terminal and run:

```sh
./install.sh
```

This installs all eight commands into `~/.local/bin` (change the location with
`PREFIX=/usr/local/bin ./install.sh`). Undo it any time with `./uninstall.sh`.

#### About your PATH ("command not found")

Your `PATH` is simply the list of folders your terminal looks inside when you
type a command. When you run `git review-pr`, your terminal goes through those
folders one by one until it finds a program with that name. If the folder where
these commands were installed isn't on the list, the terminal can't find them
and you'll see something like `git: 'review-pr' is not a git command` or
`command not found` — it's not broken, it just doesn't know where to look.

- **Homebrew and Scoop add their folder to your `PATH` automatically**, so if
  you installed that way there's nothing to do.
- The **one-line** and **manual** installs use the folder `~/.local/bin`, which
  is already on the `PATH` on most systems. If it isn't, the installer prints a
  short note, and you add it **once** by pasting one line into your shell's
  config file:

| If your terminal uses… | Add this line to the file… | The line to add |
| --- | --- | --- |
| **bash** | `~/.bashrc` | `export PATH="$HOME/.local/bin:$PATH"` |
| **zsh** (default on recent macOS) | `~/.zshrc` | `export PATH="$HOME/.local/bin:$PATH"` |
| **fish** | *(no file — just run this once)* | `fish_add_path ~/.local/bin` |

Not sure which one you use? Run `echo $0` — it prints `bash`, `zsh`, or similar.
After editing the file, **open a new terminal window** (or run `source ~/.bashrc`
/ `source ~/.zshrc`). To check it worked, run `git review-pr --help`: if you see
a usage message, you're all set.

#### Tab completion (optional)

Tab completion lets you press **Tab** and have your terminal finish a command
name or branch for you, so you don't have to type — or remember — them in full.
It's a convenience, not a requirement.

**If you installed with Homebrew, this is already set up for you** — you can skip
this. Otherwise, turn it on by telling your shell to load the matching file
every time it starts. Replace `/path/to/git-review-workflow` with the folder
where you downloaded the project.

- **bash** — add this line to the file `~/.bashrc`:

  ```sh
  source /path/to/git-review-workflow/completions/git-review-workflow.bash
  ```

- **zsh** (default on recent macOS) — add this line to the file `~/.zshrc`:

  ```sh
  source /path/to/git-review-workflow/completions/git-review-workflow.zsh
  ```

- **fish** — copy the file into fish's completions folder (no config line
  needed):

  ```sh
  cp /path/to/git-review-workflow/completions/git-review-workflow.fish \
      ~/.config/fish/completions/
  ```

Then open a new terminal. Now typing `git review-pr ` and pressing **Tab** will
offer your branch names.

### Commands

> **How to read the syntax:** `<x>` is **required**, `[x]` is **optional**, and
> `a | b` means **pick one, not both**. So in
> `git review-pr <branch> [base | --delta | --from <commit>]`, `branch` is
> required, and `base`, `--delta` and `--from` are three different ways to say
> *where the review starts* — you choose **at most one** of them (combining them
> is an error).

| Command | What it does |
| --- | --- |
| `git review-pr <branch> [base \| --delta \| --from <commit>] [--step]` | Fetch `origin`, then stage the PR diff on a new `review/<branch>` branch. |
| `git review-next` / `git review-prev` | Move a `--step` review to the next / previous commit. |
| `git review-status` | Show the state of the review on the current branch. |
| `git review-list` | List every `review/*` branch in progress (current one marked `*`). |
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
- **Merges of the base branch are excluded.** If the author merged the base
  (e.g. `develop`) into the PR, that merged-in content is left out of the review
  in every mode, so you only see the author's own changes — not the base. (In
  `--step` the base merge is simply skipped; in `--delta`/`--from` it is folded
  out of the staged diff using the base branch.)

**`git review-next` / `git review-prev`** move a `--step` review forward or
backward. Each move banks the current commit's edits and restores any edits you
had banked on the commit you move to, so you can walk back and forth without
losing work.

**`git review-status`** shows the current review: source PR, mode, and — in
`--step` mode — which commit you are on (`[k/N]`) and which steps have banked
edits. Useful for picking up where you left off.

**`git review-list`** shows *every* `review/*` branch in progress at once (with
its source PR, mode and step position), so you can see what you have open across
branches. The branch you are currently on is marked with a `*`.

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

- Git 2.23+ (uses `git switch`). Git 2.38+ is recommended: excluding base
  content that was merged into the PR uses `git merge-tree --write-tree`, and on
  older git that one step is skipped (the merged base content would then show in
  `--delta`/`--from`).
- A remote named `origin`.
- A POSIX shell. On Linux and macOS this is the default. On Windows the commands
  run under Git Bash or WSL, not in `cmd.exe` or PowerShell; under Git Bash,
  `install.sh` may copy the scripts instead of symlinking them unless symlinks
  are enabled (`MSYS=winsymlinks:nativestrict` and developer mode).

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

Estos comandos se enchufan a `git` — los usás como `git review-pr`,
`git finish-review`, etc. Elegí el método que mejor te quede. Las primeras
opciones son las más fáciles y **te configuran todo solas**.

#### Lo más fácil: un gestor de paquetes (te configura el PATH solo)

**macOS o Linux — [Homebrew](https://brew.sh):**

```sh
brew tap EzeVillo/git-review-workflow https://github.com/EzeVillo/git-review-workflow
brew install EzeVillo/git-review-workflow/git-review-workflow
```

**Windows — PowerShell** (sin necesidad de Scoop; sí necesitás
[Git for Windows](https://gitforwindows.org), que provee la shell donde corren
estos comandos). Abrí PowerShell y ejecutá:

```powershell
irm https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.ps1 | iex
```

Instala los comandos en `~\.local\bin` y agrega esa carpeta al `PATH` de tu
usuario automáticamente. Abrí una terminal nueva cuando termine.

**Windows — [Scoop](https://scoop.sh)** (alternativa si ya lo tenés instalado):

```powershell
scoop bucket add git-review-workflow https://github.com/EzeVillo/git-review-workflow
scoop install git-review-workflow/git-review-workflow
```

Con Homebrew, el instalador de PowerShell o Scoop podés parar acá — dejan los
comandos en un lugar donde tu terminal ya busca, así `git review-pr` funciona
sin más. Todo lo de abajo solo importa si instalás a mano.

#### Instalación en una línea (Linux, macOS, WSL, Git Bash)

¿Sin gestor de paquetes? Esto descarga los comandos y te los instala — ni
siquiera necesitás bajar el proyecto antes:

```sh
curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.sh | sh
```

Instala en la carpeta `~/.local/bin`. Si esa carpeta no está en tu `PATH`, el
instalador te avisa — mirá [Sobre tu PATH](#sobre-tu-path-command-not-found).

> **Git Bash en Windows — ¿error de SSL?** Si ves un mensaje como
> `schannel: next InitializeSecurityContext failed` o `revocation check`, tu Git
> for Windows está usando el backend SSL de Windows. Arreglalo con:
> ```sh
> git config --global http.sslBackend openssl
> ```
> Después volvé a correr el instalador.

#### Desde una copia descargada

Si clonaste o descargaste el proyecto, abrí su carpeta en una terminal y corré:

```sh
./install.sh
```

Instala los ocho comandos en `~/.local/bin` (cambiá la ubicación con
`PREFIX=/usr/local/bin ./install.sh`). Lo deshacés cuando quieras con
`./uninstall.sh`.

#### Sobre tu PATH ("command not found")

Tu `PATH` es, simplemente, la lista de carpetas donde tu terminal busca cuando
escribís un comando. Cuando corrés `git review-pr`, la terminal recorre esas
carpetas una por una hasta encontrar un programa con ese nombre. Si la carpeta
donde se instalaron estos comandos no está en la lista, la terminal no los
encuentra y vas a ver algo como `git: 'review-pr' is not a git command` o
`command not found` — no está roto, solo no sabe dónde mirar.

- **Homebrew y Scoop agregan su carpeta al `PATH` automáticamente**, así que si
  instalaste por ahí no tenés que hacer nada.
- La instalación **en una línea** y la **manual** usan la carpeta `~/.local/bin`,
  que en la mayoría de los sistemas ya está en el `PATH`. Si no lo está, el
  instalador te deja un aviso y lo agregás **una sola vez** pegando una línea en
  el archivo de configuración de tu shell:

| Si tu terminal usa… | Agregá esta línea al archivo… | La línea a agregar |
| --- | --- | --- |
| **bash** | `~/.bashrc` | `export PATH="$HOME/.local/bin:$PATH"` |
| **zsh** (default en macOS reciente) | `~/.zshrc` | `export PATH="$HOME/.local/bin:$PATH"` |
| **fish** | *(sin archivo — corré esto una vez)* | `fish_add_path ~/.local/bin` |

¿No sabés cuál usás? Corré `echo $0` — te dice `bash`, `zsh`, o similar. Después
de editar el archivo, **abrí una terminal nueva** (o corré `source ~/.bashrc` /
`source ~/.zshrc`). Para comprobar que funcionó, corré `git review-pr --help`: si
ves un mensaje de uso, ya está.

#### Autocompletado (opcional)

El autocompletado te deja apretar **Tab** para que la terminal complete sola un
nombre de comando o de rama, así no tenés que escribirlos —ni acordártelos—
enteros. Es una comodidad, no un requisito.

**Si instalaste con Homebrew, ya viene configurado** — podés saltearlo. Si no,
lo activás diciéndole a tu shell que cargue el archivo correspondiente cada vez
que arranca. Reemplazá `/ruta/a/git-review-workflow` por la carpeta donde
descargaste el proyecto.

- **bash** — agregá esta línea al archivo `~/.bashrc`:

  ```sh
  source /ruta/a/git-review-workflow/completions/git-review-workflow.bash
  ```

- **zsh** (default en macOS reciente) — agregá esta línea al archivo `~/.zshrc`:

  ```sh
  source /ruta/a/git-review-workflow/completions/git-review-workflow.zsh
  ```

- **fish** — copiá el archivo a la carpeta de completions de fish (sin línea de
  configuración):

  ```sh
  cp /ruta/a/git-review-workflow/completions/git-review-workflow.fish \
      ~/.config/fish/completions/
  ```

Después abrí una terminal nueva. Ahora, escribiendo `git review-pr ` y apretando
**Tab**, te ofrece los nombres de tus ramas.

### Comandos

> **Cómo leer la sintaxis:** `<x>` es **obligatorio**, `[x]` es **opcional**, y
> `a | b` significa **elegí uno, no los dos**. Así, en
> `git review-pr <rama> [base | --delta | --from <commit>]`, `rama` es
> obligatoria, y `base`, `--delta` y `--from` son tres formas distintas de decir
> *desde dónde empieza la review* — elegís **a lo sumo una** (combinarlas es un
> error).

| Comando | Qué hace |
| --- | --- |
| `git review-pr <rama> [base \| --delta \| --from <commit>] [--step]` | Hace fetch de `origin` y deja el diff del PR staged en una nueva rama `review/<rama>`. |
| `git review-next` / `git review-prev` | Mueve una review `--step` al commit siguiente / anterior. |
| `git review-status` | Muestra el estado de la review en la rama actual. |
| `git review-list` | Lista todas las ramas `review/*` en curso (la actual marcada con `*`). |
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
- **Los merges de la rama base se excluyen.** Si el autor mergeó la base (ej.
  `develop`) dentro del PR, ese contenido mergeado queda afuera de la review en
  todos los modos, así ves solo los cambios del autor — no los de la base. (En
  `--step` el merge de la base se saltea; en `--delta`/`--from` se descuenta del
  diff staged usando la rama base.)

**`git review-next` / `git review-prev`** mueven una review `--step` para
adelante o para atrás. Cada movimiento banca las ediciones del commit actual y
restaura las que tenías bancadas en el commit al que vas, así podés ir y venir
sin perder trabajo.

**`git review-status`** muestra la review actual: PR de origen, modo, y — en modo
`--step` — en qué commit estás (`[k/N]`) y qué pasos tienen ediciones bancadas.
Útil para retomar donde dejaste.

**`git review-list`** muestra *todas* las ramas `review/*` en curso a la vez (con
su PR de origen, modo y posición de paso), así ves qué tenés abierto entre
ramas. La rama en la que estás parado se marca con un `*`.

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

- Git 2.23+ (usa `git switch`). Se recomienda Git 2.38+: excluir el contenido
  de la base mergeado dentro del PR usa `git merge-tree --write-tree`, y en git
  más viejo ese paso se saltea (el contenido de la base mergeado aparecería en
  `--delta`/`--from`).
- Un remoto llamado `origin`.
- Una shell POSIX. En Linux y macOS es la de por defecto. En Windows los
  comandos corren bajo Git Bash o WSL, no en `cmd.exe` ni PowerShell; bajo Git
  Bash, `install.sh` puede copiar los scripts en vez de hacer symlink salvo que
  los symlinks estén habilitados (`MSYS=winsymlinks:nativestrict` y modo
  desarrollador).

---

## Development

Run the checks locally:

```sh
shellcheck bin/* install.sh uninstall.sh web-install.sh
bats tests/
```

CI runs both on every push and pull request (see `.github/workflows/ci.yml`).

### Releasing

Releases are cut by pushing a `v*` tag:

```sh
# bump the snapshot to the release version first
printf '0.0.1\n' >VERSION
git commit -am "Release 0.0.1"
git tag v0.0.1
git push origin HEAD --tags
```

The release workflow (`.github/workflows/release.yml`) then:

- creates a GitHub Release for the tag with auto-generated notes, and
- pins the Homebrew formula (`url`, `sha256`, `version`) to the tag on the
  default branch, so `brew install` (without `--HEAD`) installs that version.
