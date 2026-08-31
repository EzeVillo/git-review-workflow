# Data Model: 015-cliente-tui

Modelo de dominio de la TUI. Vive en `tui/internal/domain/`, **sin** bubbletea, lipgloss, bubbles,
fsnotify ni `os/exec` (FR-045, FR-075). Alineado al mismo porcelain que consumen
`vscode-extension/src/cli/*`, el `domain` de JetBrains y `GitReview.Domain` de Visual Studio: los
campos son los mismos, el parser es el cuarto.

## Situation

```text
cli-missing | cli-outdated | no-review | finish-pending
| review | finish-conflict | out-of-range | error
```

Más **`waiting`**, que **no es una situación**: es el valor inicial y sólo existe antes del primer
veredicto. Se dibuja `waiting_text` y nada más. Las tres situaciones que son respuestas sobre el
entorno (`cli-missing`, `cli-outdated`, `error`) **no se repintan de memoria**: una lectura nueva
las vuelve a derivar o las reemplaza.

### Derivación

Idéntica a la de los otros tres:

```text
sin repositorio en el cwd            → error (copy propia, ver per_client_strings)
--version falla / exit ≠ 0           → cli-missing
versión < mínimo o formato inválido  → cli-outdated
status --porcelain:
  exit 0 + registro de finish conflict → finish-conflict
  exit 0                               → review
  exit 2 + list reporta finish pending → finish-pending
  exit 2                               → no-review
  exit 3                               → out-of-range
  timeout / otro                       → error   (un TIMEOUT NO es cli-missing)
```

`isReviewReadable` = `review | finish-conflict`. `next`/`prev` sólo con `situation == review`.

## PathRef

| Campo | Uso |
|-------|-----|
| `Raw` | bytes tal cual los emitió porcelain; **lo único** que vuelve a la CLI (`status --why <raw>`) |
| `Display` | des-entrecomillado; a pantalla, al `$EDITOR` y a cualquier `stat()` |

Es un `struct` de dos strings, comparable. La regla es la de siempre y acá muerde más, porque el
mismo string pasa por un terminal: **nunca** se manda `Display` a la CLI ni `Raw` a la pantalla.

## StateRecord (status --porcelain)

| Campo | whole | step | walk |
|-------|-------|------|------|
| branch, source, tip | ✓ | ✓ | ✓ |
| mode | whole | step | walk |
| walkthrough | none/applied/degraded | none | applied/degraded… |
| position, total, recorded | — | ✓ | ✓ |
| current | — | SHA corto | PathRef |
| essential | — | — | en state y en entry |

Opcionales de status: `base` (whole), `finish{conflict,onto}`, `readonly`, `keysOnly`, `draft` (de
presencia).

## EntryRecord

| Campo | whole | step | walk |
|-------|-------|------|------|
| position | ✓ | ✓ | ✓ |
| id | PathRef | SHA | PathRef |
| essential / annotated | — | — | ✓ |
| banked | — | ✓ | — |

Mapas opcionales de step: `subjects`, `authors` por posición.

## Tolerancia del parser (FR-015)

Las tres formas ya establecidas, y **son requisito, no estilo**:

1. **campo libre al final** del registro — el último campo puede contener tabs y no se parte;
2. **no asumir cantidad de campos** — un registro con más campos de los conocidos se lee igual;
3. **ignorar registros desconocidos** — un tipo de registro que esta versión no conoce se saltea sin
   error y sin nota.

En Go eso es `strings.SplitN(line, "\t", n)` con `n` = cantidad de campos conocidos, y un `switch`
con `default:` vacío sobre el tipo de registro. Los fixtures salen de `tests/porcelain-bytes.bats`,
que es donde el emisor ya está gateado contra bytes hostiles.

## EffectiveConfig / candidates / remotes / delta / offer / draft / guide / walkthrough / fixes

Parse de `config --porcelain`, con los registros que la CLI emite hoy:

- `base` (se omite si no está seteada), `remote` (default `origin`)
- `candidate`, `remote-candidate`, `delta`, `offer` (walk|keys|step|whole × recommended|available)
- `draft` — **sólo cuando hay**; trae el path, el par annotated/total y el estado
- `guide` — **siempre las dos filas**, exista o no el archivo
- `walkthrough` — **siempre**, con su rama, su estado y su par de progreso
- `fixes` — una por rama `review-fixes/*`, con su badge

Reglas: `list` y `config` se invocan **sólo** en `no-review` / `finish-pending`; que fallen no cambia
la situación.

## BranchRecord (list --porcelain)

`name`, `saved`, `current`, `orphan`, `mode?`, `position?`, `total?`, `finish?{pending|conflict, onto}`,
`branch-draft?`.

`sourceOf(name)` quita el prefijo `review-saved/` o `review/`.

## ReviewState

Agregado en memoria tras una lectura. Es lo único que la TUI sabe del repositorio, y **todo** salió
de porcelain (FR-012):

```text
Situation
StateRecord?, Entries[], Branches[]
Config?, Candidates?, Remotes?
Subjects?, Authors?, Base?, Finish?, Readonly?, KeysOnly?
Drafts[], Guides[2], Walkthrough?, Fixes[]
Stderr?   (en las situaciones de fallo)
```

## PanelModel

Proyección plana de qué se dibuja, sin nada del dibujo. **Comparable por valor**: sin mapas, sin
slices, sin punteros. Lo variable —las filas— viaja ya proyectado en campos de string. Ver
`research.md` § Decisión 4: de esa propiedad depende SC-004.

- `situation`, `busy`, `repoLabel?`
- inventario, `pendingFinish?`, `noBaseConfigured`, `configuredBase?`, `configuredRemote?`
- `mode`, `branch`, `source`, `tip`, `base?`, `position`, `total`, `baseMoved`, `atFirst`, `atLast`
- `navigationLocked`, `degraded`, `readonly`, `keysOnly`
- `current?`, `entryCount`, `files`, `why?`
- filas del pie: walkthrough, dos guías, borradores frescos, borradores gastados, fixes
- notas derivadas (sólo presentación)
- **`mouseEnabled`** — estado del reporte de mouse, visible en el panel (FR-067). Es el único campo
  del modelo que no sale de porcelain, y no es estado del repositorio: es del terminal.

**Dentro de una review, `PanelModel` no lleva ninguna `tools_section`** (FR-023). No es que no se
dibuje: no se proyecta. El proyector es el punto donde eso se afirma, y el test de contrato de
layout lo verifica ahí.

## Viewport

`rows`, `cols` y las capacidades del terminal: `color` (apagado por `NO_COLOR`), `glyphs`
(`unicode | ascii`, decidido por locale/codepage al arrancar), `mouse` (lo que el terminal entrega).
Entra por `tea.WindowSizeMsg` y por el sondeo de arranque; **nunca** se consulta desde el dominio: se
le pasa al renderer junto al `PanelModel`.

`View(PanelModel, Viewport) -> (frame string, HitMap)` es **pura**. La `HitMap` es lo que hace que
el mouse no adivine coordenadas: cada control dibujado deja su rectángulo, y `MouseMsg` se resuelve
contra eso. Sin `HitMap` no hay forma honesta de escribir el test "sólo con el mouse" de SC-015.

## ReviewIntent

Las elecciones del asistente antes de materializar el argv:

- `branch`, `source: remote | local | offline`, `range: full | delta`,
  `layout: walk | keys | step | whole`

`IntentToArgs` produce, en orden fijo: `[flags de layout] [--delta] [--local|--offline] -- <branch>`
(walk sin flag; keys `--keys`; step `--step`; whole `--no-walk`). El origen preseleccionado sale de
`reviewui.startsource` cuando está (FR-061).

## StateToken

Huella `{branch?, tip?, situation}` capturada al abrir la confirmación y **revalidada adentro del
lock** antes del spawn. Es lo que impide mutar sobre datos viejos cuando el estado cambió entre el
clic y el "sí" — y en una TUI con vigilancia esa ventana es más real que en un IDE, porque el panel
puede haberse repintado mientras el overlay estaba abierto.

## InvocationClass

| Clase | Timeout | Verbos |
|-------|---------|--------|
| `Read` | 15 s | `status`, `list`, `config` (lecturas **y** escrituras de config), `--version` |
| `LocalMutation` | 120 s | `finish`, `save`, `abort`, `continue`, `next`, `prev`, `clean`, `forget`, `compare`, `walkthrough`, `preview` |
| `Network` | 300 s | `start`; `forget` si los args traen `--stale` |
| `SupportGit` | 30 s | el git de apoyo (`diff --name-status`, `diff-tree`, `rev-parse`), que no es git-review |

Verbo desconocido → `Read`, la misma regla que `invoke.ts`. Al vencer: matar el proceso (árbol,
best-effort) y devolver `timedOut=true` con `exitCode=nil` — **un timeout no es una CLI ausente**
(edge case de la spec, escenario 5 de la User Story 2).

## WatchSet

El conjunto de **directorios** vigilados. Se deriva de:
- lo que git contesta (`--git-dir` y `--git-common-dir`, distinguidos: un worktree enlazado comparte
  el común), y
- **los paths que la CLI ya reportó** para los borradores (FR-036) — nunca rearmados del layout del
  gitdir.

Se **rehace, no se recorre en vivo**, y sólo cuando cambia. Está **indexado por directorio**: dos
raíces que resuelven al mismo lugar son una entrada con la **unión** de sus filtros, que es lo que
pasa con `<git-dir>` y `<git-common-dir>` fuera de un worktree enlazado. Estructura, reglas de
cierre, presupuesto y las seis raíces: [contracts/refresh.md](./contracts/refresh.md).

## RefreshTrigger

```text
Action | Watch | Focus | Key
```

Decide **una sola cosa**: si el refresco se suprime por el lock de mutación. Sólo `Watch` se suprime;
`Key` nunca (FR-038: disponible en las ocho situaciones), `Focus` tampoco, `Action` es el refresco
propio de la mutación.

## MutationLock

Profundidad **1**. Si hay una mutación en curso, la segunda **se descarta con aviso**, no se encola
(User Story 5, escenario 6). Lleva además la **ventana de silencio** que hace que un `finish` repinte
una vez y no cinco: ver `contracts/refresh.md` § El lock y la ventana.

## KeyBinding

Par `tecla → acción | movimiento`, **declarado en el canónico** (`keymap:`) y no sólo en el código
(FR-041). El dominio responde desde un único mapa; la barra de teclas se dibuja de ese mismo mapa,
así que una tecla que existe y no se muestra es imposible por construcción.

Reservas duras: **`n` y `p` son el cursor de la review** (`git review next` / `prev`), nunca navegar
la lista; `j`/`k` y las flechas mueven la fila enfocada **sin** tocar el cursor de la CLI.

## Invocation

| Campo | Notas |
|-------|-------|
| `verb` | o `--version` |
| `args` | lista, sin shell |
| `cwd` | el del proceso; no hay picker ni ambigüedad multi-root |
| `class` | define timeout y entorno |
| `env` | siempre `GIT_REVIEW_ADVICE=0`; en clase red, además el anti-prompt |

Cada start/end deja una entrada en el **registro de invocaciones**: comando, cwd, duración, exit,
`timedOut`, stderr. Vive en memoria (FR-078), es lo que dibuja `showCliLog`, y es lo que hace
medible SC-002 ("cero procesos por minuto en reposo").

## Transiciones relevantes

```text
no-review --start ok--> review
review --save--> no-review (queda saved en list)
review --abort--> no-review
review --finish (con ediciones)--> finish-pending
review --finish (sin ediciones)--> no-review (+ posible delta)
finish-pending --undo--> review | no-review
finish-conflict --resume/abort/undo--> …
review --next/prev--> review (mismo modo, position ±1)
```
