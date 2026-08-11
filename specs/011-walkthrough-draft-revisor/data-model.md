# Data Model: Walkthrough del revisor (draft local)

**Feature**: `011-walkthrough-draft-revisor` | **Fase**: 1 | **Fecha**: 2026-08-09

## Entidad: Borrador de walkthrough (draft)

Orden de lectura escrito por el revisor para una rama bajo review.

### Identidad y ubicación

| Campo               | Valor                                                                                                                   |
|---------------------|-------------------------------------------------------------------------------------------------------------------------|
| Identidad           | La rama de origen (`<src>`). Uno por rama, por working tree.                                                            |
| Ubicación (activo)  | `<gitdir>/review-walkthrough/<src>.md`                                                                                  |
| Ubicación (pausado) | `<gitdir>/review-saved-walkthrough/<src>.md`                                                                            |
| `<gitdir>`          | `git rev-parse --git-dir` — el del working tree, así que cada `git worktree` tiene el suyo                              |
| Nombres con `/`     | Se materializan como subdirectorios (`feature/checkout` → `review-walkthrough/feature/checkout.md`), igual que las refs |

No hay índice ni registro paralelo: la existencia del archivo **es** el estado.
Esto evita cualquier posibilidad de desincronización entre un registro y el dato.

### Formato

Idéntico al del walkthrough del autor, sin excepciones ni campos extra:

- Preámbulo (`## Heads-up` y todo lo previo a la primera entrada).
- Entradas `## N. <path>` con su cuerpo (*why*).
- Marcador reservado `> key` como primera línea del cuerpo.

Que el formato sea el mismo es lo que permite reusar el lector, el validador y
el renumerado sin ramificar por origen. También significa que un borrador se
puede copiar a mano al sidecar del PR si alguna vez se quiere — no es una
capacidad de esta feature, pero tampoco queda cerrada.

### Reglas de validación

Las mismas de `walkthrough build`, aplicadas contra el rango de la rama
indicada en vez de contra `base..HEAD`:

| Regla                                                        | Efecto                           |
|--------------------------------------------------------------|----------------------------------|
| Entradas sin numerar (`## ?. `)                              | Rechazo                          |
| Placeholders `<!-- why` sin reemplazar                       | Rechazo                          |
| Placeholder de heads-up sin reemplazar (en el preámbulo)     | Rechazo                          |
| Encabezado casi-entrada mal formado                          | Rechazo, nombrando línea y texto |
| `> key` con valor                                            | Rechazo                          |
| Rutas duplicadas                                             | Rechazo                          |
| Drift contra el rango (falta o sobra un path)                | Rechazo, nombrando ambos lados   |
| Todas las entradas marcadas `key`, o ninguna con ≥6 entradas | Nota, nunca rechazo              |

En rechazo no se escribe nada: el borrador queda como estaba.

### Transiciones de estado

```text
                    (no existe)
                         │
                         │  draft <branch>
                         ▼
                  ┌─────────────┐
                  │  incompleto │◄──── el revisor edita ────┐
                  └─────────────┘                           │
                         │                                  │
                         │  draft --build                   │
                         ├──── rechazo ─────────────────────┘
                         │
                         │  aceptado (ordenado y renumerado 1..N)
                         ▼
                  ┌─────────────┐
                  │   validado  │
                  └─────────────┘
                         │
                         │  start <branch>  ──►  review en modo walk (draft)
                         │
      ┌──────────────────┼──────────────────┬─────────────────────┐
      │ save             │ clean / abort    │ finish              │ forget --draft
      ▼                  ▼                  ▼                     ▼
  (pausado)        (sigue existiendo) (sigue existiendo)     (eliminado)
                                                              forget --saved
                                                              (el pausado)
```

Notas sobre las transiciones:

- **Legible sin validar**: el estado *incompleto* ya es legible por la review
  (el orden se deriva de los números escritos). `--build` es control de calidad,
  no compuerta. Un borrador a medio anotar entra en walk y las entradas sin
  cuerpo simplemente no muestran *why*.
- **`save` mueve, no copia**: no pueden coexistir un borrador activo y uno
  pausado para la misma rama.
- **`continue`** hace el movimiento inverso antes de reconstruir el estado de la
  review, de modo que la lectura ya encuentra el borrador en su lugar — pero
  **después** de las guardas que todavía pueden abortar. Espejo exacto en `save`,
  donde el movimiento es el último paso: un `mv` a mitad de camino dejaba el
  archivo en un namespace sin dueño (activo con la review pausada, o guardado sin
  review guardada que lo reclamara).
- **`clean`** no toca ningún borrador, en ninguno de los dos namespaces. Un
  borrador es prosa escrita a mano que sobrevive a la review para la que se
  escribió, así que sigue la regla de los otros dos estados persistentes del
  proyecto (los marcadores de `--delta` y las reviews guardadas): `clean` borra
  ramas y refs de sesión, `forget` descarta lo que las sobrevive. Se borra con
  **`forget --draft <rama> | --all`**. Ver la revisión de la Decisión 4 en
  [research.md](research.md).
- **`reviewdraft`** (`branch.review/<x>.reviewdraft`) registra **dónde** vive el
  borrador de la review — la rama del borrador, que no siempre es el
  `reviewsource`: un `compare develop origin/feature/x` es la review de
  `origin/feature/x` y el borrador es de `feature/x`, porque el borrador es de la
  rama y no del ref con el que la nombraste. La escriben `start` y `compare` al
  crear la review, **en todos los modos y exista o no un borrador todavía**: la
  pregunta que contesta es «¿dónde iría el mío?», que es la que necesitan tanto un
  borrador escrito a mitad de review como la custodia en `whole`/`step`. La lee
  un único punto, `walk_review_draft_src`, y de ahí los dos cargadores (para fijar
  el contexto), `list` (para el `(draft)`), `save`/`continue` (para mover el
  archivo correcto), `forget` y `walkthrough draft` (para escribirlo donde se lo
  va a buscar). **No** es una clave walk: existe en todos los modos, así que el
  guard de metadata de `finish` no la incluye.
- **`reviewwalkfromdraft`** (`= 1`) registra que el orden que se está caminando
  salió de ese borrador. Un flag y no un nombre —el nombre ya está arriba—,
  porque es lo único que no se puede recalcular una vez que el archivo no está:
  lo usa `walk_range_error` para distinguir un borrador borrado de un
  `git commit` encima de la review. Lo escriben `start`/`compare` sólo cuando
  abren sobre un borrador, y sí es una clave walk como las demás: la copian
  `save`/`continue` y la cubre el guard de metadata de `finish`.
- **`finish`** no lo toca: el borrador no es una edición del revisor y no puede
  aparecer en `review-fixes/`. Sobrevive para una re-review con `--delta`.

## Entidad: Walkthrough del autor (sidecar)

Sin cambios. `.review/walkthrough.md` commiteado en el PR, leído del tip. Su
único cambio de estatus es de **precedencia**: pasa a ser la segunda opción
cuando existe un borrador del revisor para esa rama.

## Relación entre ambos: precedencia

Un único punto de resolución, en `walk_read`:

```text
¿hay <gitdir>/review-walkthrough/<src>.md ?
   sí  → ese es el walkthrough vigente          (origen: draft)
   no  → ¿hay <tip>:.review/walkthrough.md ?
            sí → ese es el walkthrough vigente  (origen: autor)
            no → no hay walkthrough             (la review va en whole)
```

`<src>` viene de la variable de contexto que fija `walk_use_draft`; cuando no
está fijada, la resolución es la actual (sólo sidecar), que es lo que mantiene
el comportamiento intacto para el autor.

**Consecuencia deliberada**: si existen los dos, manda el del revisor, y la
review queda marcada como *draft* mientras dure. El del autor no se modifica ni
se pierde; vuelve a regir en cuanto el borrador desaparece.

## Entidad: Oferta de lectura (`offer`)

Registro existente de `config --porcelain`, con dos ids nuevos:

| id             | Se emite cuando                                                                        | Rank          |
|----------------|----------------------------------------------------------------------------------------|---------------|
| `walk`         | *(sin cambios)* hay walkthrough vigente con ≥1 entrada en rango                        | `recommended` |
| `keys`         | *(sin cambios)* se emite `walk` y hay ≥1 entrada `> key` en rango                      | `available`   |
| `draft`        | **no** hay borrador para `<src>` **y** el tip no trae walkthrough del autor utilizable | `available`   |
| `draft-resume` | hay borrador para `<src>`                                                              | `available`   |
| `step`         | *(sin cambios)* tip y lower resolubles                                                 | `available`   |
| `whole`        | *(sin cambios)* tip y lower resolubles                                                 | `available`   |

`draft` y `draft-resume` son mutuamente excluyentes. Orden de emisión estable:
`walk`, `keys`, `draft`/`draft-resume`, `step`, `whole`.

Nótese que cuando hay borrador se emiten **`walk` y `draft-resume` a la vez**:
el borrador ya es legible, y a la vez se puede seguir completando.

## Estado de la review (config por rama)

Ninguna clave nueva. El modo sigue siendo `walk` y el cursor sigue viviendo en
`reviewwalkstep` / `reviewwalkcount` / `reviewwalkkeys`. Que la review corra
sobre un borrador **no se persiste**: se re-deriva preguntando si existe el
archivo del borrador de `<src>`, igual que la secuencia de entradas se re-deriva
en cada verbo en vez de guardarse.

Esto mantiene intactos los dos guardias de metadata de `finish` (claves de step
sin `reviewmode=step` y claves de walk sin `reviewmode=walk`), que no necesitan
saber nada de esta feature.
