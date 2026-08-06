# Research: Submodo walk solo-keys

**Feature**: `007-walk-keys-only` | **Date**: 2026-08-06

## Decisión 1 — Flag de inicio, no verbo nuevo

**Decision**: Entrar al submodo con `--keys` en `git review start` y
`git review compare`, simétrico a `--step` / `--no-walk`.

**Rationale**: El producto ya elige el *layout* de lectura en el start
(auto walk / step / whole forzado). Solo-keys es otro layout de walk, no
un ciclo de vida distinto. Un verbo `git review keys` implicaría toggle
mid-session (fuera de alcance v1) y otra entrada al PATH mental.

**Alternatives considered**:

| Opción                              | Por qué no                                                                                         |
|-------------------------------------|----------------------------------------------------------------------------------------------------|
| Verbo `keys on/off` mid-session     | Útil, pero v1 sticky al start cubre el caso principal; se puede sumar después sin romper porcelain |
| Config global `reviewworkflow.keys` | Cambiaría el default de todos los starts; el spec dice no-default                                  |
| Subcomando `start --walk=keys`      | Rompe el estilo de flags booleanas existentes                                                      |

## Decisión 2 — Sigue siendo `mode=walk`, no un cuarto mode

**Decision**: `branch.<review>.reviewmode` sigue en `walk`. El filtro se
persiste en una clave aparte: `branch.<review>.reviewwalkkeys=1`.

**Rationale**: `finish`/`abort`/`preview`/guards de metadata ya tratan
`walk` como familia. Un `mode=keys` obligaría a tocar cada `case "$mode"`
del árbol y a educar a consumidores porcelain. El filtro es una
restricción de secuencia, no un layout de working tree distinto (el PR
sigue materializado entero).

**Alternatives considered**: `mode=keys` — más visible en porcelain state,
pero costo de propagación alto y falso paralelismo con step/whole.

## Decisión 3 — Secuencia = curated ∩ keys (nunca uncovered)

**Decision**: La secuencia efectiva solo-keys se deriva de
`walk_sequence` (entradas del walkthrough en rango) filtrada por
`walk_is_key` / el mismo criterio de `> key`. Los uncovered **no entran**.

**Rationale**: Un uncovered no puede llevar `> key` (no tiene body en el
sidecar). Incluirlos rompería “solo keys”. El helper nuevo
(`walk_keys_order` o filtro sobre la secuencia curada) reusa
`walk_normalize` / `changed_paths` vía `walk_sequence` — sin tercer punto
de normalización de paths.

**Performance**: Una lectura del walkthrough + un pase (mismo patrón que
`walk_count_keys` / `walk_entry_fields`), no un `git show` por path.

## Decisión 4 — `reviewwalkcount` / posiciones = K filtrado

**Decision**: Al iniciar con `--keys`, `reviewwalkcount` se graba como K
(cantidad de keys en rango en ese momento). `reviewwalkstep` es 1..K.
Cada verbo re-deriva la secuencia filtrada; `total` actual = longitud
re-derivada. Misma semántica de “base moved” / exit 3 que walk hoy.

**Rationale**: Coherente con walk normal (recorded al start, total
derivado). Renumerar 1..K evita que el revisor vea “3/12” cuando solo hay
3 keys y las posiciones “saltan”.

## Decisión 5 — Porcelain: registro presencia `keys`

**Decision**: Emitir un registro de una sola etiqueta, sin campos:

```text
keys
```

cuando el filtro está activo (análogo a `readonly`). Las líneas `entry`
son solo las de la secuencia filtrada; en ellas `essential` será siempre
`1`. `state.total` = K. Consumidores viejos ignoran la etiqueta (FR-003
de `001`).

**Rationale**: Aditivo, no desplaza campos de `state`, no obliga a
parsear un flag posicional nuevo en el medio de la línea state (que ya
tiene cola opcional `essential`). Espeja el precedente `readonly` de
compare.

**Alternatives considered**: campo final `keysfilter` en `state` — también
aditivo, pero mezcla indicador de sesión con datos del cursor; el
registro suelto es más fácil de testear y de ignorar.

## Decisión 6 — Cero keys = error antes de crear la rama

**Decision**: Si `--keys` y, tras detectar walk aplicable, K=0 → `die` con
mensaje accionable **antes** de `git switch -c` / materializar la review.

**Rationale**: El flujo actual de `start` ya decide walk antes del
switch. Secuencia vacía dejaría metadata inválida (`reviewwalkcount≥1` es
invariante hoy). Mejor fallar limpio.

## Decisión 7 — Incompatibilidades

**Decision**:

| Combinación                                        | Resultado                              |
|----------------------------------------------------|----------------------------------------|
| `--keys` + `--step`                                | error                                  |
| `--keys` + `--no-walk`                             | error                                  |
| `--keys` sin walkthrough en tip / sin intersección | error (no degrada a whole en silencio) |
| `--keys` + walk con K≥1                            | ok                                     |

**Rationale**: Degradar a whole con `--keys` mentiría al usuario que pidió
explícitamente el filtro. `--step` no tiene notion de key de archivo.

## Decisión 8 — save / continue / finish / abort

**Decision**: `continue` restaura `reviewwalkkeys` con el mismo
`restore_meta` que las demás claves walk. `finish`/`abort` no cambian su
efecto sobre el árbol; los guards de metadata corrupt (walk keys sin
`reviewmode=walk`) incluyen la clave nueva. `clean`/`forget` ya borran la
rama y su config de branch.

**Rationale**: Sticky por sesión de review, como el resto del cursor.

## Decisión 9 — Extensión: layout + invocación

**Decision**:

1. Ampliar el contrato de invocación: `start` (y `compare` si aplica)
   admiten `--keys` mutuamente excluyente con `--step`/`--no-walk`.
2. En el asistente de start, un ítem de layout del estilo
   “Walkthrough — keys only” que setea el intent a pasar `--keys`
   (layout dedicado, no un segundo prompt, para no alargar el flujo).
3. Parser porcelain: reconocer registro `keys` → `keysOnly: true` en el
   modelo; el panel muestra un indicador y lista solo lo que ya viene en
   `entry` (no filtra en cliente).

**Rationale**: Filosofía `002`: el panel no re-deriva. Si la CLI filtra
entries, el panel solo pinta.

## Decisión 10 — Documentación

**Decision**: Actualizar `README.md` + `README.es.md` (tabla de start,
sección walk / `> key`, ejemplos). Landing (`docs/index.html`) **no** se
toca: el demo del formato key ya existe; no se agrega un comando nuevo a
la lista corta de ejemplos salvo que se quiera mostrar `--keys` en el
futuro (fuera de las cuatro superficies obligatorias si no se toca).

**Rationale**: CLAUDE.md — landing solo si el cambio toca sus cuatro
cosas; `--keys` no está en esa lista de ejemplos hoy.
