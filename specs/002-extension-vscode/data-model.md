# Modelo de datos: Extensión de VS Code

Todo lo de acá es **efímero y derivado**. No hay persistencia: cada refresco
reconstruye el modelo entero desde la salida de la CLI y descarta el anterior
(FR-001, FR-002). No existe una entidad "review" con identidad propia del lado
de la extensión — existe *la última respuesta de la CLI, interpretada*.

Las entidades se corresponden con las del spec (§Key Entities) y con los
registros del contrato porcelain de
[`001-contrato-porcelain`](../001-contrato-porcelain/contracts/status-porcelain.md).

---

## `Situation` — el resultado de una invocación

Enumeración cerrada. Es la entidad **raíz**: todo lo demás cuelga de que valga
`review`. Nace del exit code, más dos casos que la extensión detecta antes de
llegar a ejecutar el verbo.

| Valor          | Origen                                    | ¿Es error? | Acción ofrecida            |
|----------------|-------------------------------------------|------------|----------------------------|
| `review`       | exit `0`                                  | no         | —                          |
| `no-review`    | exit `2`                                  | **no**     | cómo iniciar una review    |
| `out-of-range` | exit `3`                                  | no         | `git reset --soft`         |
| `error`        | exit `1`                                  | sí         | ninguna (sólo diagnóstico) |
| `cli-missing`  | `ENOENT`, o git no reconoce el subcomando | sí         | instalar la CLI            |
| `cli-outdated` | `--version` < `0.3.0`                     | sí         | actualizar la CLI          |

**Reglas de validación**:

- `no-review` NO es un error y no puede presentarse como tal (FR-004). Es la
  situación más frecuente en la vida de un usuario.
- `out-of-range` es recuperable **por el usuario**; `error` no lo es. La
  diferencia es visible: sólo la primera ofrece una acción (FR-023, FR-024).
- Un exit code desconocido (`>3`) se trata como `error`, nunca como `review`.
- El `stderr` de la CLI se conserva íntegro y se muestra tal cual; no se
  reemplaza por texto propio (FR-024).

**Transiciones**: cualquiera hacia cualquiera, en cada refresco. La extensión no
asume continuidad — el usuario pudo hacer `finish` en la terminal entre dos
lecturas (edge case del spec), y eso es simplemente `review → no-review`.

---

## `ReviewState` — el estado de la review en curso

Existe sólo cuando `Situation = review`. Es el registro `state` del porcelain,
uno por invocación, siempre la primera línea.

| Campo         | Tipo                                   | Presencia            | Origen      |
|---------------|----------------------------------------|----------------------|-------------|
| `branch`      | string                                 | siempre              | `state[1]`  |
| `source`      | string                                 | siempre              | `state[2]`  |
| `tip`         | string (SHA completo)                  | siempre              | `state[3]`  |
| `mode`        | `whole` \| `step` \| `walk`            | siempre              | `state[4]`  |
| `walkthrough` | `none` \| `applied` \| `degraded`      | siempre              | `state[5]`  |
| `position`    | entero ≥ 1                             | sólo `step` / `walk` | `state[6]`  |
| `total`       | entero ≥ 0 (derivado **ahora**)        | sólo `step` / `walk` | `state[7]`  |
| `recorded`    | entero ≥ 0 (registrado **al iniciar**) | sólo `step` / `walk` | `state[8]`  |
| `current`     | `PathRef` (walk) \| string SHA (step)  | sólo `step` / `walk` | `state[9]`  |
| `essential`   | booleano                               | sólo `walk`          | `state[10]` |

**Reglas de validación**:

- El campo `mode` se lee **antes** de decidir la aridad esperada del registro.
  Los campos son posicionales y la línea tiene 6, 10 u 11 campos según el modo;
  interpretarla al revés produce corrimientos silenciosos.
- `total ≠ recorded` es una condición **legítima y visible**: significa que la
  base se movió pero el cursor sigue en rango. Se advierte (FR-011) sin degradar
  nada. (Con el cursor ya fuera de rango la invocación no llega a emitir `state`:
  sale con `3`.)
- `walkthrough = degraded` sólo aparece con `mode = whole` — degradar *es*
  caer a whole. En `mode = walk` vale siempre `applied`, y en `mode = step`
  siempre `none` (el campo es posicional, por eso no se omite).
- Campos posteriores a los conocidos se ignoran (FR-003).

**Derivado, no almacenado**: la etiqueta de posición que muestra el panel
(`N/M`) se compone de `position` y `total`, nunca de `recorded`.

---

## `SequenceEntry` — una posición del orden de lectura

Cero o más, uno por registro `entry`. En `mode = whole` no hay ninguno.

| Campo       | Tipo                                        | Presencia   | Origen     |
|-------------|---------------------------------------------|-------------|------------|
| `position`  | entero ≥ 1 (1-based)                        | siempre     | `entry[1]` |
| `id`        | `PathRef` (walk) \| string SHA corto (step) | siempre     | `entry[2]` |
| `essential` | booleano                                    | sólo `walk` | `entry[3]` |
| `banked`    | booleano                                    | sólo `step` | `entry[3]` |

**Reglas de validación**:

- `essential` y `banked` ocupan **la misma posición** y son mutuamente
  excluyentes; cuál de los dos es lo determina `ReviewState.mode`, no el
  registro. El campo que no aplica se omite, no viene vacío.
- Las entradas llegan en orden de lectura y ese orden es la única fuente de
  ordenamiento: la extensión **no** las reordena ni las ordena por `position`
  (si divergieran, reordenar ocultaría un bug del contrato).
- `entry` con la misma `position` que `ReviewState.position` es la entrada
  actual (FR-006). No se marca por comparación de `id`: dos entradas podrían
  compartir path en un walkthrough mal escrito, y la posición es lo que el
  cursor mueve.
- La cantidad de `entry` es siempre igual a `ReviewState.total` — el contrato lo
  garantiza. Si no coincide, es `error`, no un árbol a medias.

---

## `UncoveredFile` — un archivo cambiado sin entrada en el walkthrough

Cero o más, uno por registro `uncovered`. Un solo campo: `id: PathRef`
(`uncovered[1]`).

**Reglas de validación**:

- Se muestran **agrupados y separados** de las entradas del walkthrough
  (FR-008): son parte del PR, no del recorrido curado, y mezclarlos le mentiría
  al revisor sobre qué revisó el autor.
- Vienen en `mode = walk` y también en `mode = whole` cuando
  `walkthrough = degraded` (ahí son *todos* los archivos del rango). En
  `mode = step` no hay ninguno: el modo no tiene concepto de cobertura.

---

## `PathRef` — un path, en sus dos formas

No es un registro del contrato: es la representación interna de **todo** path,
y existe por la tensión entre FR-012 (mostrar legible) y FR-015 de la feature
001 (devolver byte a byte).

| Campo     | Tipo   | Uso                                                      |
|-----------|--------|----------------------------------------------------------|
| `raw`     | string | **lo único** que vuelve a la CLI (`status --why <path>`) |
| `display` | string | **lo único** que ve el usuario; también base del `Uri`   |

**Reglas de validación**:

- `display` = `raw` des-citado si `raw` empieza con `"` (citado estilo C de git:
  `\\`, `\"`, escapes de control, octales `\nnn` reensamblados como bytes y
  decodificados UTF-8); si no, `display === raw`.
- La operación es **unidireccional**: nunca se re-cita un `display` para
  mandárselo a la CLI. Si hace falta el path para una invocación, se usa `raw`,
  que se conservó justamente para eso.
- Aplica por igual a `ReviewState.current` (walk), `SequenceEntry.id` (walk) y
  `UncoveredFile.id`: los tres son el mismo dato de la misma fuente.

---

## `Why` — la explicación de una entrada

Se obtiene por separado y bajo demanda (nunca al construir el árbol), con
`status --why <raw>`.

| Campo     | Tipo    | Significado                               |
|-----------|---------|-------------------------------------------|
| `text`    | string  | el payload completo de stdout, sin tocar  |
| `present` | boolean | `false` si `text` está vacío con exit `0` |

**Reglas de validación**:

- `present = false` (entrada sin explicación) y un fallo al obtenerla (exit `1`)
  son estados **distintos** y se muestran distinto (FR-018).
- El texto se pasa a Markdown tal cual, con sus saltos de línea (FR-017). La
  extensión no recorta, no re-envuelve ni normaliza espacios: la CLI ya quitó
  los marcadores reservados.
- No se cachea entre refrescos. El walkthrough del tip no cambia durante una
  review, pero cachear obligaría a invalidar por rama/tip y el costo que evita
  es una invocación en hover.

---

## `RepositoryTarget` — a qué repositorio corresponde el panel

| Campo     | Tipo   | Origen                                               |
|-----------|--------|------------------------------------------------------|
| `rootUri` | `Uri`  | API de la extensión `vscode.git`                     |
| `label`   | string | nombre de la carpeta, para desambiguar en multi-root |

**Reglas de validación**:

- Con más de una carpeta en la ventana, el panel indica sin ambigüedad de cuál
  está hablando (FR-029). No se agregan reviews de varios repos en un mismo
  árbol.
- `rootUri` es el `cwd` de **toda** invocación. Nunca se invoca la CLI con el
  cwd del proceso del editor.
- Este es el único dato que la extensión toma de la API de git, junto con la
  señal de cambio. Ningún campo de `ReviewState`, `SequenceEntry` o
  `UncoveredFile` se alimenta de ahí (SC-005).

---

## Relación entre entidades

```text
Situation
└── (= review) ReviewState            ← registro `state`, 1 por invocación
                ├── SequenceEntry[]   ← registros `entry`, en orden de lectura
                │     └── Why         ← bajo demanda, 1 invocación aparte
                └── UncoveredFile[]   ← registros `uncovered`
```

Una sola invocación de `status --porcelain` produce el árbol entero salvo los
`Why`. Eso es lo que hace que refrescar sea barato y que el panel pueda
reconstruirse de cero ante cualquier evento, en lugar de mantener un estado
incremental que pueda desincronizarse (FR-019).
