# Research: 006-superficie-panel-completa

## Decisión 1 — Enmienda del criterio de admisión

**Decision**: Sustituir “tiene inversa en el panel” por “inversa **o**
confirmación modal que nombra el efecto” para mutaciones; solo lectura sin
modal.

**Rationale**: Es el mismo molde que `abort`/`save` en `005`. El usuario
aceptó confirmación como suficiente. Evita inventar undo de `clean`.

**Alternatives**: (a) mantener exclusión — rechazado por pedido explícito;
(b) undo stack propio en la extensión — viola “CLI es la verdad”.

## Decisión 2 — Orphans sin `git branch -D`

**Decision**: orphan saved → `forget --saved <src>`; orphan no saved →
`clean <src>`. Nunca `git branch -D`.

**Rationale**: `clean` ya borra `review/<src>` y `review-fixes/<src>` y refs
huérfanas; `forget --saved` limpia el saved. FR-006.

**Alternatives**: invocar git crudo — prohibido por frontera de `002`.

## Decisión 3 — Superficie de forget/clean en UI

**Decision**:

| Acción | UI |
|--------|-----|
| Discard saved (uno) | botón en fila inventario + palette |
| Discard orphan | botón en fila (reemplaza solo-texto) |
| Clean one source | palette; opcional en fila no-current |
| Clean all | palette |
| Forget delta one/all/stale | palette (picker de rama desde `candidate` o input del source del inventario) |
| Forget all saved | palette |

**Rationale**: el inventario ya tiene filas; all/stale son raros → palette.
No UI de dry-run.

## Decisión 4 — Preview: cómo mostrar sin alimentar view-model

**Decision**: invocar `preview` / `preview --stat`; mostrar `stdout` (+
`stderr` de advertencias) en un documento de solo lectura del editor
(`TextDocumentContentProvider` o documento untitled con language `diff`),
similar en espíritu a `whyContentProvider`. No parsear líneas para entries.

**Rationale**: FR-005 permite mostrar artefacto; prohíbe derivar estado.

**Alternatives**: OutputChannel (peor UX); multi-diff nativo reimplementando
el merge de finish (duplica lógica de la CLI).

## Decisión 5 — Compare: de dónde salen a y b

**Decision**: QuickPick de `candidate` (config porcelain) + ítem “Enter
commit-ish…” → `InputBox`. Layout como start (auto/step/no-walk). Confirmación
con frase resumen. Args: `compare` con flags y posicionales; usar `--` antes
de puntas que puedan parecer opciones si se pasan de forma que el verbo lo
requiera (misma disciplina que start).

**Rationale**: FR-016; no enumerar ramas con vscode.git.

## Decisión 6 — Walkthrough

**Decision**: comandos `walkthroughInit` y `walkthroughBuild`. Init: si el
archivo ya existe (detectado por fallo de CLI *o* por existencia del path
relativo al repo root vía fs solo para decidir si pedir --force — **cuidado**:
leer existencia del archivo en el working tree no es leer estado de review;
es el path fijo `.review/walkthrough.md`. Preferible: intentar init sin
force; si la CLI dice que existe, ofrecer reintentar con --force tras
confirmación. Así no se lee el repo “por izquierda” para metadata de review.

Build: sin confirmación fuerte (reescribe el sidecar que el autor está
editando; opcional confirmación suave “Rebuild walkthrough?”). Tras init
exitoso, `vscode.workspace.openTextDocument` + `showTextDocument` del path
`.review/walkthrough.md` bajo el root del repo (root de `vscode.git` /
RepositoryTarget — ya permitido).

**Rationale**: no parsear walkthrough; abrir archivo es UX de autor.

## Decisión 7 — ¿Porcelain nuevo?

**Decision**: no en el plan base. Targets de delta “una rama” se eligen de
candidatas o tipeando el source. Listar *todos* los markers sin rama se hace
con `forget --delta --all` (sin picker). Si más adelante se quiere UI de
lista de markers, se agrega registro al config porcelain.

**Rationale**: YAGNI; Assumptions de la spec.

## Decisión 8 — Timeouts / red

**Decision**: reutilizar clases de `invoke` de `005`: lectura (preview) 15s;
mutación local 120s; `forget --delta --stale` con `network: true` y 300s +
askpass neutralizado.

## Decisión 9 — Versión mínima CLI

**Decision**: no subir el mínimo salvo que un flag nuevo de CLI se introduzca.
Todos los verbos ya existen en la CLI actual del monorepo. Si el panel ya
declara un mínimo, se mantiene.
