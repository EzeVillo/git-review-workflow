# git-review-workflow

> Revisá la rama de un pull request localmente como un único diff staged — hacé
> correcciones inline y luego separá tus cambios en una rama limpia (o directo
> sobre la rama del PR) lista para subir.

[![CI](https://github.com/EzeVillo/git-review-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/EzeVillo/git-review-workflow/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/tag/EzeVillo/git-review-workflow?label=release&sort=semver)](https://github.com/EzeVillo/git-review-workflow/releases)

[English](README.md) · **Español**

---

Cuando revisás un PR normalmente querés ver **todos** sus cambios de una y
toquetearlos. `git review-pr` crea una rama `review/<rama>` cuyo working tree
tiene el tip del PR, pero con el `HEAD` parado en el merge-base con tu rama base.
El resultado: todo el PR aparece como **cambios staged sin commitear**. Lo leés,
lo editás, lo corrés — y cuando terminás, `git finish-review` extrae tus
ediciones a una rama separada `review-fixes/<rama>` (o directo sobre la rama del
PR).

## Inicio rápido

```sh
# 1. Instalar (macOS/Linux con Homebrew — ver Instalación para otros métodos)
brew tap EzeVillo/git-review-workflow https://github.com/EzeVillo/git-review-workflow
brew install EzeVillo/git-review-workflow/git-review-workflow

# 2. Decirle dónde se integran los PRs, una vez por repo
git config reviewworkflow.base develop

# 3. Revisar la rama de un PR como un único diff staged
git review-pr feature/login
git status                      # inspeccionar todo de una
# ...editar archivos, dejar fixes, correr tests...
git finish-review               # extraer tus ediciones a review-fixes/feature/login
```

## Instalación

Estos comandos se enchufan a `git` — los usás como `git review-pr`,
`git finish-review`, etc. Elegí el método que mejor te quede. Las opciones por
gestor de paquetes son las más fáciles y **te configuran el `PATH` solas**.

### Homebrew (macOS / Linux)

```sh
brew tap EzeVillo/git-review-workflow https://github.com/EzeVillo/git-review-workflow
brew install EzeVillo/git-review-workflow/git-review-workflow
```

El autocompletado queda configurado automáticamente. Para actualizar a la última
versión: `brew upgrade git-review-workflow`.

### Windows (PowerShell)

Necesitás [Git for Windows](https://gitforwindows.org), que provee la shell
donde corren estos comandos. Abrí PowerShell y ejecutá:

```powershell
irm https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.ps1 | iex
```

Instala los comandos en `~\.local\bin` y agrega esa carpeta al `PATH` de tu
usuario automáticamente. Abrí una terminal nueva cuando termine. Volvé a correrlo
para actualizar; para desinstalar:

```powershell
irm https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-uninstall.ps1 | iex
```

### Instalación en una línea (Linux, macOS, WSL, Git Bash)

¿Sin gestor de paquetes? Esto descarga los comandos y los instala en
`~/.local/bin` — ni siquiera necesitás clonar el proyecto antes:

```sh
curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.sh | sh
```

Volvé a correrlo para actualizar (siempre instala la última versión). Para
desinstalar (pasale el mismo `PREFIX` si lo cambiaste):

```sh
curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-uninstall.sh | sh
```

<details>
<summary>Desde una copia descargada</summary>

Si clonaste o descargaste el proyecto, abrí su carpeta en una terminal y corré:

```sh
./install.sh
```

Instala los ocho comandos en `~/.local/bin` (cambiá la ubicación con
`PREFIX=/usr/local/bin ./install.sh`). Lo deshacés cuando quieras con
`./uninstall.sh`. Para actualizar, simplemente hacé `git pull` dentro del repo —
los symlinks toman los cambios automáticamente.
</details>

<details>
<summary>"command not found" — agregar <code>~/.local/bin</code> a tu PATH</summary>

Tu `PATH` es la lista de carpetas donde tu terminal busca cuando escribís un
comando. Homebrew y el instalador de PowerShell agregan su carpeta por vos. La
instalación en una línea y la manual usan `~/.local/bin`, que en la mayoría de
los sistemas ya está en el `PATH`. Si no lo está, el instalador te deja un aviso
— agregalo **una sola vez** pegando una línea en el archivo de config de tu
shell:

| Si tu terminal usa…                 | Agregá esta línea al archivo…        | La línea a agregar                     |
|-------------------------------------|--------------------------------------|----------------------------------------|
| **bash**                            | `~/.bashrc`                          | `export PATH="$HOME/.local/bin:$PATH"` |
| **zsh** (default en macOS reciente) | `~/.zshrc`                           | `export PATH="$HOME/.local/bin:$PATH"` |
| **fish**                            | *(sin archivo — corré esto una vez)* | `fish_add_path ~/.local/bin`           |

¿No sabés cuál usás? Corré `echo $0`. Después de editar el archivo, **abrí una
terminal nueva** (o hacé `source` del archivo). Corré `git review-pr --help` para
confirmar.
</details>

<details>
<summary>Autocompletado (instalaciones manuales)</summary>

Homebrew te lo configura. Si no, decile a tu shell que cargue el archivo
correspondiente al arrancar. Reemplazá `/ruta/a/git-review-workflow` por la
carpeta donde descargaste el proyecto.

```sh
# bash — en ~/.bashrc
source /ruta/a/git-review-workflow/completions/git-review-workflow.bash

# zsh — en ~/.zshrc
source /ruta/a/git-review-workflow/completions/git-review-workflow.zsh

# fish — copiá el archivo a la carpeta de completions de fish (sin línea de config)
cp /ruta/a/git-review-workflow/completions/git-review-workflow.fish \
    ~/.config/fish/completions/
```

Después abrí una terminal nueva. Ahora, escribiendo `git review-pr ` y apretando
**Tab**, te ofrece los nombres de tus ramas.
</details>

<details>
<summary>Git Bash en Windows — ¿error de SSL al instalar?</summary>

Si ves `schannel: next InitializeSecurityContext failed` o un mensaje de
`revocation check`, tu Git for Windows está usando el backend SSL de Windows.
Arreglalo una vez y volvé a correr el instalador:

```sh
git config --global http.sslBackend openssl
```

</details>

## Comandos

> **Cómo leer la sintaxis:** `<x>` es **obligatorio**, `[x]` es **opcional**, y
> `a | b` significa **elegí uno, no los dos**.

| Comando                                                              | Qué hace                                                                                    |
|----------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| `git review [--help \| --version]`                                   | Lista todos los comandos o imprime la versión instalada.                                    |
| `git review-pr <rama> [base \| --delta \| --from <commit>] [--step]` | Hace fetch de `origin` y deja el diff del PR staged en una nueva rama `review/<rama>`.      |
| `git review-next` / `git review-prev`                                | Mueve una review `--step` al commit siguiente / anterior.                                   |
| `git review-status`                                                  | Muestra el estado de la review en la rama actual.                                           |
| `git review-list`                                                    | Lista todas las ramas `review/*` en curso (la actual marcada con `*`).                      |
| `git finish-review [--onto-source] [--push] [--resume]`              | Desde una rama `review/*`, extrae tus ediciones a `review-fixes/<rama>` (o la rama del PR). |
| `git review-abort`                                                   | Cancela la review actual y vuelve a donde empezaste.                                        |
| `git clean-review [rama] [--forget]`                                 | Borra las ramas `review/*` y `review-fixes/*` de `<rama>`, o todas.                         |

### `git review-pr`

Tiene dos ejes independientes — **rango** (desde dónde empieza) y **layout**
(`--step` o no), que se combinan libremente.

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
- `--step` — revisar el rango **de a un commit por vez** (combinalo con `--delta`
  o `--from` para recorrer solo esos commits). Arrancás en el primer commit
  después del merge-base y el comando imprime el mensaje del autor. Editás y
  corrés `git review-next` para bancar tus cambios y pasar al siguiente commit
  con el árbol limpio. Cuando se acaban los commits, corrés `git finish-review` y
  todas tus ediciones bancadas se re-aplican sobre el tip del PR — igual que en
  una review completa.
- Siempre actualiza desde `origin` primero y **falla** si no puede. La revisión
  se arma desde `origin/<rama>`, nunca desde una copia local vieja.
- No corre si tenés cambios locales — arrancá desde una rama limpia.
- **Los merges de la rama base se excluyen.** Si el autor mergeó la base (ej.
  `develop`) dentro del PR, ese contenido mergeado queda afuera de la review en
  todos los modos, así ves solo los cambios del autor.

### `git review-next` / `git review-prev`

Mueven una review `--step` para adelante o para atrás. Cada movimiento banca las
ediciones del commit actual y restaura las que tenías bancadas en el commit al
que vas, así podés ir y venir sin perder trabajo.

### `git review-status`

Muestra la review actual: PR de origen, modo, y — en modo `--step` — en qué
commit estás (`[k/N]`) y qué pasos tienen ediciones bancadas.

### `git review-list`

Muestra *todas* las ramas `review/*` en curso a la vez (con su PR de origen, modo
y posición de paso). La rama en la que estás parado se marca con un `*`.

### `git finish-review`

- Por defecto — crea `review-fixes/<rama>` sobre el tip del PR con tus ediciones
  staged, para que las revises y commitees vos.
- `--onto-source` — agrega tus ediciones como un commit sobre la rama del PR
  misma.
- `--push` — pushea la rama resultante a `origin`. Con `--onto-source` se niega a
  pushear si `origin/<rama>` se movió desde tu review.
- `--resume` — en modo `--step`, si las ediciones bancadas chocan con el tip del
  PR, el replay deja marcadores de conflicto y se detiene. Resolvélos en el árbol
  y corré `git finish-review --resume` (con los mismos flags) para seguir.

### `git review-abort`

Cancela la review actual en un paso: te devuelve a la rama desde la que empezaste
y borra la rama `review/<rama>` y sus ediciones bancadas. Como la review se
canceló (no se completó), vuelve el marcador de `--delta` a tu última review
real, así un `--delta` posterior no se saltea commits que nunca revisaste.

### `git clean-review`

- Sin `<rama>`, borra todas las ramas `review/*` y `review-fixes/*`.
- Nunca borra la rama en la que estás parado.
- `--forget` además descarta el tip de la última review (lo que desactiva
  `--delta` para esa rama).

## Configurar la rama base

La rama base es donde se integran los PRs (`develop`, `main`, `master`, …) y
varía por equipo, así que no hay default — configurala una vez por repositorio:

```sh
git config reviewworkflow.base develop
```

Orden de resolución: argumento posicional `base` → `reviewworkflow.base`. Si no
hay ninguno, una review completa falla y te pide que la configures.

## Flujo típico

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

## Requisitos

- Git 2.23+ (usa `git switch`). Se recomienda Git 2.38+: excluir el contenido de
  la base mergeado dentro del PR usa `git merge-tree --write-tree`, y en git más
  viejo ese paso se saltea (el contenido de la base mergeado aparecería en
  `--delta`/`--from`).
- Un remoto llamado `origin`.
- Una shell POSIX. En Linux y macOS es la de por defecto. En Windows los comandos
  corren bajo Git Bash o WSL, no en `cmd.exe` ni PowerShell.

## Contribuir

Reportes de bugs, fixes e ideas son bienvenidos. Mirá
[CONTRIBUTING.md](CONTRIBUTING.md) para cómo correr los tests y el proceso de
release.

## Licencia

[MIT](LICENSE) © EzeVillo
