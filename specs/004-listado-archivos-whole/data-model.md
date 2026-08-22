# Data Model — Listado de archivos del rango en modo whole

Fase 1 de [plan.md](./plan.md). La feature **no agrega ninguna entidad
persistida**: no hay claves de configuración nuevas, refs nuevas ni archivos de
estado (FR-009). Lo que sigue son las entidades derivadas que viajan entre las
capas y las reglas que las gobiernan.

---

## Archivo del rango

El único concepto nuevo. Un path que el rango de la review toca, con su posición
dentro del listado.

| Campo      | Tipo    | Origen                                    | Reglas |
|------------|---------|-------------------------------------------|--------|
| `position` | entero  | orden de emisión                          | 1-based, contiguo, sin huecos |
| `path`     | bytes   | `changed_paths` (`git diff --name-only` con `core.quotePath=false`) | byte a byte, sin re-citar ni desarmar la cita de git |

**Ciclo de vida**: ninguno. Se re-deriva en cada invocación y no sobrevive a la
salida del comando. No se marca como visto, no tiene estado propio y no participa
de ningún cursor.

**Derivación**: `range_files <tip> <lower>` sobre `(tip, HEAD)`, donde `HEAD` es el
lower bound de la review. Mismo par de extremos que usa el orden de lectura de
`walk` (research.md Decisión 1).

**Orden**: el que devuelve git. Estable entre invocaciones sobre el mismo rango
(FR-005), y **no** alfabético por decisión de git, no nuestra.

**Pertenencia**: todo archivo que el rango toca, sin excepción — incluidos los que
cuelgan de `.review/` (FR-020) y los que el rango elimina, que no existen en el
working tree pero sí en el rango.

---

## Registro `entry` en modo `whole`

La forma en que un *Archivo del rango* cruza de la CLI a cualquier consumidor.

```
entry<TAB>position<TAB>path
```

Sin campos después del path: los dos de `walk` (`essential`, `annotated`) y el de
`step` (`banked`) se omiten enteros, que es la regla que el registro ya tiene por
modo (FR-003).

**Invariantes**:

- La cantidad de registros `entry` es la cantidad de archivos del rango. Cero es un
  resultado válido (FR-007), no un error.
- El registro `state` de `whole` **no** cambia: sigue con sus seis campos, sin
  `position`, `total`, `recorded`, `current` ni `essential` (FR-004). El total del
  listado no se publica en `state` — se cuenta.
- Orden de emisión dentro de la salida: `state`, después `base` si la hay, después
  los `entry`. El orden **entre** grupos no es significativo para un consumidor; el
  orden **dentro** del grupo `entry` sí lo es.

**Transición de estado del contrato**: la regla vigente *"En `whole` no hay
registros `entry` en absoluto"* queda reemplazada, no matizada (FR-017).

---

## Orden de lectura de `walk` (entidad existente, redefinida)

No cambia de forma; cambia de contenido.

**Antes**: entradas guiadas del walkthrough que intersectan el rango, seguidas de
los archivos del rango sin entrada propia, **excluyendo los que cuelgan de
`.review/`**.

**Después**: lo mismo, sin la exclusión (FR-020).

**Consecuencias sobre datos ya existentes**:

| Dato | Efecto | Manejo |
|------|--------|--------|
| `total` derivado | Sube en 1 en toda review cuyo PR commitea un walkthrough — la mayoría | Esperado; es el objetivo del cambio |
| `reviewwalkcount` (registrado al iniciar) | Queda por debajo del total derivado en reviews ya abiertas | No se toca. `total > recorded` no es error (FR-023) |
| Aviso de "base movida" | Se calcula como `total < recorded` | No se dispara. Ya era asimétrico a propósito (research.md Decisión 7) |
| `walk_range_error` | Dispara cuando el total **cae** por debajo del registrado | No se dispara |
| Entrada del sidecar | Aparece como no anotada, al final del orden | `--why` sobre ella devuelve vacío, como cualquier no anotada |
| PR que sólo toca `.review/` | Antes: secuencia vacía → degradaba a `whole`. Ahora: una entrada | FR-024 |

---

## Proyección en el panel del editor

`PanelModel` es la proyección plana que cruza al webview. Gana un campo y cambia el
significado de un caso.

| Campo | Cambio | Nota |
|-------|--------|------|
| `files` | **nuevo** — los archivos del rango en modo `whole`, en el orden de la CLI | Vacío en `step` y `walk`; ahí la colección se recorre con el cursor |
| `entryCount` | sin cambios de tipo | Deja de ser siempre `0` en `whole` y pasa a ser el conteo mostrado |
| `position`, `total`, `atFirst`, `atLast`, `current` | sin cambios | Siguen ausentes en `whole`: la lista no es un cursor (FR-013) |
| `base` | sin cambios | Sigue conviviendo con la lista, como nota del rango |

**Regla que se mantiene**: el modelo no agrega información, sólo decide qué de lo
que la CLI ya reportó es visible. `files` se llena desde los registros `entry` de la
misma invocación de `status --porcelain` que el panel ya hace — no se agrega ninguna
invocación (FR-011).

---

## Identidad de una entrada, por modo

Regla transversal que esta feature deja enunciable en una línea, y que hoy está
implícita en una condición del parser (research.md Decisión 4):

| Modo | `id` de `entry` | Tipo en el consumidor |
|------|-----------------|-----------------------|
| `step` | SHA corto del commit | cadena |
| `walk` | path | referencia de path |
| `whole` | path | referencia de path |

El corolario es lo que hace que la lista sea accionable: en los dos modos donde el
`id` es un path, un consumidor puede abrir el archivo; en `step` necesita el
plumbing del commit.
