# Quickstart de validación: 015-cliente-tui

Guía para validar la TUI localmente. **No es tutorial de usuario final.**

## Prerrequisitos

1. **Go** en la versión que diga `tui/go.mod`, única fuente del pin.
2. **git** en el `PATH`.
3. **La CLI** `git-review-workflow` en una versión ≥ `min_cli_version.tui` del canónico
   (`contracts/client-product-surface.yaml`). Durante el desarrollo, el checkout mismo: con
   `npm link` el `git review` del `PATH` corre el árbol de este repo.
4. **Un multiplexor** (tmux o screen) para las historias 1 y 8. Sin él se validan igual todas las
   demás.
5. Repo de prueba: `./tests/sandbox.sh` desde la raíz (PR de juguete con walkthrough) y
   `./tests/sandbox-min.sh` (el hermano vacío: sin walkthrough ni `reviewworkflow.base`, la única
   forma de ver la pantalla de setup del panel).

## Build y tests

```sh
cd tui
gofmt -l .        # tiene que salir vacío
go vet ./...
go test ./...     # corre con nopWatcher: FR-063 probado por construcción
```

Esperado en verde: parsers de porcelain, situación, `PanelModel`, intent, argv de las 26 acciones,
`UserCopy`, iconos (ancho de celda), keymap, tabla de confirmaciones, contrato de layout, golden
files, alcanzabilidad sólo-teclado y sólo-mouse, y las dos fronteras de imports.

### La suite con la vigilancia encendida

```sh
GIT_REVIEW_UI_WATCH=1 go test ./internal/host -run TestWatch
```

Es el **único** paquete que instancia `fsnotify`. Cubre los cinco escenarios de FR-058 —crear y
borrar refs, empaquetarlos, escribir config, tocar el borrador y un worktree enlazado— más los dos
que trae la sexta raíz: un `git checkout` (dos seguidos, para probar que el watch sobrevive al rename
de `HEAD`) y el dedup de `<git-dir>` con el directorio común.

### Golden files

```sh
go test ./internal/ui                                   # compara
go test -tags goldenupdate ./internal/ui -update        # regenera, SOLO local
```

La bandera `-update` **sólo se compila** bajo el build tag `goldenupdate`, así que en el binario que
arma CI no existe: pasarla ahí es un error de flag desconocido, no un no-op silencioso (FR-070). Los
golden se revisan **como diff**.

### Anti-drift multi-cliente

```sh
node scripts/check-client-product-surface.mjs
```

Falla si el canónico y cualquiera de los **cuatro** clientes divergen: `min_cli_version` del cliente
contra su constante, `per_client_strings`, comandos npm, strings compartidos, las 27 acciones, la
secuencia de `panel_layout`, iconos, `confirms:`, `reveals:` y `listing.applies_to`.

## El verbo, sin la TUI instalada

```sh
git review -h            # la lista tiene que incluir `ui`
git review ui            # exit ≠ 0 + stderr con qué falta y cómo instalarlo
bats tests/ui.bats       # o: ./tests/run-docker.sh ui.bats
```

Esperado: se **niega**, no pregunta ni instala. Es la mitad de la User Story 2, y funciona **antes**
de que exista un binario.

## Correr la TUI

```sh
cd tui && go build -o /tmp/git-review-ui ./cmd/git-review-ui

# el punto de entrada canónico:
GIT_REVIEW_UI=/tmp/git-review-ui git review ui

# o poniéndolo en el PATH, que es lo que hacen los paquetes:
PATH="/tmp:$PATH" git review ui       # y también: git review-ui
```

Desde el sandbox, en un pane; el editor en otro.

## Recorrido de validación

### 1 — El refresco (User Story 1)

Con la TUI abierta en un pane y **sin tocarla**, desde el pane de al lado:

| # | Hacer | Esperar |
|---|---|---|
| 1 | `git review next` | el panel muestra la entrada nueva, solo |
| 2 | esperar varios minutos sin tocar nada | **cero** invocaciones nuevas en `showCliLog` (SC-002) |
| 3 | escribir el borrador del revisor en el gitdir, **de una rama con barra** (`feature/foo`) | la fila del borrador actualiza su par de progreso sola — es el caso que el cierre de directorios existe para cubrir |
| 4 | `git pack-refs --all` | el panel sigue vivo y una mutación posterior dispara |
| 5 | `git review config base <otra>` | el panel refleja la base nueva (rename atómico) |
| 6 | un `finish` desde la propia TUI | **un** repintado, no cinco (SC-004) |
| 7 | `tmux set -g focus-events off`, reabrir, irse a otro pane y volver | sigue funcionando con los otros tres disparadores |
| 8 | `GIT_REVIEW_UI_WATCH=0`, operar el panel entero | todo igual y **ningún dato incorrecto**; sólo deja de enterarse solo (SC-016) |
| 9 | con la vigilancia apagada, cambiar el estado por fuera y apretar `r` | lo trae. El panel no queda mintiendo para siempre |
| 10 | `git checkout <otra rama>` en el otro pane | el panel cambia solo — es la sexta raíz (`<git-dir>` filtrada a `HEAD`) |
| 11 | `git rebase -i` sobre veinte commits en el otro pane | el panel lee **a lo sumo una vez por segundo**, no veinte: es el techo del debounce acotando la única ráfaga plausible |

En un **worktree enlazado**, la prueba que separa las dos raíces: un `checkout` en el worktree donde
corre la TUI dispara, y uno en el worktree principal **no**. Ver `contracts/refresh.md`.

### 2 — Instalar, descubrir y arrancar (User Story 2)

| # | Hacer | Esperar |
|---|---|---|
| 1 | `git review ui` sin binario | exit ≠ 0, stderr con el comando de instalación |
| 2 | con binario | reemplaza el proceso; el exit code de la TUI es el que ve la shell (SC-011) |
| 3 | `GIT_REVIEW_UI=<ruta>` | gana sobre el `PATH` |
| 4 | `git review-ui` | exactamente lo mismo |
| 5 | `PATH` sin la CLI | situación `cli-missing` con el comando copiable — **y no un timeout** |
| 6 | ídem en un terminal sin OSC 52 (tmux con `set-clipboard off`) | el comando queda en una línea limpia seleccionable; el panel dice cómo seleccionarla y **nunca afirma haber copiado** |

### 3 — Leer y operar (User Story 3)

Sandbox con review **walk**, **step** y **whole**. Contrastar cada campo contra
`git review status --porcelain` en otro pane, y recorrer la secuencia entera **dos veces**: una sólo
con teclado y otra sólo con mouse.

- cursor en 2 de 7 con la 3 marcada `key` → se ve la entrada 2, la posición 2/7 y la 3 distinguida;
- `j`/`k` mueven la fila enfocada y **no** el cursor de la review;
- `n` mueve el cursor de la review;
- en `finish-conflict`, las teclas del cursor no están y **la barra no las ofrece**;
- el picker abre una entrada **sin** cambiar el cursor de la CLI;
- un walkthrough degradado a whole muestra su nota y la review sigue usable.

### 4 — Abrir archivo, diff y why (User Story 4)

Con paths **con espacio y no-ASCII**, en los tres modos:

- el archivo se abre en el editor configurado, con el path correcto;
- el diff se ve con la herramienta del usuario y el color de git, **no** con un visor propio;
- el *why* coincide con el que la CLI devuelve para el path **crudo**;
- un archivo eliminado en el rango no es fatal;
- «abrir todos los cambios» **no existe** en esta TUI, y su ausencia está declarada en el canónico.

### 5 — El ciclo de riesgo (User Story 5)

Desde `sandbox-min.sh` (sin base configurada):

- se ve **sólo** el paso de configurar base y remote, sin un *Start* engañoso;
- con base, el asistente ofrece **sólo** las formas de lectura que la CLI reporta viables, y al
  terminar la última pregunta **arranca sin cartel**;
- abortar muestra **una** confirmación, la del único punto de confirmación del cliente;
- un cierre pendiente muestra su banner con los dos controles y **ningún** aviso que repita en prosa
  lo que los controles ya dicen;
- un cierre en conflicto usa el argumento de destino **sólo** si el porcelain lo reporta;
- una segunda mutación durante otra **se descarta con aviso**, no se encola.

Contrastar cada argv contra [contracts/cli-invocation.md](./contracts/cli-invocation.md) usando
`showCliLog`.

### 6 — El pie (User Story 6)

Sandbox sin review, con borrador fresco, borrador gastado, guías en los tres estados y al menos una
rama de ediciones:

- la fila del walkthrough nombrada **por su rama**, con badge y sus dos verbos;
- **las dos** filas de guías, exista o no cada archivo, con badges distintos;
- un borrador a medio llenar muestra el par de progreso y el control de arrancar apagado con el
  motivo a mano;
- las ramas de ediciones, una por fila con su badge, y **la rama en la que estás no ofrece
  borrarse**;
- entrar en una review → **ninguna** sección de pie;
- con varias secciones abiertas en un pane bajo, el pie ocupa a lo sumo el **55%** y scrollea con
  **una sola** barra, sin recortar.

### 7 — La lista de acciones (User Story 7)

- en cada situación, la lista enumera exactamente lo que esa situación habilita, con su tecla al lado
  donde la tenga;
- en una review activa, ahí están las **cuatro** que el cuerpo no dibuja;
- una destructiva elegida desde la lista pasa por la **misma** puerta de confirmación;
- una invocación que falló muestra comando, directorio, duración y error — a un solo gesto y nunca en
  la primera capa.

### 8 — El pane real (User Story 8)

```sh
tmux new-session -x 80 -y 24    # y después -x 120 -y 40
NO_COLOR=1 git review ui
GIT_REVIEW_UI_ASCII=1 git review ui
```

- ninguna línea se desborda ni se corta a mitad de columna, en las ocho situaciones;
- sin color, todo legible;
- con ASCII forzado, **ninguna fila se pierde**;
- las columnas de todas las filas con icono caen alineadas;
- redimensionar el pane en vivo rehace el layout sin corromperlo;
- matar el proceso con un fallo deja el terminal restaurado: sin alt-screen colgada ni cursor
  escondido;
- en un terminal que no entrega eventos de mouse, los mismos controles y todo operable con teclado,
  **sin mensaje de error ni degradación visible**;
- la tecla que apaga el mouse devuelve la selección nativa por arrastre y el panel lo muestra.

## Matriz smoke multi-OS (antes del release)

En Windows, macOS y Linux:

| # | Caso | OK si |
|---|---|---|
| 1 | `git review ui` con la CLI vieja | situación `cli-outdated`, no `cli-missing` |
| 2 | path acentuado y con espacio en el rango | lista bien y abre bien |
| 3 | `start --offline` desde el asistente | review activa |
| 4 | un verbo de red con credenciales que pedirían prompt | falla con diagnóstico, **no** cuelga el pane |
| 5 | worktree enlazado | las guías salen del común y el borrador del worktree |
| 6 | Windows: `git review ui` con la TUI instalada por `web-install.ps1 -WithUi` | arranca |
| 7 | repo con backend `reftable` | arranca y refresca |
| 8 | `cwd` fuera de un repositorio | situación de error accionable, no pantalla en blanco |

## Empaquetado

```sh
cd tui && ./bump-version.sh 0.1.0
bats tests/version-consistency.bats        # el bloque de la TUI
node scripts/check-client-product-surface.mjs

# los siete binarios y sus sumas
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" ./cmd/git-review-ui
```

Esperado: los **siete** archivos del Release existen, no están vacíos, y el `SHA256SUMS` los cubre a
todos. **No hay ningún `package.json` bajo `tui/`** — la TUI no se publica en ningún registro
(FR-049), y `version-consistency.bats` lo afirma para que la vía descartada no vuelva sin que nadie
lo note.

**El instalador de la CLI, sin el flag, no toca nada de la TUI** (FR-079):

```sh
PREFIX=/tmp/probe sh web-install.sh     # sin GIT_REVIEW_WITH_UI=1
ls /tmp/probe                           # NO tiene que aparecer git-review-ui
```

La fórmula y los dos one-liner están en
[contracts/packaging-release.md](./contracts/packaging-release.md). **No hay ninguna alta previa que
hacer**: sin registro de paquetes de por medio, el modo de falla que este documento advertía —el
primer release muriendo con un error que parece de OIDC roto— desapareció con la vía que lo causaba.
