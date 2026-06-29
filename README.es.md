# git-review-workflow

> Revisá un pull request **editándolo y corriéndolo**, no solo leyéndolo. Todo el
> PR aparece en tu working tree como un único diff staged; después tus
> correcciones se extraen a una rama limpia automáticamente. Re-revisá solo lo
> que cambió.

[![CI](https://github.com/EzeVillo/git-review-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/EzeVillo/git-review-workflow/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/tag/EzeVillo/git-review-workflow?label=release&sort=semver)](https://github.com/EzeVillo/git-review-workflow/releases)

[English](README.md) · **Español**

---

Revisar en una web está bien para dejar comentarios, pero es malo para realmente
*correr* y *editar* el código. `git review start` pone todo el PR en tu working
tree como **cambios staged sin commitear**: crea una rama `review/<rama>` cuyo
working tree tiene el tip del PR, pero con el `HEAD` parado en el merge-base con
tu rama base. Como es simplemente tu working tree, abrís todo el PR en cualquier
editor — leés el diff, lo editás inline, corrés los tests — y cuando terminás,
`git review finish` extrae *tus* ediciones a una rama separada `review-fixes/<rama>`
(o directo sobre la rama del PR), manteniéndolas limpiamente aparte del trabajo
del autor. Re-revisá solo los commits nuevos tras una actualización con `--delta`.

> **Todos los comandos viven bajo `git review <verbo>`** — `git review start`,
> `git review finish`, `git review status`, etc., como `git bisect` y `git stash`
> agrupan sus verbos.

## ¿Por qué no usar la vista de PR de tu IDE?

La mayoría de las herramientas te dejan *ver* un PR. Lo que esto resuelve es
*actuar* sobre uno — editarlo y correrlo como cambios normales del working tree y
después devolver tus correcciones sin stash ni cherry-pick manuales.

|                                  |     Ver el PR      | Editar y correr como working tree | Extraer tus fixes automáticamente | Re-review incremental (`--delta`) | Independiente del editor |
|----------------------------------|:------------------:|:---------------------------------:|:---------------------------------:|:---------------------------------:|:------------------------:|
| **git-review-workflow**          |         ✅          |                 ✅                 |                 ✅                 |                 ✅                 |            ✅             |
| `gh pr checkout` / `glab`        | ⚠️ checkout pelado |                 ✅                 |                 ❌                 |                 ❌                 |            ✅             |
| JetBrains *Review Pull Request*  |         ✅          |         ⚠️ solo en el IDE         |                 ❌                 |                 ❌                 |            ❌             |
| Extensión *GitHub PR* de VS Code |         ✅          |         ⚠️ solo en el IDE         |                 ❌                 |                 ❌                 |            ❌             |
| Web de GitHub / GitLab           |         ✅          |                 ❌                 |                 ❌                 |            ⚠️ parcial             |            ✅             |

Como el PR son simplemente cambios staged, cualquier cosa que lea un diff de Git
lo ve entero — incluidos agentes de IA como Claude Code o Codex que no tienen una
función propia para revisar PRs. Apuntás uno al diff staged y puede revisar o
corregir todo el PR ahí mismo.

Y para las cosas chicas — un rename, un typo, un nombre de variable más claro —
arreglarlo vos mismo es más rápido y menos burocrático que dejar un comentario y
esperar la ida y vuelta, sobre todo cuando ya estás mirando el PR en tu editor.
Como tus ediciones se extraen automáticamente, el arreglo te cuesta más o menos
lo mismo que habría costado el comentario. O le pasás el diff staged a un agente
y que haga el cambio por vos.

Si mayormente *comentás*, el panel nativo de PR de tu IDE alcanza. Si revisás
editando y corriendo el código — en cualquier editor o agente — esto es lo que
falta.

## Inicio rápido

```sh
# 1. Instalar (necesita Node.js; ver Instalación para Homebrew y una opción sin Node)
npm install -g git-review-workflow

# 2. Decirle dónde se integran los PRs, una vez por repo
git config reviewworkflow.base develop

# 3. Dejar la rama de un PR staged como un único diff y abrir el repo en tu IDE
git review start feature/login
# ...leer y editar el diff staged en tu editor, correr tests...
git review finish               # extraer tus ediciones a review-fixes/feature/login
```

¿Preferís Homebrew, un instalador nativo de Windows (PowerShell), o una
instalación que no necesite Node? Mirá
[Instalación](#instalación). Para el flujo completo — re-revisar actualizaciones,
recorrer un PR commit por commit, limpieza — mirá [Flujo típico](#flujo-típico).

## Instalación

Estos comandos se enchufan a `git` como un único subcomando — los usás como
`git review start`, `git review finish`, etc. Elegí el método que mejor te quede.
Las opciones por gestor de paquetes son las más fáciles y **te configuran el
`PATH` solas**.

### npm (recomendado)

Si tenés [Node.js](https://nodejs.org), esta es la instalación de un solo comando.
Te pone `git review` en el `PATH` y anda en Linux, macOS y Windows (en Windows los
comandos igual corren bajo Git Bash):

```sh
npm install -g git-review-workflow
```

Actualizá con `npm install -g git-review-workflow@latest`; desinstalá con
`npm uninstall -g git-review-workflow`. El autocompletado se configura igual que
en las otras instalaciones que no son Homebrew — mirá la nota más abajo.

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

Instala el comando en `~\.local\bin` y agrega esa carpeta al `PATH` de tu usuario
automáticamente. Abrí una terminal nueva cuando termine. Volvé a correrlo para
actualizar; para desinstalar:

```powershell
irm https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-uninstall.ps1 | iex
```

(Si tenés Node, `npm install -g git-review-workflow` también anda en Windows — los
comandos igual corren bajo Git Bash en ambos casos.)

### Instalación en una línea (Linux, macOS, WSL, Git Bash)

¿Sin gestor de paquetes? Esto descarga el comando y lo instala en `~/.local/bin`
— ni siquiera necesitás clonar el proyecto antes:

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

Instala el dispatcher `git review` en `~/.local/bin` (cambiá la ubicación con
`PREFIX=/usr/local/bin ./install.sh`). Los verbos viajan al lado suyo como
helpers privados, no como comandos sueltos en tu `PATH`. Lo deshacés cuando
quieras con `./uninstall.sh`. Para actualizar, simplemente hacé `git pull` dentro
del repo — el symlink toma los cambios automáticamente.
</details>

<details>
<summary>"command not found" — agregar <code>~/.local/bin</code> a tu PATH</summary>

Tu `PATH` es la lista de carpetas donde tu terminal busca cuando escribís un
comando. Homebrew, npm y el instalador de PowerShell agregan su carpeta por vos. La
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
terminal nueva** (o hacé `source` del archivo). Corré `git review -h` para
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

Después abrí una terminal nueva. Ahora, escribiendo `git review ` y apretando
**Tab**, te ofrece los verbos; `git review start ` te ofrece los nombres de tus
ramas.
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

Cada comando es un verbo bajo `git review`. Corré `git review -h` para ver la
lista, o `git review <verbo> -h` para el detalle de un verbo.

| Comando                                                                                                | Qué hace                                                                                                                                                                            |
|--------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `git review [-h \| --version]`                                                                         | Lista todos los verbos o imprime la versión instalada.                                                                                                                              |
| `git review start [<rama>] [<base> \| --base <base> \| --delta \| --from <commit>] [--step] [--local]` | Hace fetch de `origin` y deja el diff del PR staged en una nueva rama `review/<rama>` (omití `<rama>` para revisar la rama actual; `--local` revisa ramas locales sin hacer fetch). |
| `git review compare <a> <b> [--step]`                                                                  | Deja staged el diff entre dos commit-ish (tags, commits, ramas) en modo lectura, para leerlo o recorrerlo. `git review finish` se niega — no hay a dónde escribir.                  |
| `git review next` / `git review prev`                                                                  | Mueve una review `--step` al commit siguiente / anterior.                                                                                                                           |
| `git review status`                                                                                    | Muestra el estado de la review en la rama actual.                                                                                                                                   |
| `git review list`                                                                                      | Lista todas las reviews en curso y las guardadas (la rama actual marcada con `*`).                                                                                                  |
| `git review save`                                                                                      | Pausa la review actual como `review-saved/<rama>` y vuelve a donde empezaste.                                                                                                       |
| `git review continue [rama]`                                                                           | Retoma una review guardada con `git review save`.                                                                                                                                   |
| `git review finish [--onto-source] [--resume \| --abort [--force]]`                                    | Desde una rama `review/*`, extrae tus ediciones a `review-fixes/<rama>` (o la rama del PR); `--abort` deshace el último finish.                                                     |
| `git review preview [--stat]`                                                                          | Muestra las ediciones que hiciste hasta ahora — el diff que `finish` extraería — sin commitear ni cambiar de rama.                                                                  |
| `git review abort`                                                                                     | Cancela la review actual y vuelve a donde empezaste.                                                                                                                                |
| `git review clean [rama]`                                                                              | Borra las ramas `review/*` y `review-fixes/*` de `<rama>`, o todas.                                                                                                                 |
| `git review forget --delta (<rama> \| --all \| --stale [--dry-run])`                                   | Descarta el marcador de `--delta` de una rama, de todas, o solo de las obsoletas.                                                                                                   |
| `git review forget --saved (<rama> \| --all) [--dry-run]`                                              | Descarta una review guardada con `git review save`.                                                                                                                                 |

### `git review start`

Tiene dos ejes independientes — **rango** (desde dónde empieza) y **layout**
(`--step` o no), que se combinan libremente.

- `<rama>` — la rama a revisar. **Omitila para revisar la rama que tenés
  checkouteada** — el default propio de git (como `push`, `status`, `log`). Solo
  resuelve el nombre; el modo lo siguen eligiendo los flags, así que combiná la
  rama omitida con `--local` para revisar tu trabajo local. Sin `--local` revisa
  `origin/<rama>` — si difiere de tu rama checkouteada te avisa, porque estarías
  revisando un snapshot distinto al que tenés. Con la rama omitida, falla con HEAD
  detached o estando sobre una rama `review/*`.
- `base` — commit-ish contra el que comparar: una rama, un **tag** o un commit.
  Tomada de `reviewworkflow.base` (ver abajo); el argumento posicional la
  sobreescribe. **Obligatoria para una review completa** — no hay default, así que
  una review completa sin base configurada falla y te pide que la configures. No se
  usa con `--delta` ni `--from`, que ya traen su propio punto de inicio — pasar una
  base explícita junto con ellos es un error (una base que viene de config
  simplemente se ignora).
- `--base <base>` — la base contra la que comparar, como flag. Usala para pasar
  una base dejando que `<rama>` defaultee a la rama actual — ej.
  `git review start --base develop` revisa la rama en la que estás contra
  `develop` (el posicional solitario siempre se toma como `<rama>`, así que el
  flag es la forma de llegar a la base sin nombrar la rama). No se puede combinar
  con una base posicional.
- `--delta` — revisar solo los commits agregados **desde tu última review** de
  esta rama, en vez de todo el PR. Ideal para re-revisar un PR actualizado. El
  tip registrado sobrevive a `git review clean`, así que funciona aunque hayas
  borrado las ramas de review; para descartarlo usá `git review forget --delta`.
- `--from <commit>` — revisar solo los commits **después de `<commit>`**. Útil
  cuando no hay review registrada para usar `--delta`, o para elegir un punto de
  inicio exacto. Mutuamente excluyente con `--delta`.
- `--step` — revisar el rango **de a un commit por vez** (combinalo con `--delta`
  o `--from` para recorrer solo esos commits). Arrancás en el primer commit
  después del merge-base y el comando imprime el mensaje del autor. Editás y
  corrés `git review next` para bancar tus cambios y pasar al siguiente commit
  con el árbol limpio. Cuando se acaban los commits, corrés `git review finish` y
  todas tus ediciones bancadas se re-aplican sobre el tip del PR — igual que en
  una review completa.
- `--local` — revisar tus ramas **locales** directamente, sin hacer fetch. La
  review se arma desde tu `<rama>` local y se compara contra tu base local, así
  que funciona offline y te deja revisar tu propio trabajo antes de pushear.
  Mantiene su propio marcador de `--delta`, separado del remoto, así una review
  local y una remota de la misma rama nunca se pisan el progreso.
- Siempre actualiza desde `origin` primero y **falla** si no puede (salvo con
  `--local`). La revisión se arma desde `origin/<rama>`, nunca desde una copia
  local vieja. Si una rama local con el mismo nombre apunta a otro lado, te avisa:
  la review refleja el remoto, no tu checkout, y un `git review finish
  --onto-source` posterior se va a negar hasta que tu rama local coincida.
- No corre si tenés cambios locales — arrancá desde una rama limpia.
- **Los merges de la rama base se excluyen.** Si el autor mergeó la base (ej.
  `develop`) dentro del PR, ese contenido mergeado queda afuera de la review en
  todos los modos, así ves solo los cambios del autor.
- `--` termina el parseo de opciones, la convención habitual de git: todo lo que
  va después se trata como argumento posicional, así una rama cuyo nombre empieza
  con `-` igual se puede revisar (ej. `git review start -- --weird develop`).

### `git review compare`

Deja staged el diff entre dos commit-ish — dos tags, dos commits, dos ramas —
como una review de solo lectura, para leerlo inline o recorrerlo commit por
commit con la misma UX que una review real, sin `git diff | less`.

```sh
git review compare v1.0 v2.0          # dejar staged el diff entre dos releases
git review compare v1.0 v2.0 --step   # ...y recorrerlo commit por commit
```

- Compara `<a>..<b>`: `<a>` es el límite inferior (donde empieza la review),
  `<b>` el tip cuyo contenido llena el working tree. Ambos se resuelven a commits,
  así que andan tags y SHAs crudos, no solo nombres de rama.
- Es **de solo lectura por diseño**. Toda la mitad editar→finish del workflow
  necesita una rama escribible a la cual devolver, y un tag o un commit no lo es —
  así que `git review finish` sobre un compare se niega explícitamente ("esta
  review es de solo lectura, no hay a dónde escribir"). Usá `git review abort`
  para terminarlo.
- `--step` lo recorre de a un commit, igual que `git review start --step`, con
  `git review next` / `git review prev`.

### `git review next` / `git review prev`

Mueven una review `--step` para adelante o para atrás. Cada movimiento banca las
ediciones del commit actual y restaura las que tenías bancadas en el commit al
que vas, así podés ir y venir sin perder trabajo.

### `git review status`

Muestra la review actual: PR de origen, modo, y — en modo `--step` — en qué
commit estás (`[k/N]`) y qué pasos tienen ediciones bancadas.

### `git review list`

Muestra *todas* las ramas `review/*` en curso a la vez (con su PR de origen, modo
y posición de paso). Las reviews pausadas con `git review save` también aparecen,
bajo `saved`. La rama en la que estás parado se marca con un `*`.

### `git review save` / `git review continue`

`git review save` te deja apartar una review y retomarla después. Convierte la
`review/<rama>` actual en `review-saved/<rama>` y te devuelve a la rama desde la
que empezaste, llevándose todo lo necesario para retomar justo donde lo dejaste:

- En modo PR completo, el diff del PR staged y tus ediciones sin commitear.
- En modo `--step`, el commit en el que estás, sus ediciones y todas las
  ediciones que tengas bancadas en los otros commits. Los refs de ediciones se
  mueven de `refs/review-edits/` (que `git review clean` poda) a
  `refs/review-saved-edits/`, así un `git review clean` nunca toca una review
  guardada.

`git review continue` convierte `review-saved/<rama>` de nuevo en la
`review/<rama>` activa y restaura ese estado exacto — en modo `--step` te deja de
vuelta en el mismo commit, con `git review next` / `git review prev` funcionando
como antes. Sin argumento retoma la única review guardada, o las lista si hay más
de una; nombrá una rama para elegir cuál.

Empezar un `git review start` nuevo sobre una rama que ya tiene una review
guardada se rechaza, para que no pierdas la pausada sin querer — retomala o
descartala con `git review forget --saved` primero.

### `git review finish`

- Por defecto — crea `review-fixes/<rama>` sobre el tip del PR con tus ediciones
  staged, para que las revises y commitees vos.
- `--onto-source` — en su lugar deja tus ediciones staged sobre la rama del PR
  misma, para que las revises y commitees vos ahí.
- En cualquiera de los dos casos el resultado queda local — revisalo y pusheá a
  mano cuando estés listo.
- `--resume` — en modo `--step`, si las ediciones bancadas chocan con el tip del
  PR, el replay deja marcadores de conflicto y se detiene. Resolvélos en el árbol
  y corré `git review finish --resume` (con los mismos flags) para seguir.
- `--abort` — deshace el último finish y te devuelve a `review/<rama>` justo donde
  estabas editando, igual que `git merge --abort` revierte un merge. Se niega si
  cambiaste la rama del finish desde entonces, para que no pierdas trabajo; agregá
  `--force` para descartar esos cambios y abortar de todas formas.
- Se niega sobre un `git review compare` de solo lectura — no hay una rama
  escribible a la cual devolver tus ediciones.

### `git review preview`

Muestra las ediciones que hiciste hasta ahora — el mismo diff que `git review
finish` extraería, tus ediciones sobre el tip del PR — pero **nunca commitea,
nunca cambia de rama y nunca toca tu árbol de trabajo ni el índice**, así volvés
directo a editar donde lo dejaste. Pensalo como "¿qué me daría `finish` ahora
mismo?".

- `--stat` — muestra un resumen tipo diffstat en lugar del diff completo.
- En modo `--step` re-aplica las ediciones del commit actual más cada edición
  bancada sobre el tip, igual que `finish`. Una edición que choca de verdad con el
  tip es el único caso que difiere: un preview de solo lectura no puede dejarte
  marcadores de conflicto, así que omite esa edición e imprime una nota
  apuntándote a `finish`.

### `git review abort`

Cancela la review actual en un paso: te devuelve a la rama desde la que empezaste
y borra la rama `review/<rama>` y sus ediciones bancadas. Como la review se
canceló (no se completó), vuelve el marcador de `--delta` a tu última review
real, así un `--delta` posterior no se saltea commits que nunca revisaste.

### `git review clean`

- Sin `<rama>`, borra todas las ramas `review/*` y `review-fixes/*`.
- Nunca borra la rama en la que estás parado.
- También descarta los edit refs bancados commit-a-commit, incluso cuando no
  queda ninguna rama de review.
- Deja intacto el marcador de `--delta` — para descartarlo usá `git review forget --delta`.
- Deja intactas las reviews guardadas (`review-saved/*`) — para descartar una usá
  `git review forget --saved`.

### `git review forget --delta`

Descarta el tip de la última review que usa `--delta`. El marcador se conserva a
propósito para que `--delta` sobreviva a `git review clean`; así es como lo borrás.

- `<rama>` — olvidar el/los marcador(es) de una rama de origen: el remoto y el de
  `--local` si existe.
- `--all` — olvidar todos los marcadores (no toca `reviewworkflow.base`).
- `--stale` — hace fetch y prune de `origin`, y olvida solo los marcadores cuya
  rama ya no existe: los remotos cuya `origin/<rama>` se fue (PRs mergeados y
  borrados) y los de `--local` cuya `<rama>` local se fue. Si el fetch falla,
  aborta sin borrar nada.
- `--dry-run` — con `--stale`, lista lo que olvidaría sin hacerlo. Se rechaza con
  los otros modos, donde el objetivo ya es explícito.

### `git review forget --saved`

Descarta una review apartada con `git review save`: borra `review-saved/<rama>`,
sus ediciones bancadas y su metadata. Como una review guardada quedó pausada (no
completada), también vuelve el marcador de `--delta` a tu última review real, igual
que hace `git review abort`.

- `<rama>` — descartar la review guardada de una rama de origen.
- `--all` — descartar todas las reviews guardadas.
- `--dry-run` — listar lo que se descartaría sin descartarlo.

## Configurar la rama base

La rama base es donde se integran los PRs (`develop`, `main`, `master`, …) y
varía por equipo, así que no hay default — configurala una vez por repositorio:

```sh
git config reviewworkflow.base develop
```

Orden de resolución: argumento posicional `base` (o `--base <base>`) →
`reviewworkflow.base`. Si no hay ninguno, una review completa falla y te pide que
la configures. La base es cualquier commit-ish — una rama, un tag (`v1.0`) o un
commit — no solo un nombre de rama.

## Configurar el remoto

Por defecto los comandos hacen fetch y push contra `origin`. Si revisás un
repositorio que no es tuyo (un `upstream` con tu `origin` como fork, por
ejemplo), apuntá el flujo a ese remoto:

```sh
git config reviewworkflow.remote upstream
```

Afecta a `git review start` y `git review forget --delta --stale`. Una review
`--local` ignora el remoto por completo.

### Es por repositorio por diseño

Tanto `reviewworkflow.base` como `reviewworkflow.remote` son simples claves de
`git config`, así que se guardan **por repositorio** (en el `.git/config` de cada
uno). No hay perfiles ni un archivo de config compartido: cada repositorio en el
que trabajás mantiene su propia base y su propio remoto de forma independiente, y
nunca se mezclan entre sí:

```sh
# repo A: los PRs se integran en main, traídos desde origin (el default)
cd ~/proyecto-a && git config reviewworkflow.base main

# repo B: los PRs se integran en develop, revisados desde un upstream ajeno
cd ~/proyecto-b
git config reviewworkflow.base develop
git config reviewworkflow.remote upstream
```

Lo mismo aplica a los marcadores de `--delta`: también viven en la config de cada
repo. Si querés un valor de respaldo para *todos* tus repos, configuralo de forma
global (`git config --global reviewworkflow.base main`); un valor por repo lo
sobrescribe, y un argumento posicional `base` sobrescribe a ambos.

## Flujo típico

```sh
git config reviewworkflow.base develop      # una vez por repo

git review start feature/login              # dejar todo el PR staged
# ...abrir el repo en tu IDE, leer el diff staged, editar inline, correr tests...
git review finish                            # extraer fixes a review-fixes/feature/login
git diff --cached && git commit -m "address review comments"
git review clean feature/login              # limpiar

# Re-revisar después de que el autor pushea más commits:
git review start feature/login --delta       # solo los commits nuevos
git review start feature/login --delta --step  # ...y recorrerlos de a uno

# O recorrer el PR commit por commit desde el principio:
git review start feature/login --step        # arrancar en el primer commit
# ...editar, y después...
git review next                              # bancar cambios, pasar al siguiente
git review next                              # ...hasta "no more commits"
git review finish                            # re-aplicar todos tus cambios sobre el tip

# Elegir un commit de inicio explícito:
git review start feature/login --from a1b2c3d

# Revisar la rama en la que ya estás (omitiendo el nombre):
git switch feature/login && git review start         # contra la base configurada
git review start --base develop                       # ...o contra una base explícita

# Comparar contra un tag en vez de una rama:
git review start feature/login v1.0

# Comparar dos releases en modo lectura:
git review compare v1.0 v2.0

# Revisar tu propia rama local antes de pushear, offline:
git review start feature/login --local
```

## Requisitos

- Git 2.23+ (usa `git switch`). Se recomienda Git 2.38+: excluir el contenido de
  la base mergeado dentro del PR usa `git merge-tree --write-tree`, y en git más
  viejo ese paso se saltea (el contenido de la base mergeado aparecería en
  `--delta`/`--from`).
- Un remoto llamado `origin` (o el que configures con `reviewworkflow.remote`).
- Una shell POSIX. En Linux y macOS es la de por defecto. En Windows los comandos
  corren bajo Git Bash o WSL, no en `cmd.exe` ni PowerShell.

## Contribuir

Reportes de bugs, fixes e ideas son bienvenidos. Mirá
[CONTRIBUTING.md](CONTRIBUTING.md) para cómo correr los tests y el proceso de
release.

## Licencia

[MIT](LICENSE) © EzeVillo
