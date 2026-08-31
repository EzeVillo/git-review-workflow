# Contract: CLI invocation (cliente TUI)

**Consumidor normativo**: `tui/internal/host/invoke.go`
**Consumidores hermanos**: `vscode-extension/`, `jetbrains-plugin/`, `visualstudio-extension/`
(misma semántica, cuatro implementaciones)
**Fuente de verdad del wire format**: la CLI en `bin/`, gateada en el **emisor** por
`tests/status-porcelain.bats` (40), `tests/config-porcelain.bats` (16), `tests/list.bats` (19) y
`tests/porcelain-bytes.bats` (6)

Este documento **no** redefine el porcelain: fija cómo la TUI invoca y consume, y es la **lista
cerrada** que FR-014 pide. Una invocación que no esté acá no existe. Cualquier enmienda del wire
format se hace en la CLI y actualiza este contrato y los cuatro clientes.

---

## La forma de toda invocación

**Siempre `git review <verbo> …`. Nunca el dispatcher a mano** (FR-007).

| Plataforma | command | args |
|---|---|---|
| todas | `git` | `review`, `<verbo>` \| `--version`, … |

**Y no hay más filas.** La TUI **no ofrece un ajuste de ruta al dispatcher** (FR-008), a diferencia
de la extensión de VS Code. Ése es el punto de esta decisión:

- `bin/git-review` es un script sin extensión con `#!/usr/bin/env sh`. Para Windows **no es un
  ejecutable**: `CreateProcess` corre `.exe`/`.com`/`.bat`/`.cmd` y no lee shebangs. `git review`
  funciona en Windows porque lo ejecuta **git**, con su capa MSYS y su `sh.exe`.
- Spawneando el dispatcher directo, lo que hay en disco cambia con la instalación: npm deja un shim
  `.cmd` que termina llamando al `sh` del `PATH` (y si no hay, muere — ya mordió a la extensión de
  VS Code), `web-install.ps1` deja el script sin shim (`CreateProcess` falla), Homebrew deja un
  symlink (funciona).
- Llamando a `git`: **una sola forma** en las tres instalaciones y los tres sistemas operativos, con
  **el mismo git que el usuario**, y si `git review` no anda en su shell la TUI falla igual en vez de
  esconder una instalación rota detrás de un camino privado.

**Corolario del argv**: llamando a `git`, la palabra `review` la consume git y el dispatcher recibe
`$1=<verbo>`. Las tablas de abajo listan **el verbo y sus args**, sin el token `review`.

Reglas invariantes:

- **cwd** = el directorio del proceso. Uno solo, sin picker y sin ambigüedad multi-root: una terminal
  está parada en un lugar.
- **sin shell**: argv como arreglo, nunca concatenación.
- **`stdout`/`stderr` decodificados como UTF-8 explícito** en los tres sistemas operativos (FR-010).
- **`GIT_REVIEW_ADVICE=0` siempre**, exportado en **un solo lugar** de este archivo (FR-009). Sin
  eso, la TUI reenvía las notas que sus propias teclas ya cubren.
- Cada start/end deja una entrada en el **registro de invocaciones** en memoria: comando, cwd,
  duración, exit, `timedOut`, `stderr`. Es lo que dibuja `showCliLog` y lo que hace medible SC-002.

---

## Timeouts por clase (FR-010)

| Clase | ms | Verbos |
|---|---|---|
| `Read` | 15 000 | default: `status`, `list`, `config` (lecturas **y** escrituras), `--version` |
| `LocalMutation` | 120 000 | `finish`, `save`, `abort`, `continue`, `next`, `prev`, `clean`, `forget`, `compare`, `walkthrough`, `preview` |
| `Network` | 300 000 | `start`; `forget` si los args traen `--stale` |
| `SupportGit` | 30 000 | el git de apoyo, que no es git-review — ver § Git de apoyo |

Verbo desconocido → `Read`, la misma regla que `invoke.ts`. `config base|remote` cae en `Read` por
ser un verbo fuera de las listas de mutación, igual que en los otros tres: es una escritura de
config, no un movimiento de refs.

Al vencer: matar el proceso (árbol, best-effort) y devolver `timedOut = true`, `exitCode = nil`.
**Un timeout no es una CLI ausente**: se dice que tardó y dónde mirar (edge case de la spec, y
escenario 5 de la User Story 2).

---

## Entorno de red (`class == Network`)

Partir del entorno del proceso y forzar:

- `GIT_TERMINAL_PROMPT=0`
- `GIT_ASKPASS` y `SSH_ASKPASS` → **el propio ejecutable de la TUI** (`os.Executable()`), con
  `GIT_REVIEW_UI_ASKPASS=1` en el entorno. `main` detecta ese centinela como **lo primero que hace**
  —antes de tocar el terminal— y sale distinto de cero sin imprimir nada. Cero archivos nuevos y una
  ruta que existe en las siete plataformas. Ver `research.md` § Decisión 13.

Sólo en las invocaciones de clase red (FR-011). Un prompt de credenciales colgado en un pane es un
pane muerto: no hay diálogo del IDE que lo rescate.

---

## Probe de versión

```text
argv: --version
stdout trim → X.Y.Z
mínimo: min_cli_version.tui del canónico (valor propio del cliente, FR-028)
```

| Resultado | Situación |
|---|---|
| error de spawn / exit ≠ 0 | `cli-missing` |
| no parsea, o **<** mínimo | `cli-outdated` |
| ok | seguir a `status` |

La comparación es un **piso estricto**: no hay techo, así que una CLI más nueva que el mínimo nunca
se reporta desactualizada.

---

## Lecturas de estado

| Orden | argv | Si falla |
|---|---|---|
| 1 | `status --porcelain` | define la situación (0 / 2 / 3 / otro / timeout) |
| 2a | si exit 2: `list --porcelain` | ramas vacías; **no** cambia la situación |
| 2b | si exit 2 o camino de finish-pending: `config --porcelain` | sin config; **no** cambia la situación |
| why | `status --why <raw>` | why failed; vacío → ausente |

`--why` recibe el path **crudo** de la entrada, nunca el mostrable (User Story 4, escenario 3).

**Nunca** parsear el `stdout` humano de una mutación para decidir la situación (FR-013). Y cuando la
TUI muestre el resultado de un verbo en verde, lo lee de **`stdout`**, que es donde los verbos lo
escriben: `stderr` está reservado a errores y notas, y un camino que sólo lee `stderr` en verde se
queda sin la única frase que contesta qué pasó.

### Exit codes de `status`

| exit | situación base |
|---|---|
| 0 | `review` (+ `finish-conflict` si hay registro de finish) |
| 2 | `no-review` (+ `finish-pending` si `list` lo reporta) |
| 3 | `out-of-range` |
| otro / nil sin timeout | `error` |
| `timedOut` | `error`, con el mensaje de timeout |

---

## Mutaciones — argv exactos

| Acción | verbo | args |
|---|---|---|
| `startReview` | `start` | ver § intent |
| `continueReview` | `continue` | `[source]` |
| `saveReview` | `save` | `[]` |
| `abortReview` | `abort` | `[]` |
| `finishReview` | `finish` | `[]` o `["--onto-source"]` |
| `undoFinish` | `finish` | `["--abort"]`, y opcionalmente después `["--abort","--force"]` |
| `resumeFinish` | `finish` | `["--resume"]` o `["--resume","--onto-source"]` — **`--onto-source` sólo si el porcelain de la review lo reporta** (User Story 5, escenario 5) |
| `next` / `prev` | `next` \| `prev` | `[]` |
| `previewEdits` | `preview` | `[]` |
| `previewEditsStat` | `preview` | `["--stat"]` |
| `compareReview` | `compare` | flags de layout + `["--", lower, upper]` |
| `cleanReview` (una) | `clean` | `[source]` |
| `cleanReview` (keep-fixes) | `clean` | `["--keep-fixes", source]` |
| `discardFixes` | `clean` | `["--fixes-only", source]` |
| `discardAllFixes` | `clean` | `["--fixes-only"]` — **siempre sin rama**; por diseño de `clean` eso enumera sólo `review-fixes/*` y nunca toca una `review/*` viva |
| `cleanReview` (todas) | `clean` | `[]` |
| `forgetReview` saved | `forget` | `["--saved", source]` / `["--saved","--all"]` |
| `forgetReview` delta | `forget` | `["--delta", source]` / `["--delta","--all"]` / `["--delta","--stale"]` (**red**) |
| `forgetReview` draft | `forget` | `["--draft", …]` / `["--draft","--reviewed"]` |
| `setBase` | `config` | `["base", "--", name]` |
| `setRemote` | `config` | `["remote", "--", name]` |
| `walkthroughInit` | `walkthrough` | `["init"]` o `["init","--force"]` |
| `walkthroughBuild` | `walkthrough` | `["build"]` |
| `createGuide` | `walkthrough` | `["guide"]` o `["guide","--team"]` |
| `discardGuide` | `walkthrough` | `["guide","--delete"]` — sólo la propia; la compartida es un archivo trackeado y la CLI niega `--delete --team` |
| `startFromDraft` | `start` | como `start`, con la forma de lectura del borrador |

`discardAllFixes` **siempre** corre `--fixes-only`, incluso con la sesión cerrada: el argv no puede
depender de un dato que se relee en cada refresco, y un `clean <x>` que llegue tarde —la sesión
volvió a existir entre el refresco y el gesto— se llevaría puesta una review viva desde un control
que promete borrar una rama de ediciones.

### `start` intent → args

Orden fijo:

1. layout: *(vacío)* | `--keys` | `--step` | `--no-walk`
2. `--delta` si `range == delta`
3. `--local` | `--offline` si `source != remote`
4. `--`, branch

### Sondeos de config del asistente

```text
config --porcelain
config --porcelain -- <branch>
config --porcelain [--local|--offline] [--delta] -- <branch>
```

Siempre `class == Read` (nunca red).

El asistente **sólo ofrece las formas de lectura que la CLI reporta como viables** (registro `offer`)
y al terminar la última pregunta **arranca sin cartel de confirmación** — `startReview` no confirma,
y vale para los **dos** caminos que llegan al start: el asistente y `startFromDraft` (User Story 5,
escenario 2).

---

## Git de apoyo (no git-review)

Para el inventario de cambios y para resolver dónde vive el repositorio:

- ejecutable: `git` del `PATH` (el mismo que corre `git review`)
- `cwd` = el del proceso; UTF-8; clase `SupportGit` (30 s); buffer grande
- rango: `diff --name-status -z --no-renames HEAD`
- commit: `diff-tree -r -z --no-commit-id --name-status --root <sha>`
- ubicación: `rev-parse --git-dir --git-common-dir --show-toplevel` — **una sola invocación**, y la
  única fuente de las rutas de la vigilancia (FR-036). Sin `--path-format=absolute`, que es de git
  2.31 y el proyecto declara 2.23+.

---

## Herramientas del usuario (las cuatro acciones delegadas)

No son invocaciones de la CLI, pero son procesos y viven en el mismo invocador:

| Acción | Herramienta | Cómo |
|---|---|---|
| `openEntry`, `openChange` | `$EDITOR` | `tea.ExecProcess`, path **mostrable** |
| `previewEdits`, `compareReview` | `git difftool` → `$PAGER` → `less` | con el color de git |

`tea.ExecProcess` suspende el programa, le entrega el TTY al hijo y lo recupera al volver — y **al
volver dispara un refresco**, porque el revisor pudo haber editado y guardado adentro. Es el
equivalente en la TUI del `watched: on_save` que el canónico declara para el walkthrough y las
guías.

Un `$EDITOR` con argumentos (`"code -w"`, `"nvim -R"`) se parte con reglas de shell POSIX, no con un
split por espacios. Ausente o inexistente: el mensaje dice **qué no pasó**, no qué comando falló.

---

## Prohibiciones

1. Resolver o ejecutar el dispatcher por cuenta propia, en cualquier sistema operativo (FR-007).
2. Ofrecer un ajuste de ruta al dispatcher (FR-008).
3. Derivar la situación leyendo refs, `git config` de review o el working tree (FR-012).
4. Parsear el `stdout` humano de una mutación para decidir la situación (FR-013).
5. Reenviar el `stdout` de un verbo tal cual: termina en el comando del paso siguiente, que en el
   panel es una tecla o un control.
6. Encolar mutaciones. El lock es de profundidad 1 y la segunda se descarta con aviso.
7. Mandar `PathRef.Raw` a la pantalla o `PathRef.Display` a la CLI.
8. `--force` de undo como primera opción.
9. Leer o escribir cualquier clave `reviewworkflow.*` que no sea a través de un verbo. Y del otro
   lado de la frontera: **la CLI no lee ninguna clave `reviewui.*`** (FR-077).
10. Exportar `GIT_REVIEW_ADVICE` desde más de un lugar.
