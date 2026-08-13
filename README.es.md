# git-review-workflow

> Revisá un pull request **editándolo y corriéndolo**, no solo leyéndolo. Todo el
> PR aparece en tu working tree como un único diff staged; después tus
> correcciones se extraen a una rama limpia automáticamente. Re-revisá solo lo
> que cambió.
>
> Y cuando el cambio lo escribió un **agente de IA**, el agente puede escribir
> también el **orden de lectura** — un walkthrough committeado junto al código
> que dice qué archivo leer primero y por qué. `git review start` lo detecta solo
> y te lleva por el diff en ese orden, en vez de alfabéticamente.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/tag/EzeVillo/git-review-workflow?label=release&sort=semver)](https://github.com/EzeVillo/git-review-workflow/releases)

[English](README.md) · **Español** · [Sitio web](https://ezevillo.github.io/git-review-workflow/)

Clientes: [extensión VS Code](vscode-extension/README.md) · [plugin JetBrains IDE](jetbrains-plugin/README.md) · [extensión Visual Studio](visualstudio-extension/README.md)

[![Mirá la demo](trailer-poster.png)](https://youtu.be/LsSQtNFnjRQ)

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

## Revisar lo que escribió un agente

Le pediste una feature a un agente. Volvió con catorce archivos cambiados y un
diff ordenado alfabéticamente — el único orden que garantiza no decir nada sobre
el cambio. Revisar eso es reconstruir, archivo por archivo, un razonamiento que
nunca viste.

El agente que hizo el cambio es el único que *sí* conoce ese razonamiento, y
[`git review walkthrough`](#git-review-walkthrough) le da dónde ponerlo. Como
parte de la misma tarea, justo después de escribir el código, el agente corre:

```sh
git review walkthrough init                   # esqueleto con cada archivo cambiado
# ...completa el orden de lectura y un por qué en cada entrada...
git review walkthrough build                  # valida, ordena y renumera
git add .review/walkthrough.md && git commit  # viaja con el PR
```

Después lo revisás vos — sin habilitar nada ni configurar nada de tu lado:

```sh
git review start feature/rate-limit
```

`git review start` encuentra el walkthrough solo: imprime el heads-up del agente
sobre qué es delicado en este PR y después te deja en el primer archivo con la
nota sobre *por qué* importa — las entradas que el agente marcó como esenciales
salen etiquetadas `(key)`; `git review next` te lleva por el
resto del orden. Todo el PR sigue staged y editable durante todo el recorrido,
así que corregís inline lo que encontrás y `git review finish` te devuelve tus
correcciones en una rama aparte.

Para que salga automático, poné la instrucción donde tu agente la vaya a leer —
su `CLAUDE.md`, su `AGENTS.md`, o tu template de prompt:

> Después de hacer el cambio y commitearlo, corré `git review walkthrough init`,
> completá el orden de lectura y un *por qué* de una línea en cada entrada, la
> sección `## Heads-up` con lo delicado de este PR, y un marcador `> key` en las
> pocas entradas que un reviewer no puede leer por arriba; después corré
> `git review walkthrough build` y committeá `.review/walkthrough.md`.

Lo que queda es un archivo Markdown committeado, así que también se lee tal cual
en GitHub para cualquiera que nunca instale esto. Y conseguís lo mismo **sin que
el autor se suba**: en un PR que no trae walkthrough, apuntá tu propio agente al
diff y que genere uno solo para tu review — mirá [Flujo típico](#flujo-típico).

Revisar PRs escritos por agentes es también donde rinde el resto del flujo: traés
todo el cambio a tu working tree, lo corrés de verdad y corregís inline los code
smells y los errores sutiles en vez de escribir comentarios sobre ellos.

## ¿Por qué no usar la vista de PR de tu IDE?

La mayoría de las herramientas te dejan *ver* un PR. Esto resuelve dos cosas:
*actuar* sobre uno — editarlo y correrlo como cambios normales del working tree
y después devolver tus correcciones sin stash ni cherry-pick manuales — y
darle un **orden de lectura guiado**, algo que ni git ni GitHub ofrecen de
forma nativa.

|                                  |     Ver el PR      | Orden + por qué, por archivo | Editar y correr como working tree | Extraer tus fixes automáticamente | Re-review incremental (`--delta`) | Independiente del editor |
|----------------------------------|:------------------:|:----------------------------:|:---------------------------------:|:---------------------------------:|:---------------------------------:|:------------------------:|
| **git-review-workflow**          |         ✅          |              ✅               |                 ✅                 |                 ✅                 |                 ✅                 |            ✅             |
| `gh pr checkout` / `glab`        | ⚠️ checkout pelado |              ❌               |                 ✅                 |                 ❌                 |                 ❌                 |            ✅             |
| JetBrains *Review Pull Request*  |         ✅          |              ❌               |         ⚠️ solo en el IDE         |                 ❌                 |                 ❌                 |            ❌             |
| Extensión *GitHub PR* de VS Code |         ✅          |              ❌               |         ⚠️ solo en el IDE         |                 ❌                 |                 ❌                 |            ❌             |
| Web de GitHub / GitLab           |         ✅          |              ❌               |                 ❌                 |                 ❌                 |            ⚠️ parcial             |            ✅             |

Ninguna de las alternativas de arriba te da un **orden de lectura curado por el
autor** — qué archivo leer primero, y por qué — en vez de una lista alfabética o
un diff pelado. El autor (a menudo un agente de IA) lo escribe una sola vez, con
`git review walkthrough init`/`build`, y lo commitea junto con el PR; un
reviewer no tiene que hacer nada especial — `git review start` lo detecta solo
y te deja directamente en ese orden, recorriéndolo con
`git review next`/`prev`. Mirá [`git review walkthrough`](#git-review-walkthrough)
para el flujo completo, tanto del lado del autor como del reviewer. Ni siquiera
necesitás que el autor o tu equipo se suban para aprovecharlo — mirá
[Flujo típico](#flujo-típico) para generar el tuyo, solo para una review.

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
recorrer un PR con un walkthrough curado o commit por commit, limpieza — mirá
[Flujo típico](#flujo-típico).

## Instalación

Estos comandos se enchufan a `git` como un único subcomando — los usás como
`git review start`, `git review finish`, etc. El [Inicio rápido](#inicio-rápido)
de arriba ya cubre la instalación por npm; descolapsá abajo para Homebrew, el
instalador nativo de Windows, o una opción sin Node.

<details>
<summary>Métodos de instalación (npm, Homebrew, Windows, en una línea, PATH, autocompletado)</summary>

Elegí el método que mejor te quede. Las opciones por gestor de paquetes son las
más fáciles y **te configuran el `PATH` solas**.

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

</details>

## Comandos

> **Cómo leer la sintaxis:** `<x>` es **obligatorio**, `[x]` es **opcional**, y
> `a | b` significa **elegí uno, no los dos**.

Cada comando es un verbo bajo `git review`. Corré `git review -h` para ver la
lista, o `git review <verbo> -h` para el detalle de un verbo.

| Comando                                                                                                                                    | Qué hace                                                                                                                                                                                                                                                                                                                                                                               |
|--------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `git review [-h \| --version]`                                                                                                             | Lista todos los verbos o imprime la versión instalada.                                                                                                                                                                                                                                                                                                                                 |
| `git review start [<rama>] [<base> \| --base <base> \| --delta \| --from <commit>] [--step \| --no-walk \| --keys] [--local \| --offline]` | Hace fetch de `origin` y deja el diff del PR staged en una nueva rama `review/<rama>` (omití `<rama>` para revisar la rama actual; entra en modo walk si el PR trae un walkthrough; `--keys` restringe el walk a las entradas marcadas `> key`; `--local` revisa tu rama local pero sigue comparando contra la base de origin; `--offline` además salta el fetch y usa tu base local). |
| `git review compare <a> <b> [--step \| --no-walk \| --keys]`                                                                               | Deja staged el diff entre dos commit-ish (tags, commits, ramas) en modo lectura, para leerlo o recorrerlo. `git review finish` se niega — no hay a dónde escribir.                                                                                                                                                                                                                     |
| `git review walkthrough (init [--base <base>] [--force] \| build [--check])`                                                               | Escribe un walkthrough de lectura para el PR de la rama actual — un orden curado de los archivos cambiados con una nota en cada uno, committeado como `.review/walkthrough.md`.                                                                                                                                                                                                        |
| `git review walkthrough draft [--build] [--local \| --offline] [--delta] [--force] [<rama>]`                                               | Escribí tu propio orden de lectura para el PR de otra persona, fuera del working tree — no se stagea, commitea ni deshace nada. `git review start` lo lee en lugar del walkthrough del PR. `--build` lo valida y renumera.                                                                                                                                                             |
| `git review next` / `git review prev`                                                                                                      | Mueve una review `--step` o walkthrough a la entrada siguiente / anterior.                                                                                                                                                                                                                                                                                                             |
| `git review status [--porcelain \| --why <path>]`                                                                                          | Muestra el estado de la review en la rama actual (`--porcelain` para salida legible por programas, incluido un registro `finish` cuando un cierre quedó trabado por conflicto; `--why <path>` para el porqué de una entrada del walkthrough).                                                                                                                                          |
| `git review list [--porcelain]`                                                                                                            | Lista todas las reviews en curso y las guardadas (la rama actual marcada con `*`; `--porcelain` también reporta cierres sin resolver como `pending` o `conflict`).                                                                                                                                                                                                                     |
| `git review save`                                                                                                                          | Pausa la review actual como `review-saved/<rama>` y vuelve a donde empezaste.                                                                                                                                                                                                                                                                                                          |
| `git review continue [rama]`                                                                                                               | Retoma una review guardada con `git review save`.                                                                                                                                                                                                                                                                                                                                      |
| `git review finish [--onto-source] [--resume \| --abort [--force]]`                                                                        | Desde una rama `review/*`, extrae tus ediciones a `review-fixes/<rama>` (o la rama del PR); `--abort` deshace el último finish.                                                                                                                                                                                                                                                        |
| `git review preview [--stat]`                                                                                                              | Muestra las ediciones que hiciste hasta ahora — el diff que `finish` extraería — sin commitear ni cambiar de rama.                                                                                                                                                                                                                                                                     |
| `git review abort`                                                                                                                         | Cancela la review actual y vuelve a donde empezaste.                                                                                                                                                                                                                                                                                                                                   |
| `git review clean [--keep-fixes] [rama]`                                                                                                   | Borra las ramas `review/*` (y por defecto también `review-fixes/*`) de `<rama>`, o todas; `--keep-fixes` deja `review-fixes/*` intactas.                                                                                                                                                                                                                                               |
| `git review forget --delta ([--] <rama> \| --all \| --stale [--dry-run])`                                                                  | Descarta el marcador de `--delta` de una rama, de todas, o solo de las obsoletas.                                                                                                                                                                                                                                                                                                      |
| `git review forget --saved ([--] <rama> \| --all) [--dry-run]`                                                                             | Descarta una review guardada con `git review save`.                                                                                                                                                                                                                                                                                                                                    |
| `git review forget --draft ([--] <rama> \| --all) [--dry-run]`                                                                             | Borra un walkthrough que escribiste para el PR de otra persona.                                                                                                                                                                                                                                                                                                                        |
| `git review config [<clave> [<valor>]] [--unset <clave>] [--porcelain [<rama>]]`                                                           | Lee o escribe la config del producto (`base`, `remote`); `--porcelain` también lista las ramas candidatas a revisar.                                                                                                                                                                                                                                                                   |

<details>
<summary id="git-review-start"><code>git review start</code></summary>

Tiene dos ejes independientes — **rango** (desde dónde empieza) y **layout**
(`--step` o no), que se combinan libremente.

- `<rama>` — la rama a revisar. **Omitila para revisar la rama que tenés
  checkouteada** — el default propio de git (como `push`, `status`, `log`). Solo
  resuelve el nombre; el modo lo siguen eligiendo los flags, así que combiná la
  rama omitida con `--local` para revisar tu trabajo local. Sin `--local`/`--offline`
  revisa `origin/<rama>` — si difiere de tu rama checkouteada te avisa, porque estarías
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
  esta rama, en vez de todo el PR. Ideal para re-revisar un PR actualizado. Una
  review **completada** conserva el tip a través de `git review clean`; un start
  **abandonado** (clean o abort sin finish) revierte el marcador para que
  `--delta` no se saltee commits que nunca revisaste. Descartalo a mano con
  `git review forget --delta`.
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
- **Modo walk (automático).** Si el PR trae un walkthrough
  (`.review/walkthrough.md`, escrito por el autor con
  [`git review walkthrough`](#git-review-walkthrough)), `git review start` entra
  en **modo walk**: la misma review completa staged y editable, más un cursor de
  lectura curado por encima. Imprime el heads-up del autor — qué es delicado en
  este PR, se lee una vez antes del primer archivo — y después la primera entrada:
  un archivo y la nota del autor sobre por qué importa, etiquetada `(key)` cuando
  es una de las pocas que el autor marcó como esenciales. Te movés por el orden de
  lectura con `git review next` / `git review prev`. El cursor es *solo* una
  posición de lectura: nunca stagea, resetea ni esconde nada, así que editás y
  hacés `git review finish` exactamente como en una review completa. Las entradas
  se filtran al rango real de la review, así un walkthrough que ya no coincide
  (ej. uno viejo con `--delta`) simplemente degrada — un walkthrough roto o
  desactualizado **nunca** falla una review; a lo sumo cae a una review completa
  normal con una nota. Un archivo que cambia en el rango pero no tiene entrada
  propia — el caso típico es un walkthrough desactualizado — tampoco queda
  afuera: se agrega al final del orden de lectura, marcado `(uncovered)` en vez
  de `(key)`, así una review nunca llega a `git review finish` con archivos del
  PR que nunca viste — incluido el propio walkthrough committeado, que entra en
  esa misma cola sin anotar: un walkthrough nunca puede anotarse a sí mismo,
  pero es contenido que el PR agrega como cualquier otro archivo, así que nunca
  es el único archivo que ninguna review muestra.
- `--no-walk` — ignorar cualquier walkthrough y revisar el diff completo a secas.
  `--step` también tiene prioridad sobre walk (son dos formas del mismo eje de
  layout), así que `--step` gana sin error — solo imprime una nota avisando que
  ignora el walkthrough del PR (se silencia pasando además `--no-walk`).
- `--keys` — modo walk restringido a las entradas marcadas `> key`. El cursor
  de lectura, `next`/`prev` y el status listan solo esos archivos esenciales
  (en el orden del walkthrough). Requiere un walkthrough con al menos una key
  en rango; no se combina con `--step` ni `--no-walk`. El PR completo sigue
  staged — solo se acorta el recorrido guiado. Es un primer pase enfocado, no
  un reclamo de que el resto del PR no importe.
- `--local` — revisar tu `<rama>` **local**, incluidos los commits sin pushear,
  en vez de la copia de `origin`. La base es otra cosa —es el punto de merge
  compartido—, así que se sigue haciendo fetch y se sigue comparando contra la
  copia de `origin` incluso con `--local`; solo cambia tu rama. Te deja revisar
  tu propio trabajo antes de pushear. Mantiene su propio marcador de `--delta`,
  separado del remoto, así una review local y una remota de la misma rama nunca
  se pisan el progreso.
- `--offline` — como `--local`, pero además salta el fetch por completo y
  resuelve la base desde tus ramas locales también, para el caso raro en que no
  tenés acceso a la red. Implica `--local`.
- Siempre actualiza desde `origin` primero y **falla** si no puede (salvo con
  `--offline`). Sin `--local`/`--offline` la revisión se arma desde
  `origin/<rama>`, nunca desde una copia local vieja. Si una rama local con el
  mismo nombre apunta a otro lado, te avisa: la review refleja el remoto, no tu
  checkout, y un `git review finish --onto-source` posterior se va a negar hasta
  que tu rama local coincida.
- No corre si tenés cambios locales (tracked **o** untracked no ignorados) —
  arrancá desde una rama limpia.
- **Los merges de la rama base se excluyen.** Si el autor mergeó la base (ej.
  `develop`) dentro del PR, ese contenido mergeado queda afuera de la review en
  todos los modos, así ves solo los cambios del autor.
- `--` termina el parseo de opciones, la convención habitual de git: todo lo que
  va después se trata como argumento posicional, así una rama cuyo nombre empieza
  con `-` igual se puede revisar (ej. `git review start -- --weird develop`).

</details>

<details>
<summary><code>git review compare</code></summary>

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
- Si el árbol de `<b>` trae un walkthrough, `compare` también entra en modo walk,
  igual que `git review start`, y sigue siendo de solo lectura. `--no-walk` opta
  por salir.

</details>

<details>
<summary id="git-review-walkthrough"><code>git review walkthrough</code></summary>

Lo único que ni git ni GitHub ofrecen: un **orden de lectura escrito por el
autor** sobre un PR. Como autor (a menudo un agente de IA), curás el orden en que
conviene leer los archivos cambiados y anotás cada uno con *por qué* importa; un
reviewer que corre `git review start` sobre el PR entra entonces en
[modo walk](#git-review-start) y lo lee en ese orden.

El walkthrough es un sidecar committeado, `.review/walkthrough.md` — Markdown
plano, legible en GitHub, que se mergea con el PR. Hay dos subcomandos:

```sh
git review walkthrough init     # escribe un esqueleto con cada archivo cambiado
# ...completás el orden y los porqués...
git review walkthrough build    # valida, ordena por tus números y renumera 1..N
```

- `init` escribe un esqueleto determinístico con **todos los archivos** cambiados
  vs la base (el mismo rango que verá un reviewer), cada uno como `## ?. <path>`
  más un placeholder `<!-- why: -->`, encabezado por una sección `## Heads-up` con
  su propio placeholder. Se niega a pisar un walkthrough existente sin `--force`.
  `--base <base>` sobreescribe `reviewworkflow.base`.
- Vos (el autor) hacés solo la parte no mecánica: reemplazás cada `?` por un
  número de orden y cada placeholder por una nota corta.
- **`## Heads-up`** es lo único que un reviewer lee antes de abrir un archivo: los
  invariantes que este PR puede romper, las partes sutiles o riesgosas, de qué
  desconfiar. `git review start` lo imprime al entrar. Borrá la sección entera si
  el PR no tiene nada delicado — una sección vacía es peor que ninguna.
- **`> key`** marca las entradas esenciales. Escribilo en una línea propia, como
  primera línea del porqué, en los pocos archivos que llevan el cambio — los que
  un reviewer no puede leer por arriba — y dejá el resto sin marcar; los archivos
  generados, los lockfiles y los renames mecánicos son justamente lo que queda sin
  marca. No lleva valor: el porqué dice el resto. El modo walk etiqueta esas
  entradas con `(key)` y las cuenta al entrar. El revisor puede arrancar con
  `git review start --keys` para recorrer solo esas entradas. El marcador solo
  sirve mientras sea selectivo, así que `build` avisa si están todas marcadas (o
  si un walkthrough largo no marca ninguna).
- **Guide de autoría (opcional):** commiteá `.review/walkthrough-guide.md` con las
  reglas del equipo solo de **contenido** — qué marcar `> key`, cómo escribir los
  porqués y el Heads-up, convenciones locales. **No** cambia el formato del
  walkthrough; `build` no lo valida. `init` y `draft` mencionan el path en las
  instrucciones del esqueleto y avisan por stderr si el archivo está (se resuelve
  en el work tree donde corrés el comando — también sirve al draftear el PR de
  otro con las convenciones de tu equipo).
- `build` valida el archivo, ordena las entradas por tus números, las renumera
  `1..N` y lo reescribe, preservando el heads-up. `--check` valida **sin escribir**
  y sale con código distinto de cero ante cualquier problema — pensado para CI.
  Falla si queda algún placeholder `?.`, `<!-- why` o `<!-- heads-up`, si `> key`
  lleva un valor, si un path aparece dos veces, si el encabezado de una entrada no
  tiene exactamente la forma `## <N>. <path>`, o ante **drift**: el conjunto de
  paths tiene que coincidir exactamente con los archivos cambiados del PR
  (excluyendo `.review/`).

Completar el orden y los porqués es una tarea perfecta para delegarle a un
agente de IA — apuntalo al diff y dejá que escriba los placeholders. Funciona
de los dos lados: el autor del PR puede hacer que un agente redacte el
walkthrough junto con el cambio, y puede ser **todavía más útil del lado del
reviewer** — un reviewer humano necesitaría ya entender el PR para curar a
mano un orden de lectura sobre él, lo cual es circular, mientras que un agente
que lee todo el diff puede escribir ese orden *antes* de que hayas leído un
solo archivo (mirá el caso de review individual en
[Flujo típico](#flujo-típico)).

### Escribir uno para el PR de otra persona

La mayoría de los PRs no traen walkthrough, y no podés commitear uno en una rama
que no es tuya. `git review walkthrough draft` escribe el mismo esqueleto para la
rama que le indiques, **fuera del working tree** — bajo `$GIT_DIR`, donde
`git status` no lo ve, `git review start` no se tropieza con él y `git review
finish` no puede arrastrarlo a tus ediciones extraídas. No hay nada que stagear,
y nada que deshacer:

```sh
git review walkthrough draft feature/checkout          # esqueleto para el PR de otro
# ...completás el orden y los porqués (a mano, o se lo pasás a un agente)...
git review walkthrough draft --build feature/checkout  # valida, ordena y renumera
git review start feature/checkout                      # entra en walk con tu orden
```

- Toma la rama como argumento, igual que `git review start` — estás parado en la
  base, no en el PR — y por defecto usa la rama en la que estás o, si lo corrés
  desde adentro de una review, la rama que esa review está leyendo. `--local`, `--offline` y
  `--delta` resuelven el rango exactamente como lo hace `start`, así que el
  esqueleto lista precisamente los archivos que tu review va a cubrir. Nunca
  hace fetch.
- `--build` aplica la misma validación que `build` sobre el sidecar del autor:
  placeholders, drift, paths duplicados, `> key` con valor. Es un control de
  calidad, no una compuerta: un borrador sin validar ya se puede leer.
- Tu borrador **tiene precedencia** sobre el walkthrough del propio PR mientras
  tenga algo adentro, y `git review status` marca la review como `walk (draft)`
  para que un orden de lectura que escribiste vos nunca se confunda con el del
  autor. Un borrador vacío no es un orden de lectura: la review cae al walkthrough
  del PR, y te dice cuál de los dos usó. Escribir uno sobre un PR que ya tiene te
  lo avisa; borrá el borrador para volver al de ellos.
- **Editalo con la review abierta.** Es un archivo, no un sidecar congelado, así
  que podés reescribir tu orden (o sacarle un `> key`) mientras la review está en
  curso. Si eso deja el cursor pasado la última entrada, `git review` lo vuelve a
  poner sobre la última y te lo dice: nunca confunde que hayas editado con un
  `git commit` de más.
- Es tuyo y es local, así que nada lo tira a tus espaldas: sobrevive a `abort`, a
  `finish` y a `git review clean` (arrancá la rama de nuevo y tu orden de lectura
  sigue ahí), `git review save` lo archiva junto con la review pausada, y los dos
  comandos que lo descartan son los que le apuntás vos — `git review forget
  --draft <rama>` (o `--all`), y `git review forget --saved`, que se lleva junto
  con la review la copia que esa review archivó, y lo dice — el borrador es de la
  rama, así que dos reviews pausadas de una misma rama comparten el nombre, y sólo
  la que lo escribió se lo lleva, de vuelta o al tacho. Si escribís un
  borrador nuevo para una rama mientras su review está pausada, `git review
  continue` se niega en vez de pisar uno de los dos: descartá el que no quieras y
  retomá. `git review save` se niega en el caso espejo — cuando tenés un borrador
  para archivar y otra review pausada ya tiene uno archivado con ese nombre — y
  avisa cuando el que reemplaza no lo puede reclamar ninguna review.

**git review nunca escribe el walkthrough por vos y nunca habla con ningún
servicio.** Te da el esqueleto con la consigna ya escrita adentro, y valida lo
que vuelve. Quién lo completa —vos, un agente, lo que prefieras— es enteramente
decisión tuya.

El walkthrough se arma sobre **historia commiteada** (`base..HEAD`), no sobre el
working tree: commiteá los cambios del PR antes de autorearlo. `init` y `build`
no ven lo que está sin commitear — se niegan con una pista si no hay nada
commiteado, y avisan si hay cambios sin commitear al costado.

El formato del archivo que `build` produce y `start` lee:

```markdown
# Walkthrough

## Heads-up

Las sesiones ahora expiran; todo lo que cacheaba un token queda bajo sospecha.

## 1. src/auth/session.c

> key
Leé esto primero: define la forma del token de la que depende todo lo demás.

## 2. src/auth/login.c

Después el flujo de login que lo consume — fijate el nuevo camino de error.
```

Cada entrada es una línea `## <N>. <path>` (el path tal cual lo reporta git,
escrito en limpio — un nombre con caracteres no-ASCII va tal cual, nunca
C-escapado) seguida de su *porqué* en texto libre, hasta la próxima entrada,
opcionalmente encabezada por el marcador reservado `> key`. Todo lo que
está arriba de la primera entrada es el preámbulo (la sección `## Heads-up`); el
parser lo ignora y `build` lo preserva tal cual, menos los comentarios HTML. La
granularidad es por archivo en v1.

</details>

<details>
<summary><code>git review next</code> / <code>git review prev</code></summary>

Mueven una review `--step` o walkthrough para adelante o para atrás. En modo
`--step` cada movimiento banca las ediciones del commit actual y restaura las que
tenías bancadas en el commit al que vas, así podés ir y venir sin perder trabajo.
En modo walk solo mueven el cursor de lectura — tus ediciones viven en el working
tree todo el tiempo y nunca se tocan.

</details>

<details>
<summary id="git-review-status"><code>git review status</code></summary>

Muestra la review actual: PR de origen, modo, y — en modo `--step` — en qué
commit estás (`[k/N]`) y qué pasos tienen ediciones bancadas. En modo walk muestra
el cursor de lectura: `walk  [k/N] on <path>`. En modo whole (sin walkthrough —
el default) lista los archivos que toca el rango, numerados, sin cursor; un
rango vacío lo dice explícitamente en vez de no imprimir nada.

- `--porcelain` — salida legible por programas para scripts e integraciones de
  editor: líneas estables separadas por tab (ver abajo). De sólo lectura, igual
  que la salida humana — nunca muta config, refs ni el working tree.
- `--why <path>` — imprime *sólo* el texto explicativo del walkthrough para
  `<path>`, nada más en el stream: sin etiqueta, sin ningún otro dato. Sólo en
  modo walk.

**Códigos de salida** — no sólo bajo `--porcelain`: los mismos códigos salen de
todo verbo que detecte la situación (`status`, `list`, `abort`, `finish`,
`preview`, `save`, y `next`/`prev` para el `3`), así que un script nunca tiene
que distinguir según qué comando corrió:

| Código | Significado                                                                                                                      |
|--------|----------------------------------------------------------------------------------------------------------------------------------|
| `0`    | éxito                                                                                                                            |
| `1`    | error — metadata de review ausente o corrupta, uso inválido, no es un repositorio git                                            |
| `2`    | HEAD no está en una rama de review (el caso común, sin nada raro)                                                                |
| `3`    | el cursor del walkthrough quedó fuera de rango porque HEAD se movió de la base de la review — se recupera con `git reset --soft` |

**Formato de `--porcelain`** — una línea por registro, campos separados por
tab, primero el tipo de registro y, si tiene, un path o id **inmediatamente
después** — nunca al final, así los campos nuevos siempre se agregan al final
de la línea. Un consumidor debe ignorar cualquier campo final que no reconozca
en una línea de un tipo que sí conoce, y cualquier línea cuya etiqueta no
reconozca: el formato sólo crece.

```
state	<branch>	<source>	<tip>	<mode>	<walkthrough>[	<position>	<total>	<recorded>	<current>[	<essential>]]
finish	conflict	<onto>
entry	<position>	<id>[	<essential>	<annotated>|<banked>]
subject	<position>	<asunto>
author	<position>	<autor>
base	<base>
```

- `state` — exactamente una línea, siempre la primera. `mode` es
  `whole` \| `step` \| `walk`. `walkthrough` es `none` \| `applied` \| `degraded`
  (siempre `none` en modo step, porque ahí el campo es posicional).
  `position`/`total`/`recorded`/`current` aparecen sólo con cursor (modo
  `step`/`walk`); `current` es un SHA corto en step, un path en walk. `total` es
  el total vigente, derivado en el momento; `recorded` es el registrado al
  iniciar la review — difieren cuando la base se movió, aunque el cursor siga en
  rango. `essential` (`1`/`0`) aparece sólo en modo walk.
- `finish` — sólo mientras un `git review finish` está **trabado por conflicto**
  en esta rama de review (`state` es siempre `conflict` acá; un cierre completo
  ya sacó a `HEAD` de `review/*`, así que `status` nunca lo ve — usá `list` para
  eso). `onto` es `1` si el finish usó `--onto-source`, `0` si no. Se omite el
  registro entero cuando no hay ningún cierre en curso. Con este registro
  presente, el consumidor no debe ofrecer navegación por la secuencia.
- `entry` — cero o más. En step/walk, uno por posición en el orden de lectura
  (paths de walk o commits de step, el mismo orden que recorren `next`/`prev`),
  incluida una entrada de walk que el walkthrough no anota — se agrega al final
  del orden en vez de omitirse. En modo whole, uno por archivo que el rango
  toca — un listado, no una secuencia: `state` sigue sin
  `position`/`total`/`recorded`/`current` en whole. En modo walk los campos
  finales son `essential` (`1`/`0`) y `annotated` (`1`/`0`, `0` en un archivo
  sin entrada propia en el walkthrough — el walkthrough committeado mismo
  siempre cae en este grupo, porque nunca puede anotarse a sí mismo); en modo
  step es sólo `banked` (`1`/`0`, existe una edición bancada bajo
  `refs/review-edits/`); en modo whole ninguno de los dos grupos está presente,
  así que el registro termina en el path. Un rango vacío produce cero registros
  `entry` y sigue terminando en éxito.
- `subject` y `author` — sólo en modo step, uno de cada uno por posición, con el
  asunto del commit y su autor en la forma `Nombre <correo>`. Se emparejan con
  `entry` por `position`, nunca por orden de aparición. Un asunto puede estar
  vacío (un commit cuyo mensaje no tiene primera línea): el registro se emite
  igual, con el campo vacío, para que "sin asunto" se distinga de "este
  git-review no reporta asuntos".
- `file` — sólo en modo step: cero o más líneas del commit **actual** (el del
  cursor / `state.current`), no de todos los commits del rango. Cada línea es
  `file<TAB>position<TAB>path` con posición 1-based *dentro de ese commit* y un
  path con las mismas reglas de bytes que el resto de paths. Los clientes usan
  esta lista para dibujar el inventario de archivos del paso; abrir el diff de
  un archivo queda del lado del host (git / el editor), no en el porcelain. Un
  commit que no toca archivos emite cero líneas `file`. Walk y whole no emiten
  ninguna (en whole los paths ya van como `entry`). `state.total` sigue contando
  sólo las líneas `entry` (commits).
- `base` — sólo en modo whole, y sólo si la review tiene una base registrada: el
  ref contra el que se armó su rango. Registro único y sin posición — la base es
  de la review, no de una entrada. Sin base registrada la línea se omite entera,
  nunca se emite en blanco.

**Campos de texto libre.** `subject`, `author` y `base` llevan texto escrito por
una *persona*, no producido por git, y a diferencia de un path **puede contener
un tab literal**. De ahí la regla para estos registros —y para cualquier registro
futuro con texto libre—: el texto libre es siempre el **último campo** de su
registro, y hay a lo sumo uno por registro. Se emite byte a byte, sin escapar y
sin citar. Se lee como *"todo lo que sigue al N-ésimo tab, hasta el fin de
línea"*, no como *"el campo N-ésimo"* — un `split` por tab truncaría en silencio
un asunto que contenga uno. Por ese mismo motivo estos registros no admiten
campos nuevos al final: lo que haya que agregar va en un registro propio. Un
newline nunca puede aparecer en ellos.

Un path siempre sale exactamente como lo devuelve `git diff --name-only` (con
`core.quotePath=false`): bytes literales, sin escapar, para espacios y
caracteres no-ASCII; la cita propia de git, intacta, para el caso raro de un
path con `"` o `\`. El límite de campo siempre es el tab, nunca el espacio — un
path de git nunca contiene un tab literal.

</details>

<details>
<summary><code>git review list</code></summary>

Muestra *todas* las ramas `review/*` en curso a la vez (con su PR de origen, modo
y posición `[k/N]` para reviews `--step` y walk). Las reviews pausadas con
`git review save` también aparecen, bajo `saved`. La rama en la que estás parado
se marca con un `*`.

- `--porcelain` — inventario legible por programas, el mismo formato separado
  por tab que [`status --porcelain`](#git-review-status):

  ```
  branch	<name>	<saved>	<current>	<orphan>[	<mode>[	<position>	<total>]]
  finish	<branch>	pending|conflict	<onto>
  ```

  `saved`, `current` y `orphan` son `1`/`0` (`orphan` significa que la rama no
  tiene metadata de review — hecha a mano, o dejada por un comando que murió
  antes de escribirla). Cuando `orphan` es `1` no hay `mode`/`position`/`total`
  que reportar. `position` y `total` son los valores registrados al iniciar la
  review, no re-derivados — para los números vigentes y derivados de una review
  puntual, corré `status --porcelain` parado en ella. Cualquiera de los dos
  campos se omite, nunca se rellena con el `?` que usa la salida humana, si la
  clave de config correspondiente falta. Sale con `0` incluso con el inventario
  vacío (que no haya reviews no es un error); `1` sólo si corre fuera de un
  repositorio git.

  Se emite una línea `finish` por cada `review/<x>` con un cierre sin resolver:
  `pending` tras un finish completo que aún espera confirmación/aborto (las
  ediciones están en `review-fixes/<x>` o en la rama del PR; `HEAD` puede haber
  salido ya de `review/*`), y `conflict` cuando un finish se detuvo a mitad del
  replay. `onto` es `1` si ese finish usó `--onto-source`, `0` si no. Se
  empareja con la fila `branch` del mismo nombre. Las reviews sin cierre en
  curso no emiten registro `finish`.

</details>

<details>
<summary><code>git review save</code> / <code>git review continue</code></summary>

`git review save` te deja apartar una review y retomarla después. Convierte la
`review/<rama>` actual en `review-saved/<rama>` y te devuelve a la rama desde la
que empezaste, llevándose todo lo necesario para retomar justo donde lo dejaste:

- En modo PR completo, el diff del PR staged y tus ediciones sin commitear.
- En modo walk, lo mismo, más el cursor de lectura — `git review continue` te deja
  de vuelta en la entrada exacta en la que estabas.
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

</details>

<details>
<summary id="git-review-config"><code>git review config</code></summary>

Lee o escribe la configuración propia de git-review-workflow — la base contra la
que se arma el rango de una review completa, y el remoto del que se trae la
copia a revisar. Espeja `git config` a propósito: clave sola lee, clave más valor
escribe. Válido en cualquier repositorio git, con o sin review activa (no hay
exit `2`).

```
git review config                         # config efectiva, para leer
git review config <clave>                 # una clave (base | remote)
git review config <clave> <valor>         # fija <clave>
git review config --unset <clave>         # borra <clave>
git review config --porcelain [<rama>]    # legible por máquina + candidatas
```

- `base` — el commit-ish contra el que se arma el rango. Sin default de producto:
  una review completa sin ella falla y pide configurarla. Es el mismo valor que
  `git config reviewworkflow.base` (la clave cruda queda como detalle de
  implementación).
- `remote` — de dónde se traen las reviews (default `origin`).
- `--porcelain` — registros separados por tab para scripts y el panel del
  editor:

  ```
  config	<clave>	<valor>
  candidate	<name>	remote|local	<current>
  delta	<rama>	<tip>	remote|local
  ```

  Una clave sin valor efectivo omite su línea `config` entera (así `base` no
  aparece hasta configurarla; `remote` siempre está). `candidate` lista cada
  rama elegible para empezar una review; `current` es `1`/`0`. Con una
  `<rama>` opcional también emite filas `delta` si esa rama tiene un
  marcador `--delta` previo — cero, una o dos: las reviews remotas y locales
  guardan markers separados, y cada eje presente emite su fila (`origin` es
  `remote` o `local`).
- `--` termina el parseo de opciones, así un valor que empieza con `-` (un
  nombre de rama legal) no se toma como flag: `git review config base -- -foo`.

</details>

<details>
<summary><code>git review finish</code></summary>

- Por defecto — crea `review-fixes/<rama>` sobre el tip del PR con tus ediciones
  staged, para que las revises y commitees vos. Si no hiciste ediciones, la rama
  se crea igual (en el tip, sin nada staged) para que la sesión se cierre del
  mismo modo — `git review finish --abort` la deshace, o `git review clean`
  tira el leftover.
- `--onto-source` — en su lugar deja tus ediciones staged sobre la rama del PR
  misma, para que las revises y commitees vos ahí. Sin ediciones, igual aterrizás
  en la rama del PR en el tip (y se conserva el mismo punto de undo).
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

</details>

<details>
<summary><code>git review preview</code></summary>

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

</details>

<details>
<summary><code>git review abort</code></summary>

Cancela la review actual en un paso: te devuelve a la rama desde la que empezaste
y borra la rama `review/<rama>` y sus ediciones bancadas. Como la review se
canceló (no se completó), vuelve el marcador de `--delta` a tu última review
real, así un `--delta` posterior no se saltea commits que nunca revisaste.

</details>

<details>
<summary><code>git review clean</code></summary>

- Sin `<rama>`, borra todos los leftovers que correspondan (`review/*` y, por
  defecto, `review-fixes/*`).
- `--keep-fixes` — borra solo `review/*` (el undo del finish / leftover de la
  sesión) y deja `review-fixes/*`. Útil después de un `finish` exitoso cuando
  querés soltar el punto de undo y quedarte con las edits staged.
- Nunca borra la rama en la que estás parado.
- También descarta los edit refs bancados commit-a-commit y los registros de
  undo del finish (incluido el flag mid-conflict `reviewresume`), incluso cuando
  no queda ninguna rama de review.
- Revierte el marcador de `--delta` al borrar un `review/*` **incompleto** (igual
  que `git review abort`). Un finish completado conserva el marcador. Borrá
  marcadores a mano con `git review forget --delta`.
- Deja intactas las reviews guardadas (`review-saved/*`) — para descartar una usá
  `git review forget --saved`.
- Deja intactos también tus borradores de walkthrough, por la misma razón: los
  escribiste a mano y sobreviven a la review para la que los escribiste. Para
  borrar uno, `git review forget --draft`.

</details>

<details>
<summary><code>git review forget --delta</code></summary>

Descarta el tip de la última review que usa `--delta`. Las reviews completadas
conservan ese marcador a través de `git review clean`; usá este comando cuando
quieras olvidarlo vos.

- `<rama>` — olvidar el/los marcador(es) de una rama de origen: el remoto y el de
  `--local` si existe.
- `--all` — olvidar todos los marcadores (no toca `reviewworkflow.base`).
- `--stale` — hace fetch y prune de `origin`, y olvida solo los marcadores cuya
  rama ya no existe: los remotos cuya `origin/<rama>` se fue (PRs mergeados y
  borrados) y los de `--local` cuya `<rama>` local se fue. Si el fetch falla,
  aborta sin borrar nada.
- `--dry-run` — con `--stale`, lista lo que olvidaría sin hacerlo. Se rechaza con
  los otros modos, donde el objetivo ya es explícito.

</details>

<details>
<summary><code>git review forget --saved</code></summary>

Descarta una review apartada con `git review save`: borra `review-saved/<rama>`,
sus ediciones bancadas y su metadata. Como una review guardada quedó pausada (no
completada), también vuelve el marcador de `--delta` a tu última review real, igual
que hace `git review abort`.

- `<rama>` — descartar la review guardada de una rama de origen.
- `--all` — descartar todas las reviews guardadas.
- `--dry-run` — listar lo que se descartaría sin descartarlo.

</details>

<details>
<summary><code>git review forget --draft</code></summary>

Borra un walkthrough que escribiste para el PR de otra persona con
[`git review walkthrough draft`](#git-review-walkthrough). `git review clean`
nunca los toca —son prosa que escribiste a mano, y una re-review de la rama los
vuelve a leer—, así que este es el comando para tirar uno.

- `<rama>` — borrar el borrador escrito para una rama.
- `--all` — borrar todos los borradores, más los que hayan quedado archivados
  por una review pausada que ya no existe (una cuya `review-saved/<rama>`
  borraste a mano): a esos no los alcanza ningún otro comando.
- `--dry-run` — listar lo que se borraría sin borrarlo.
- Borrar el borrador de una review que sigue viva está permitido (volver al orden
  del autor es algo legítimo de querer) y nombra la review que lo estaba leyendo
  —incluida una review de `git review compare`, que lee un borrador archivado bajo
  un nombre distinto del suyo.
- Toma un nombre de rama, y rechaza cualquier cosa que no lo sea.
- Un borrador que viajó con una review pausada es de esa review, y se va con ella
  con `git review forget --saved`.

</details>

## Configurar la rama base

La rama base es donde se integran los PRs (`develop`, `main`, `master`, …) y
varía por equipo, así que no hay default — configurala una vez por repositorio,
como se muestra en [Inicio rápido](#inicio-rápido):

```sh
git config reviewworkflow.base develop
```

<details>
<summary>Orden de resolución, y configurar el remoto</summary>

Orden de resolución: argumento posicional `base` (o `--base <base>`) →
`reviewworkflow.base`. Si no hay ninguno, una review completa falla y te pide que
la configures. La base es cualquier commit-ish — una rama, un tag (`v1.0`) o un
commit — no solo un nombre de rama.

### Configurar el remoto

Por defecto los comandos hacen fetch y push contra `origin`. Si revisás un
repositorio que no es tuyo (un `upstream` con tu `origin` como fork, por
ejemplo), apuntá el flujo a ese remoto:

```sh
git config reviewworkflow.remote upstream
```

Afecta a `git review start` y `git review forget --delta --stale`. Una review
`--offline` ignora el remoto por completo; `--local` todavía lo usa para
resolver la base.

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

</details>

## Flujo típico

```sh
git config reviewworkflow.base develop      # una vez por repo

# Lado autor: shippear un walkthrough de lectura con el PR (a menudo escrito
# por un agente de IA como autor), curando el orden en que conviene leer los
# archivos y un porqué en cada uno:
git review walkthrough init                  # esqueleto de cada archivo cambiado
# ...completar el orden, un porqué en cada uno, el heads-up y los marcadores > key...
git review walkthrough build                 # ordenar, renumerar y validar
git add .review/walkthrough.md && git commit # viaja con el PR

# Lado reviewer: no hay nada especial que correr — un PR que trae un
# walkthrough se detecta solo:
git review start feature/login              # heads-up + entrada 1; entra en modo walk
# ...leer la primera entrada y su porqué, editar inline si querés, correr tests...
git review next                              # pasar a la siguiente entrada
git review next                              # ...hasta recorrer todo el orden...
git review finish                            # extraer tus ediciones a review-fixes/feature/login
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

# Revisar tu propia rama local antes de pushear, contra la base de origin:
git review start feature/login --local

# Lo mismo, pero sin acceso a la red:
git review start feature/login --offline
```

<details>
<summary>¿El PR no tiene walkthrough? Generá el tuyo, solo para esta review</summary>

Este es un buen lugar para delegarle a un agente de IA el paso de "completar
el orden y los porqués" en vez de hacerlo a mano: todavía no leíste el PR, así
que curar el orden de lectura vos mismo es circular — un agente que lee todo
el diff puede escribir ese orden antes de que mires un solo archivo.

```sh
# No hace falta que el equipo se suba: escribí tu propio orden de lectura para
# cualquier PR que estés revisando. Vive fuera del working tree — no hay nada
# que stagear, commitear ni deshacer — y start lo lee en lugar del walkthrough
# del PR (si trae uno):
git review walkthrough draft feature/login
# ...completar el orden y un porqué en cada uno (o apuntarle un agente al diff)...
git review walkthrough draft --build feature/login
git review start feature/login               # recorre tu orden; status dice walk (draft)
# ...leer, editar, finish o abort como siempre...
# El borrador sobrevive a clean/abort — borralo solo cuando quieras:
# git review forget --draft feature/login
```

Mirá [`git review walkthrough`](#git-review-walkthrough) → *Escribir uno para
el PR de otra persona* para precedencia, ediciones a mitad de review, y cómo
`save`/`continue` llevan el borrador con una review pausada.

</details>

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
