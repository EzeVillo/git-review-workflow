# Contract: Superficie del plugin IntelliJ (paridad VS Code)

Superficie de producto del tool window y acciones. Implementación Swing;
semántica = extensión VS Code al 2026-08-08 (`package.json` + `panelModel` +
handlers).

## Tool window

| Propiedad | Valor |
|-----------|--------|
| Id | **`gitReview.walkthrough`** — mismo id que la view de VS Code. Decidido y estable en `plugin.xml`: un tool window id se persiste en el layout del usuario, así que no se renombra después. Si la validación de `plugin.xml` rechazara el punto en el id, la única alternativa admitida es `GitReviewWalkthrough` (T002 lo confirma al escribir el descriptor) |
| Ancla | left / tool window bar |
| Título | `git review` |
| Contenido | nativo; primer build de UI al **mostrar**, no al abrir proyecto |
| Refresh | coalescido; señales GitRepository + acción Refresh + post-mutación |

## Matriz situación × acciones habilitadas

`B` = busy bloquea. `R` = readonly bloquea finish.

**Esta tabla es un resumen legible; la fuente normativa es
`contracts/client-product-surface.yaml` (clave `actions`)**, que es lo que el
check de CI compara contra ambos clientes. Si divergen, gana el YAML y esta
tabla se corrige.

Dos superficies distintas, como en la extensión: el **panel** (contextual,
dibuja solo lo que aplica a la situación) y las **acciones globales** del
`ActionManager` (equivalente de la command palette: visibles con más
amplitud, pero degradan con un mensaje honesto cuando no hay datos). Donde
difieren, la celda lo dice.

| Acción | no-review | finish-pending | review | finish-conflict | out-of-range | error | cli-* |
|--------|-----------|----------------|--------|-----------------|--------------|-------|-------|
| Refresh | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Start | ✓ !B | ✓ !B | — | — | — | — | — |
| Set base/remote | ✓ !B panel+acción | ✓ !B acción | ✓ !B acción | ✓ !B acción | ✓ !B acción | ✓ !B acción* | ✓ !B acción |
| Continue (fila) | ✓ !B | — | — | — | — | — | — |
| Discard inventory (fila) | ✓ !B | — | — | — | — | — | — |
| Open entry/change/why/go-to | — | — | ✓ | ✓ | — | — | — |
| Open all changes | — | — | whole | whole | — | — | — |
| Next/Prev | — | — | ✓ !B | — | — | — | — |
| Finish | — | — | ✓ !B !R | — | — | — | — |
| Save | — | — | ✓ !B | — | — | — | — |
| Abort | — | — | ✓ !B | ✓ !B | — | — | — |
| Undo finish | — | ✓ !B | — | ✓ !B | — | — | — |
| Resume finish | — | — | — | ✓ !B | — | — | — |
| Preview (+stat) | — | — | ✓ !B | ✓ !B | — | — | — |
| Clean / Forget / Compare / Wt | ✓ !B | ✓ !B | ✓ !B | ✓ !B | ✓ !B | ✓ !B | — |
| Install CLI docs / copy npm | — | — | — | — | — | — | ✓ |
| Show CLI log | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

\* **Set base / Set remote** — paridad literal con la extensión, que las
expone en la palette con `when: !gitReview.busy` (todas las situaciones) pero
las **dibuja en el panel solo en `no-review`**: inline en el setup cuando
falta base, y en la sección plegada *Settings* cuando ya hay
(`panelHtml.ts` → `renderSetup` / `renderSettings`). El plugin hace lo mismo:

- **Panel**: solo en `no-review`. No se dibuja un botón de base durante una
  review, en `cli-*` ni en `error`.
- **Acción global**: registrada siempre; habilitada si no hay mutación en
  curso **y** hay `RepositoryTarget` único. Sin candidatas leídas (el caso
  típico en `cli-*`) degrada con el mismo mensaje que la extensión —
  `"No branches to pick a base from were found."` (canónico
  `strings.no_base_candidates`) — no con un fallo opaco.
- En `error` **sin cwd único** la acción se deshabilita: no hay repositorio
  donde escribir la config (FR-003). El resto de los `error` (timeout, fallo
  de lectura) sí la permiten.

Continue / Discard inventory **no** son acciones globales de ActionManager
siempre visibles: se disparan desde filas del inventario (como `when: false`
en palette de VS Code).

## Panel por situación (qué debe existir)

### cli-missing / cli-outdated

- Texto con **min version** desde superficie canónica
- Copy npm install | update
- Link “other install options” → docs
- Nota de reintento periódico si visible

### no-review + no base

- Setup only: set base (required), set remote
- Sin Start, sin inventario, sin footer de other actions engañoso

### no-review + base

- Inventario de reviews (orden CLI)
- Por fila: badges saved/current/orphan/finish; Continue si resumable; Discard
- Start primary
- Footer: Other actions / Settings / Support

### finish-pending

- Banner: edits en destino; Clean keep-fixes; Undo finish
- Sin inventario dibujado como lista principal (host usa branches internamente)

### review / finish-conflict

- Barra: mode, source, tip (abbrev en UI), position/total si cursor
- Notas: readonly, keysOnly, baseMoved, degraded, base (whole)
- walk: current entry + why (loading|present|absent|failed) + uncovered count/list
- step: current + subject/author si hay
- whole: file list + lastOpened mark + open all
- finish-conflict: banner undo/resume; navigationLocked (sin next/prev)
- Title actions: finish, save, abort, preview según matriz

### out-of-range / error

- Mensaje + “How to fix it” + stderr o mensaje fijo multi-root/timeout

## Protocolo UI → host (equivalente webview messages)

El panel Swing no usa postMessage; emite **intents** tipados al controller:

```text
Refresh | Start | Continue(index) | DiscardInventory(index)
| OpenEntry | OpenChange | OpenAll | ShowWhy | Next | Prev | GoTo
| Finish | Save | Abort | UndoFinish | ResumeFinish
| SetBase | SetRemote | Preview | PreviewStat
| Clean… | Forget… | Compare | WalkthroughInit | WalkthroughBuild
| CopyNpm(install|update) | OpenSupport(id) | ShowCliLog | OutOfRangeHelp
```

Índices de inventario se validan en el host contra `state.branches` actual
(nunca confiar en fila stale).

## Confirmaciones (copy en inglés, paridad)

| Acción | ¿Modal? | Tono |
|--------|---------|------|
| Abort | sí | destructivo (descarta uncommitted de la review) |
| Save | sí | suave |
| Continue | sí | mueve HEAD / restaura |
| Start | sí | confirma summary + argv |
| Finish | pick destino, no modal destructivo genérico | |
| Undo | sí; 2º si CLI pide --force | |
| Resume | no | |
| Compare | sí | |
| Walkthrough overwrite | sí si existe archivo | |
| Build | sí | |
| Housekeeping | sí según kind | |

Confirmaciones **fuera** del MutationLock (busy no cubre el tiempo del modal).

## Diff UX

| Acción | Comportamiento IntelliJ |
|--------|-------------------------|
| Open entry (walk/whole) | abrir VirtualFile WT; si falta → contenido HEAD |
| Open change (walk/whole) | DiffRequest HEAD vs WT o un solo lado A/D |
| Open entry/change (step) | chain o lista de diffs del commit |
| Open all (whole) | DiffRequestChain del rango |
| Why | editor o panel markdown/plain con texto why |

## Settings

| Key | Default | |
|-----|---------|--|
| `gitReview.path` | `""` | dispatcher |
| `gitReview.defaultSource` | `remote` | preselect wizard |

## Persistencia IDE

- `lastOpened` map branch→display (máx 20), solo whole
- settings de arriba

## Activación

- No CLI en project open sin tool window/acción
- Probe CLI ~10s solo cli-missing|outdated **y** tool window visible
