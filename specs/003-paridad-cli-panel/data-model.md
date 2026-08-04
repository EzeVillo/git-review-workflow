# Data Model: Paridad de información entre la CLI y el panel del editor

Las entidades del spec, aterrizadas a los dos lados que las manipulan: lo que la
CLI deriva y emite, y lo que la extensión parsea y proyecta. Nada de esto se
persiste — los tres datos se derivan en cada invocación, igual que hoy se
derivan para imprimirse en pantalla.

## Lado CLI

### Origen de cada dato

| Dato   | De dónde sale                                        | Cuándo se emite            |
|--------|-------------------------------------------------------|-----------------------------|
| asunto | `git log --format=%s` sobre el rango de la secuencia | modo `step`, una vez por posición |
| autor  | `git log --format='%an <%ae>'` sobre el mismo rango   | modo `step`, una vez por posición |
| base   | `git config branch.<rama>.reviewbase`                | modo `whole`, sólo si existe |

Ninguno es estado nuevo: los tres ya se leen hoy para la salida humana
(`bin/git-review-verbs/status`, `show_commit` en `bin/git-review-lib.sh`).

### Derivación de la secuencia de asuntos y autores

Dos listas paralelas a `commits`, la lista que `load_step_review_meta` ya
deriva. Las tres se recorren con las **mismas** flags —
`--reverse --first-parent --no-merges <start>..<tip>` — así que la n-ésima línea
de cada una corresponde al n-ésimo commit.

```
commits    →  6bce6d1              f307e69
subjects   →  "feat: exponer …"    "test: cubrir …"
authors    →  "Eze Villo <…>"      "Eze Villo <…>"
```

**Invariante de alineación**: las tres listas tienen exactamente `total` líneas.
Se sostiene porque ninguno de los dos formatos puede emitir un newline interno
(`%s` es por definición la primera línea; git elimina el newline del ident al
construir el commit — medido, ver `research.md` Decisión 1). Si alguna vez
dejara de sostenerse, el síntoma sería un asunto emparejado con el commit
equivocado, en silencio: es la invariante que los tests tienen que atacar.

**Reglas de validación**:

- Una lista con menos líneas que `total` es metadata inconsistente, no un asunto
  vacío. El emisor no debe rellenar el faltante con una cadena vacía.
- Un asunto vacío es un valor legítimo y se emite como campo vacío.
- El número de procesos git empleado en producir las dos listas es **constante**,
  independiente de `total` (FR-014).

### Formato de emisión

Los tres registros pasan por `porcelain_row`, el único punto que escribe una
línea porcelain. La única regla nueva que el emisor debe respetar:

> El campo de texto libre se pasa **último** a `porcelain_row`, y hay a lo sumo
> uno por llamada.

`porcelain_row` no escapa nada, y eso sigue siendo correcto: un tab dentro del
último campo no desplaza nada porque no hay campos después.

## Lado extensión

### Tipos del parser

Extienden `PorcelainResult` sin tocar `StateRecord` ni `EntryRecord`:

```
PorcelainResult
├── state: StateRecord          (sin cambios)
├── entries: EntryRecord[]      (sin cambios)
├── subjects?: Map<position, string>   ← nuevo
├── authors?:  Map<position, string>   ← nuevo
└── base?: string                      ← nuevo
```

**Por qué mapas y no campos en `EntryRecord`**: emparejar por `position` es lo
que el contrato exige (nunca por orden de aparición), y mantener los datos
nuevos fuera de `EntryRecord` conserva intacta la forma que los tests unitarios
existentes ya afirman.

**Por qué opcionales**: la ausencia del mapa entero significa *"la CLI no provee
este dato"* y es distinta de un mapa con una entrada vacía, que significa *"el
dato existe y está vacío"* (FR-004). Es la misma disciplina de `toOptionalInt`,
que existe para que un campo ausente no se convierta en un `0` inventado.

### Lectura de un campo de texto libre

El campo se toma como **el resto de la línea desde el N-ésimo tab**, no como el
N-ésimo elemento de un `split`. Con `split("\t")` un asunto que contenga tabs se
partiría en varios elementos y el consumidor mostraría sólo el primero — el modo
de falla exacto que la Decisión 1 evita del lado del emisor y que hay que
respetar también acá.

### Proyección al `PanelModel`

| Campo nuevo        | Presente cuando                        | Qué dibuja                                    |
|--------------------|-----------------------------------------|------------------------------------------------|
| `current.subject`  | modo step y el registro llegó           | el cuerpo principal de la entrada              |
| `current.author`   | modo step y el registro llegó           | la línea de metadatos, junto al SHA            |
| `source`           | siempre (ya venía en `state`)           | la barra, en lugar de la rama                  |
| `tip`              | siempre (ya venía en `state`)           | la barra, abreviado                            |
| `base`             | modo whole y el registro llegó          | el texto del estado sin walkthrough            |
| `entries[].subject`| modo step y el registro llegó           | el selector de la secuencia                    |

**Regla de degradación** (FR-003): cada uno de estos campos ausente deja al panel
dibujando exactamente lo que dibuja hoy. Ninguno introduce un hueco visual, un
valor por defecto ni un mensaje de error: una CLI vieja produce el panel actual,
no un panel roto.

### Estados de un dato, del lado del panel

Tres, no dos — el mismo patrón que `WhyState` ya estableció para las
explicaciones:

| Estado             | Origen                                | Presentación                          |
|--------------------|----------------------------------------|----------------------------------------|
| no provisto        | el registro no llegó                   | el panel de hoy, sin marca de ausencia |
| vacío              | el registro llegó con campo vacío      | la ausencia mostrada como tal          |
| presente           | el registro llegó con contenido        | el contenido, byte a byte              |

## Entidades del spec, mapeadas

| Entidad del spec        | Dónde vive                                                                 |
|--------------------------|-----------------------------------------------------------------------------|
| Commit de la secuencia   | `EntryRecord` + su entrada en `subjects`/`authors`, emparejadas por `position` |
| Encabezado de la review  | `StateRecord.source` / `.tip` (ya existían) + el registro `base`             |
| Exclusión deliberada     | la tabla de exclusiones de `001-contrato-porcelain/contracts/status-porcelain.md` (absorbido ahí por `004`) |
