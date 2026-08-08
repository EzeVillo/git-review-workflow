# Data Model: Contrato de salida legible por programas

No hay entidades persistidas nuevas (ver Assumptions del spec y Decisión 4 de
`research.md`): todo lo de abajo se deriva en el momento de la consulta a
partir de config/refs ya existentes. Este documento describe la forma de los
datos tal como salen por el contrato porcelain, no un esquema de
almacenamiento.

## Estado de review (`state`)

Un registro por invocación de `status --porcelain` dentro de una review
activa (FR-006, FR-007, FR-008, FR-009).

| Campo         | Siempre presente      | Descripción                                                                                                               |
|---------------|-----------------------|---------------------------------------------------------------------------------------------------------------------------|
| `branch`      | sí                    | rama `review/<x>` actual                                                                                                  |
| `source`      | sí                    | origen revisado (`branch.<x>.reviewsource`)                                                                               |
| `tip`         | sí                    | punto fijado del origen, SHA completo                                                                                     |
| `mode`        | sí                    | `whole` \| `step` \| `walk`                                                                                               |
| `walkthrough` | sí                    | `none` \| `applied` \| `degraded` (Decisión 4). Siempre `none` en modo `step`                                             |
| `position`    | sólo en `step`/`walk` | posición actual, 1-based                                                                                                  |
| `total`       | sólo en `step`/`walk` | total de posiciones **derivado ahora**; coincide con la cantidad de líneas `entry` de esta misma salida (Decisión 6)      |
| `recorded`    | sólo en `step`/`walk` | total **registrado al iniciar** (`reviewcount` / `reviewwalkcount`). `total` ≠ `recorded` ⇒ la base se movió (Decisión 6) |
| `current`     | sólo en `step`/`walk` | SHA corto del commit (step) o path (walk) actual                                                                          |
| `essential`   | sólo en `walk`        | `1` si la entrada actual lleva `> key`, si no `0`                                                                         |

Ausencia de un campo no aplicable (p. ej. `position` en modo `whole`) se
representa con la ausencia del campo, nunca con un valor vacío que pueda
confundirse con un dato real (Acceptance Scenario 2 de US1) — igual que
`status` humano hoy omite la sección de cursor en modo whole. La regla vale
para todo el contrato: **omitir, nunca vaciar, y nunca rellenar con un
centinela** (Decisiones 3 y 7).

`walkthrough` es la excepción aparente que confirma la regla: en modo `step`
no se omite sino que vale `none`, porque el registro es posicional y omitirlo
correría todos los campos siguientes. `none` es cierto en step (no hay
walkthrough aplicado) y admite refinarse después de forma aditiva.

## Entrada de secuencia (`entry`)

Cero o más registros por invocación, uno por posición del **orden de lectura
completo** (FR-010, FR-011; Q2 = C). En walk deriva de `walk_reading_order`:
la secuencia curada de `walk_sequence`, seguida de todo path que
`changed_paths` reporta en rango y que no tiene entrada propia en el
walkthrough — agregado al final en vez de omitido, para que un review no
llegue a `finish` con archivos del PR que el reviewer nunca vio (el
precedente es `git status`, que no esconde los untracked). En step deriva de
`rev-list --reverse --first-parent --no-merges <start>..<tip>` — el mismo
mecanismo que ya recorre `next`/`prev`.

| Campo       | Modo  | Descripción                                                     |
|-------------|-------|-----------------------------------------------------------------|
| `position`  | ambos | 1-based, coincide con el orden de lectura real                  |
| `id`        | ambos | path (walk) o SHA corto del commit (step)                       |
| `essential` | walk  | `1`/`0`, marca `> key` (FR-008); `0` en una posición no anotada |
| `annotated` | walk  | `1`/`0`, si el path tiene entrada propia en el walkthrough      |
| `banked`    | step  | `1`/`0`, existe `refs/review-edits/<src>/<position>` (Q2 = C)   |

El grupo no aplicable al modo (`essential`+`annotated` en step, `banked` en
walk) se omite entero de la línea, no se envía vacío — mismo criterio que en
`state`. `total` (en `state`) cuenta las posiciones no anotadas igual que las
curadas: son parte del mismo orden de lectura, no una lista aparte.

Vacío por completo (cero registros `entry`) en modo `whole` sin walkthrough
aplicable, sin que eso se reporte como error (Acceptance Scenario 4 de US2).

| Campo | Descripción      |
|-------|------------------|
| `id`  | path sin entrada |

## Archivos del commit actual (`file`, modo `step`)

Cero o más registros **sólo en modo step**: los paths que toca el commit bajo
el cursor (`state.current`). Es un inventario auxiliar, no la secuencia de
lectura — esa sigue siendo `entry` (un commit por posición).

| Campo      | Descripción                                                           |
|------------|-----------------------------------------------------------------------|
| `position` | 1-based dentro del commit actual (no es `reviewstep`)                 |
| `path`     | path del archivo, mismas reglas de bytes que `entry.id` en walk/whole |

No lleva status letter ni patch. Un commit sin archivos produce cero líneas.
En walk/whole no se emite el tipo. `state.total` no los cuenta.

## Texto explicativo (`why`)

No es un registro porcelain — es la salida completa y única de
`status --why <path>` (FR-012, FR-014). Texto crudo, sin marcadores
reservados (`> key`, `> at:`), preservando saltos de línea internos, tal como
lo devuelve `walk_why` hoy. Vacío (stdout vacío, exit 0) para una entrada sin
cuerpo (Acceptance Scenario 3 de US4). Sólo válido en modo `walk` — en
cualquier otro modo, `status --why` es un error de uso (exit 1): step no tiene
entradas de walkthrough que expliquen un path.

## Inventario (`branch`, bajo `list --porcelain`)

Un registro por rama de review encontrada (activa, guardada u huérfana),
igual alcance que `list` humano hoy (US6, FR-020).

| Campo                | Siempre presente                                 | Descripción                                                                                                                    |
|----------------------|--------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| `name`               | sí                                               | nombre de la rama                                                                                                              |
| `saved`              | sí                                               | `1` si está bajo `review-saved/`, si no `0`                                                                                    |
| `current`            | sí                                               | `1` si es la rama en la que está parado HEAD, si no `0`                                                                        |
| `orphan`             | sí                                               | `1` si no tiene `reviewsource` (metadata ausente)                                                                              |
| `mode`               | no, si `orphan=1`                                | `whole` \| `step` \| `walk`                                                                                                    |
| `position` / `total` | no, si `orphan=1`, `mode=whole` o la clave falta | leídos de la config de la rama (`reviewstep`/`reviewcount`, `reviewwalkstep`/`reviewwalkcount`), **no** derivados (Decisión 7) |

A diferencia del registro `state`, acá `total` es el valor persistido, no el
derivado: el inventario no re-deriva la secuencia de cada rama (Decisión 7).
Por eso tampoco hay campo `recorded` — sería el mismo número. Si una de las
dos claves falta, ambos campos se omiten; nunca se emite el `?` que la salida
humana de `list` usa como relleno.

Nótese que este registro usa la etiqueta `branch`, distinta de `state`
(una review) y de `entry` (una posición dentro de una review) — tres tipos de
registro con esquemas y cardinalidades distintas, cada uno con su propio
conjunto de campos, todos coexistiendo por la etiqueta líder de línea.

## Situación (código de salida, no un dato de línea)

No es un registro de texto: es el código de salida del proceso (Decisión 5).
Deliberadamente fuera del stream porcelain — mezclar "hubo o no hubo review"
con las líneas de datos habría obligado a todo consumidor a parsear una línea
más sólo para saber si debía parsear el resto.

| Código | Situación                                                                                                                                |
|--------|------------------------------------------------------------------------------------------------------------------------------------------|
| `0`    | éxito — hay datos que emitir (o inventario vacío, en `list`)                                                                             |
| `1`    | error — metadata ausente o corrupta, argumento inválido, no es un repo git                                                               |
| `2`    | no hay review activa (sólo `status`; no aplica a `list`)                                                                                 |
| `3`    | el cursor quedó fuera del rango vigente porque HEAD se movió de la base — recuperable por el usuario (FR-023, Decisión 5). Sólo `status` |

`1` y `3` son ambos "no se pudo responder", pero se separan por quién puede
arreglarlo: el `3` tiene una acción concreta del lado del usuario
(`git reset --soft`), el `1` no. Una rama `review/*` sin metadata es `1`, no
`2`: HEAD está parado en algo que dice ser una review.
