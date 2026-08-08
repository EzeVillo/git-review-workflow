# Data model: el layout del panel como dato

**Feature**: `010-panel-intellij-acciones`

El único tipo nuevo es la **disposición del panel**. No hay entidades
persistidas, ni estado propio, ni formato nuevo en disco: `PanelLayout` es una
proyección pura de `PanelModel`, que ya existe y no cambia.

```text
ReviewState  ──(existente)──►  PanelModel  ──(NUEVO: puro)──►  PanelLayout
   (porcelain de la CLI)         (qué mostrar)                  (cómo se ordena)
                                                                     │
                                        ┌────────────────────────────┴───────────┐
                                        ▼                                        ▼
                                 PanelRenderer (Swing)              PanelLayoutContractTest
                                 preview + tool window              (compara contra el YAML)
```

## PanelLayout

Raíz de la proyección. Vive en `domain/PanelLayout.kt`, sin `com.intellij`
(`checkDomainNoIntellij` lo verifica en cada build).

| Campo | Tipo | Qué es |
|---|---|---|
| `situation` | `Situation` | La situación que se está dibujando; se copia del modelo para que el layout sea autocontenido en los tests. |
| `blocks` | `List<Block>` | La secuencia del cuerpo, **en orden de arriba abajo**. El orden de la lista *es* el orden de la pantalla. |
| `titleActions` | `List<Control>` | La barra del tool window, en orden de izquierda a derecha. |
| `fillsHeight` | `Boolean` | Si el cuerpo estira y el pie queda anclado abajo. Sólo `true` en `no-review` con base configurada, igual que la clase `fills` de la extensión. |

## Block

Suma cerrada de los bloques que el panel sabe dibujar. Cada variante existe
porque la extensión dibuja algo distinto; no hay variantes "por si acaso".

| Variante | Campos | Corresponde a |
|---|---|---|
| `IdentityBar` | `mode`, `name`, `tip?`, `position?`, `total?`, `skeleton` | La barra de identidad de la review. |
| `Note` | `text` | Las notas de solo lectura / solo claves / base movida / degradado / base del rango. |
| `Paragraph` | `text`, `muted` | Texto corrido de los estados vacíos. |
| `Heading` | `text` | Los títulos de sección ("Reviews in this repository", "N files in this review"). |
| `Banner` | `paragraphs`, `row` | El aviso de finish pendiente y el de finish trabado, con su fila de controles adentro. |
| `CodeCommand` | `command`, `copy` | El comando de instalación con su control de copiar. |
| `EntryHead` | `position`, `identifier?`, `author?`, `badge?` | La cabecera de la entrada: número, sha y autor en step, y **una** marca. |
| `EntryTitle` | `text`, `muted` | El asunto (step) o el path (walk); `muted` para el commit sin asunto. |
| `Why` | `state`, `text?`, `uncovered` | El bloque de explicación en sus cuatro estados. |
| `Row` | `controls` | Fila horizontal de uno o dos controles que se reparten el ancho. |
| `FileRows` | `rows` | El listado de whole: una fila accionable por archivo. |
| `InventoryRows` | `rows` | El inventario: nombre, badges, meta y los controles de la fila. |
| `ToolsSection` | `title`, `blocks` | Sección plegable del pie. Anida bloques (párrafos y controles). |
| `Stderr` | `text` | El bloque de error crudo de la CLI. |
| `EmptyMessage` | `text`, `control?`, `stderr?` | El molde de estado vacío de la extensión (`empty()`). |
| `Skeleton` | `shape` | Los bloques de carga que reemplazan contenido conservando la silueta. |

**Regla de anidamiento**: sólo `Banner` y `ToolsSection` contienen otros
bloques, y sólo a un nivel. Un layout no puede anidar secciones dentro de
secciones — la extensión tampoco.

## Control

La unidad que la verificación compara entre clientes. Todas sus dimensiones
salen de un requisito del invariante rector.

| Campo | Tipo | Dimensión del invariante |
|---|---|---|
| `id` | `ControlId` | Qué acción ejecuta (corolario 1). |
| `label` | `String?` | Rótulo palabra por palabra; `null` sólo en controles de ícono (corolario 5). |
| `accessibleName` | `String` | Nombre para lectores de pantalla y tooltip; obligatorio cuando `label` es `null` (FR-035). |
| `emphasis` | `Emphasis` | `PRIMARY` / `SECONDARY` / `LINK` / `ICON` (corolario 3). |
| `enabled` | `Boolean` | Ya resuelto en el layout, no en el renderer (corolario 6). |
| `tooltip` | `String?` | El `title` del control en la extensión, cuando lo tiene. |
| `index` | `Int?` | La posición del ítem para los controles de fila (inventario y archivos). |

**Invariantes de construcción** (verificados por test):

1. `label == null` ⟹ `emphasis == ICON` y `accessibleName` no vacío.
2. Un `Row` tiene 1 o 2 controles; nunca 0, nunca 3.
3. Como máximo un control `PRIMARY` por situación.
4. `index != null` sólo en controles dentro de `FileRows` o `InventoryRows`.
5. Ningún `Control` con un `id` que no pertenezca a la situación según el
   canónico.

## ControlId

Espejo exacto de `PANEL_MESSAGES` de la extensión (22 entradas) más las cinco
de la barra de título. Se declara como enumeración cerrada: agregar un control
al panel es agregar una constante, y el test del canónico obliga a registrarlo.

**Cuerpo del panel (22)** — `openEntry`, `openChange`, `openAllChanges`,
`showWhy`, `next`, `prev`, `refresh`, `installCli`, `copyCliInstall`,
`outOfRangeHelp`, `continueReview`, `startReview`, `setBase`, `setRemote`,
`undoFinish`, `resumeFinish`, `discardInventory`, `cleanReview`,
`compareReview`, `walkthroughInit`, `walkthroughBuild`, `openSupport`.

**Barra del tool window (5)** — `refresh`, `finishReview`, `saveReview`,
`abortReview`, `previewEdits`.

**Fuera del panel, sólo en el menú del plugin (4)** — `goToEntry`,
`forgetReview`, `previewEditsStat`, `showCliLog`. No tienen `ControlId`: que no
se puedan nombrar es la garantía de que no se cuelen (FR-001, segunda mitad).

Tres de los 22 no son acciones del contrato y no llegan a la CLI:
`copyCliInstall` (portapapeles), `outOfRangeHelp` (reexpone `stderr`) y
`openSupport` (abre la URL del canónico).

## Emphasis

| Valor | Qué significa | Cómo se dibuja |
|---|---|---|
| `PRIMARY` | La acción principal de la pantalla | Botón de acción por defecto del tema |
| `SECONDARY` | El resto de los botones | Botón normal |
| `LINK` | Abre otra superficie, no actúa sobre ésta | Enlace del tema (`open in editor`, `Other install options`) |
| `ICON` | Sin rótulo visible | Botón de ícono con nombre accesible |

## Filas compuestas

```text
FileRow      { display, index, lastOpened }
InventoryRow { name, badges[], meta, controls[], helpTooltip? }
```

`badges` son los mismos de la extensión (`current`, `orphan`); `meta` es el
modo y, si está registrada, la posición. `helpTooltip` es el texto que explica
por qué una fila no ofrece ningún verbo, y sólo se completa cuando
`controls` está vacío.

## Mapeo a las acciones existentes

El panel no implementa comportamiento: despacha. Cada `ControlId` rutea a lo que
ya existe en `ui/actions/ReviewActions.kt` y `host/MutationActions.kt`.

| ControlId | Destino | Nota |
|---|---|---|
| `next` / `prev` | `MutationActions.runNextPrev` | — |
| `openEntry` / `openChange` / `openAllChanges` | `OpenEntryActions` | — |
| `showWhy` | `ShowWhyAction` | — |
| `startReview` | `StartWizard` | — |
| `continueReview` | `MutationActions.runSimple("continueReview", …)` | **Por índice**: sin selector, la fila ya identifica la review. |
| `discardInventory` | `MutationActions.runHousekeeping` | **Por índice**: hoy la acción del menú pide el nombre escrito a mano (research §7). |
| `cleanReview` | `MutationActions.runHousekeeping` | En `finish-pending`, resuelto desde el modelo: sin selector de tipo. |
| `undoFinish` / `resumeFinish` | acciones existentes | — |
| `setBase` / `setRemote` | acciones existentes | Conservan su selector: la extensión también abre un *quick pick*. |
| `compareReview` / `walkthroughInit` / `walkthroughBuild` | acciones existentes | — |
| `installCli` | `InstallCliAction` | — |
| `copyCliInstall` | portapapeles + confirmación transitoria | Nuevo, sin CLI de por medio. |
| `outOfRangeHelp` | muestra el `stderr` del modelo | Nuevo, sin CLI de por medio. |
| `openSupport` | abre `support.star_url` del canónico | Nuevo, sin CLI de por medio. |
| `refresh` | `GitReviewService.scheduleRefresh` | Sólo en la barra de título. |
| `finishReview` / `saveReview` / `abortReview` / `previewEdits` | acciones existentes | Sólo en la barra de título, con su condición. |

**Confirmaciones**: las que ya pide el plugin se conservan tal cual; el control
del panel no agrega ni saca diálogos (FR-032).

## Qué NO entra en el modelo

- **El estado de apertura de las secciones del pie** y **los tiempos del
  esqueleto**: son del componente, no del review (FR-034, research §6 y §8).
- **El último archivo abierto**: ya vive en el modelo (`lastOpened`); el layout
  sólo lo refleja como marca de fila.
- **Cualquier dato derivado de git**: el layout no consulta nada; recibe el
  `PanelModel` y devuelve estructura.
