# Data Model: El borrador del revisor, escrito por un agente

**Feature**: `012-prompt-agente-draft` | **Fase**: 1 | **Fecha**: 2026-08-19

Ninguna entidad nueva persiste estado fuera del archivo del walkthrough. Esta
feature agrega **una pieza al formato** y **tres proyecciones** de datos que ya
existen.

---

## Entidad: Bloque de instrucciones (`git-review-range`)

La única pieza nueva del formato de walkthrough desde `> key` y `> at: `.

### Forma

Un comentario HTML, en el **preámbulo** (antes de la primera entrada), cuya
primera línea empieza exactamente con `<!-- git-review-range:`.

```markdown
# Walkthrough

<!-- git-review-range: what this reading order covers, and how to see it.
     ...
-->

## Heads-up

...prosa del autor...

## 1. src/api/orders.ts
```

### Reglas

| Regla | Valor |
| --- | --- |
| Cantidad | Cero o una por archivo. La segunda y siguientes se ignoran. |
| Ubicación | En el preámbulo. Un bloque después de la primera entrada no se reconoce. |
| Reconocimiento | `index($0, "<!-- git-review-range:") == 1` en la línea de apertura. |
| Cierre | El `-->` del comentario, en su línea o en una posterior. |
| Al reescribir (`build`, `draft --build`) | Se **regenera** desde el rango que esa corrida validó, entre el encabezado `# Walkthrough` y el preámbulo. El bloque entrante se consume para que no se duplique ni se cuele al preámbulo. Con `--check` no se escribe nada. |
| Al leer (`start`, `compare`) | Se **descarta**: `walk_preamble` filtra todo comentario, sin cambios. `status --why` **no pasa por `walk_preamble`** (nunca muestra el preámbulo), así que ahí el bloque tampoco se ve, pero por otro motivo. |
| En la validación | **Neutro**. Su presencia o ausencia no cambia el resultado de ninguna de las ocho reglas. |
| En el PR | No se renderiza: es un comentario HTML. |
| Borrado a mano | Legal. El borrador sigue siendo válido y legible; sólo se pierde poder reanotarlo sin volver a pedir el esqueleto. |

### Contenido

Fijado byte a byte en
[`contracts/walkthrough-prompt-block.md`](contracts/walkthrough-prompt-block.md).
Tres partes:

1. **El rango**, con los dos extremos resueltos a objetos concretos.
2. **La relación del árbol de trabajo con el PR**, según dónde se generó.
3. **Los comandos** para ver, de cualquier archivo listado, el cambio que el PR
   le hace y su contenido resultante.

### Los dos extremos

| | `init` (autor) | `draft` (revisor) |
| --- | --- | --- |
| `tip` | `git rev-parse HEAD` | SHA de `refs/remotes/<remote>/<branch>` o `refs/heads/<branch>` |
| `lower` | `fold_lower(mb, baseref, tip)` — siempre un **commit** (a veces sintético y sin referenciar) | `resolve_lower_bound(start, baseref, tip)` — un **commit** o un **tree OID** sin referenciar |

Los dos son objetos, no nombres de refs: el bloque es una foto del momento en
que se generó. La foto no envejece, porque toda reescritura la vuelve a tomar
(§ *Al reescribir*); y si además cambió el conjunto de paths, la validación lo
detecta como deriva, que es el mecanismo que ya existe.

**Consecuencia dura para el contenido**: **ninguna** línea del bloque puede usar
`<lower>..<tip>`, ni nombrar `git log` / `rev-list` / `shortlog` / `range-diff`.
Dos motivos independientes, medidos en [research.md](research.md) § Hallazgo 0:

- `git diff <a>..<b>` con dos SHAs completos y sin `--` muere en **Windows** con
  cwd profundo (`failed to stat ...: Filename too long`, exit 128), **con
  cualquier tipo de extremo** — también con dos commits, o sea también en `init`.
- Con `lower` de tipo tree, los comandos de historia imprimen **el repositorio
  entero con exit 0**, en silencio.

Lo que sí funciona con un `lower` de cualquier tipo, y es lo que el bloque usa:
`git diff <lower> <tip>` en forma de dos argumentos, y `git show <rev>:<path>`.

### Campo: con qué flags se generó

Una línea del bloque registra los flags de origen y rango normalizados
(`--local` | `--offline`, luego `--delta`) o `(defaults)`. Es la **única** casa
de ese dato —no hay clave de config— para que nazca y muera con el archivo. El
registro `draft` de `config --porcelain` lo emite como campos, y de ahí lo toma
*Validate and start* del panel para no invocar `start` con un rango distinto del
que el borrador cubre. Ver [research.md](research.md) § Decisión 13.

---

## Entidad: Progreso del borrador

Un par de enteros derivado del archivo, **nunca persistido**.

| Campo | Definición |
| --- | --- |
| `annotated` | Entradas con **posición** (`## N.`, `N` numérico) **y** *why* resuelto |
| `total` | **Todos** los encabezados de entrada del archivo (`## N.` y `## ?.`) |

*Why* resuelto = el cuerpo tiene al menos una línea no vacía que no es `> key`
ni `> at: `, **y** no tiene ninguna línea que empiece con `<!-- why`.

### Invariantes

- Un borrador recién generado marca `0/N`, con `N` los archivos del rango
  (SC-013): todas sus entradas son `## ?.` con el placeholder intacto.
- `annotated` nunca llega a `total` mientras quede una entrada a la que le falte
  cualquiera de las dos marcas (SC-013).
- Se cuenta **sobre el archivo**, sin cruzarlo con el rango (FR-022). Un
  borrador que quedó fuera de rango informa su avance igual; el desajuste es
  asunto de la validación.
- `annotated == total` **no** promete que `--build` vaya a pasar: siguen
  existiendo duplicados, marcadores con valor y deriva.

### Cómo se calcula

`walk_draft_progress` — **un solo `awk`** sobre todos los archivos de borrador a
la vez, con normalización de BOM/CR incorporada y cierre por archivo con
`FNR == 1` (no `ENDFILE`, que es extensión de gawk). Emite
`<ruta><TAB><annotated><TAB><total>`, una línea por archivo **que tenía
contenido**.

**La enumeración manda; `awk` sólo cuenta.** La lista de borradores y sus `<src>`
salen de `walk_draft_list`; el llamador correlaciona por ruta y lo que `awk` no
reportó cae a `0 0`. El sentido de la correlación no es un detalle de estilo:
`awk` no ve archivos, ve contenidos, y de ahí salen dos casos que la enumeración
resuelve sin ninguna regla especial.

- **Cero borradores ⇒ `walk_draft_progress` no se invoca.** `awk` sin argumentos
  de archivo lee la entrada estándar y **se cuelga**. `config --porcelain` corre
  en cada refresco del panel y a mano en una terminal: un cuelgue en el caso más
  común —repositorio sin borradores— violaría SC-005. Sin borradores tampoco se
  resuelve el gitdir absoluto: **cero procesos**.
- **Un borrador vacío no produce ninguna línea.** `awk` no ejecuta ninguna regla
  para un archivo de cero bytes ni le asigna `FILENAME`. Pero tiene que
  reportarse igual, con `0` de `0`: es custodia —hay que poder abrirlo y
  descartarlo— y es el estado exacto en que queda uno recién creado con
  `--stdout` y todavía sin instalar. Cae del `0 0` de la correlación.

Por eso `awk` emite la **ruta** y no `<src>`: recuperar `<src>` desde `FILENAME`
obligaría a pelar el prefijo del gitdir y el `.md` dentro del `awk`, con `<src>`
conteniendo `/`. El llamador ya tiene el `<src>` de la enumeración; no hace falta
derivarlo dos veces.

---

## Entidad: Borrador suelto (proyección)

«Suelto» = existe en el namespace **activo** (`<gitdir>/review-walkthrough/`).

| Campo | Origen |
| --- | --- |
| `src` | El nombre de archivo, sin `.md`, con los subdirectorios como `/` (`walk_draft_list`) |
| `path` | `<gitdir absoluto>/review-walkthrough/<src>.md` |
| `annotated` / `total` | `walk_draft_progress` |

**Un borrador de una review pausada nunca es un borrador suelto**, y no por una
regla nueva: `save` lo movió a `review-saved-walkthrough/`, que
`walk_draft_list` no recorre. FR-024 y SC-012 se cumplen por la separación de
namespaces que 011 ya construyó.

---

## Registros porcelain (delta)

Los tres son aditivos. Detalle en
[`contracts/config-porcelain-drafts.md`](contracts/config-porcelain-drafts.md) y
[`contracts/porcelain-draft-custody.md`](contracts/porcelain-draft-custody.md).

| Verbo | Registro | Forma | Cardinalidad |
| --- | --- | --- | --- |
| `config --porcelain` | `draft` | `draft<TAB><src><TAB><path><TAB><annotated><TAB><total>` | 0..N, uno por borrador suelto |
| `status --porcelain` | `draft` | `draft<TAB><path>` — **campo agregado** al registro de presencia de 011 | 0..1 |
| `list --porcelain` | `branch-draft` | `branch-draft<TAB><branch>` | 0..1 por fila `branch` |

El `draft` de `config` y el `draft` de `status` comparten etiqueta y **no
colisionan**: son verbos distintos con gramáticas de registro propias, igual que
`finish` significa cosas distintas en `status` y en `list`.

---

## Modelo del cliente (delta)

### `PanelDraft`

Proyección plana, una por registro `draft` de `config --porcelain`. **Nada de
esto se deriva**: cada campo viene tal cual de la CLI (SC-008).

| Campo | Tipo | Nota |
| --- | --- | --- |
| `branch` | `string` | La rama a la que pertenece el borrador |
| `path` | `string` | Ruta absoluta; el cliente la abre, nunca la arma |
| `annotated` | `number` | |
| `total` | `number` | |

### `PanelModel`

| Campo | Cuándo |
| --- | --- |
| `drafts: PanelDraft[]` | Poblado **sólo** con `situation === "no-review"`; array vacío en cualquier otra. Es la misma regla que `reviews`. |

`PanelModel.draft: boolean` (011, la review corre sobre un borrador) **no
cambia**: sigue siendo el registro `draft` de `status --porcelain`, leído como
presencia. Su campo nuevo de ruta se guarda aparte (`draftPath?: string`) y no
altera el booleano.

### Estado de la review (config por rama)

**Ninguna clave nueva.** `reviewdraft`, `reviewwalkfromdraft`,
`reviewdraftfiled` y los dos guards de metadata de `finish` quedan exactamente
como los dejó 011. El bloque de instrucciones vive dentro del archivo y el
progreso se cuenta al vuelo, así que no hay nada que persistir ni que pueda
desincronizarse.
