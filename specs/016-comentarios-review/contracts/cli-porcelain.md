# Contrato: `git review comments` y registros v1

Contrato v1 implementado en la CLI candidata; la integración de los cuatro
clientes sigue pendiente. Amplía sus listas cerradas de invocación y no cambia
los campos existentes de `status/config/list`.

## Argv

```text
git review comments status [--porcelain] [--context <id> | --all]
git review comments init --document <local|shared> [context-options] [guards]
git review comments add --document <local|shared> [context-options] [location-options]
                       [--text <text> | --stdin] [guards]
git review comments delete --document <local|shared> [--entry <ordinal>] [--context <id>] [guards]

git review comments renumber --document <local|shared> [--context <id>] [guards]
git review comments entries --document <local|shared> [--context <id>] --porcelain
git review comments diff --document <local|shared> --entry <ordinal>
                        [--context <id>] [--porcelain] [guards]
git review comments save [guards]
git review comments prepare --context <id> [--check [--porcelain]] [guards]
```

`context-options` admite `--context <id>` para contexto conocido y una sola
opción explícita `--new-context` o `--use-context <id>` para resolver ambigüedad
o declarar otro trabajo aunque Git proponga continuidad. Se permiten antes
de la primera edición de la pasada; con preparación nueva sin conservar se
rechaza el cambio de contexto hasta conservarla o descartarla. `init` crea
explícitamente sólo el documento elegido; `add` lo crea al confirmar texto
no vacío. La CLI exige `--document` también con un solo destino; el cliente lo envía automáticamente sin selector cuando sólo hay una capacidad. Con varios exige elección por captura, sin preferencia retenida. `--new-context`
no borra el contexto anterior: crea otro y lo asocia a esta sesión.

`delete` elimina sólo el documento elegido de una preparación activa o un resultado
conservado después de Finish. Revalida contexto y bytes bajo lock; no modifica
la otra copia ni un `.review/comments.md` ya entregado. Un Shared pendiente
eliminado se reporta `discarded` y no se puede volver a preparar sin documento.
Las preparaciones pausadas siguen requiriendo `continue` antes de borrarlas.

`delete --entry <ordinal>` elimina sólo esa entrada física. Conserva sin cambios
los bytes, números y orden de las demás; no renumera. Incluso sin entradas,
el documento permanece presente y no se descarta la entrega pendiente.
Usa las mismas guardas y publicación atómica que las demás transformaciones.

`location-options`: `--path <path>`, `--side <base|head>`,
`--start-line <n> --end-line <n>`, `--start-column <n> --end-column <n>`,
`--base <OID> --head <OID>`,
`--base-path <path> --head-path <path>` y `--unversioned`.
No se requieren para una entrada general. Líneas exigen path y lado; los pares
de líneas y OID deben estar completos. En renombres se informan ambas rutas;
se omite la del lado inexistente. Si se proporciona sólo `--path`, la CLI
resuelve las rutas del rango capturado mediante su inventario de cambios.

Las columnas son opcionales y cuentan unidades UTF-16 desde 1 (un tabulador
cuenta como una unidad). Con columnas, ambas posiciones son extremos y el fin
es exclusivo: seleccionar los caracteres 3 a 5 de la línea 12 usa
`--start-line 12 --end-line 12 --start-column 3 --end-column 6`. Sin columnas,
las líneas siguen siendo inclusivas. Se exigen ambas columnas; se rechazan
selecciones vacías o invertidas.

Sin OID explícitos, la CLI obtiene el par real del modo/paso actual. Una
ubicación de working tree sólo se marca versionada cuando coincide con el
blob y el host no informa buffer sucio. Los IDE conservan la procedencia de
sus diffs y pasan refs/lado reales. OID explícitos se resuelven y validan;
no se aceptan nombres móviles guardados en el Markdown.

`guards`: `--expect-context <token>` y `--expect-document <revision>`.
El token de contexto representa sesión, contexto documental, modo, cursor y
extremos de captura, además del custodio. La revisión representa bytes y
presencia del documento. Los clientes los envían en toda mutación/selección;
un usuario de terminal puede omitirlos para operar sobre el estado actual.
`save`, que afecta a dos documentos, exige las revisiones del par mediante
`--expect-local <revision> --expect-shared <revision>` en los clientes.
`prepare` también valida la revisión del Compartido y el destino.
Con `--check`, sólo inspecciona y permite comparar la prosa sin escribirla;
`--porcelain` en prepare requiere `--check`.

Todos aceptan `-h`, rechazan opciones/argumentos sobrantes y soportan `--`
para terminar opciones. Valores de opciones se pasan como argv independientes,
incluidos textos/rutas que comiencen por guion. No se concatena texto de usuario
en shell. `renumber` sobre un documento ausente informa ausencia; no lo crea.

## Entrada de texto y contexto permitido

`--text` y `--stdin` son mutuamente excluyentes. Sin ambos se compone en un
temporal con el comando obtenido de `git var GIT_EDITOR`. La interpretación de
ese comando sigue la convención de Git; el texto nunca es parte del comando.
Vacío/whitespace o salida sin contenido se considera cancelación sin mutación;
un editor que falla informa error sin crear el documento. `--stdin` permite
texto multilínea sin incluirlo en logs de argv; los invocadores incorporan
stdin con UTF-8 y no registran su cuerpo.

`init/add`: sólo review o compare activos; compare admite únicamente Local y rechaza Shared antes de componer o escribir. Las reviews admiten Local y Shared, incluidos comentarios generales
durante un conflicto de finish. No se inventa contexto histórico de los
marcadores de conflicto. `status/entries/diff`: lectura durante y después.
`renumber`: también sobre resultados existentes fuera de sesión. `save`:
exclusivamente compare, checkpoint opcional compatible; guarda los documentos existentes como resultado local y sigue
comparando. `prepare`: reintenta una entrega Compartida pendiente después del
cierre; no inicia una review ni convierte un resultado de compare en versionado.

Fuera de sesión, sin `--context`, `status` enumera resultados. Las operaciones
de documento requieren contexto si hay más de uno; no eligen el más reciente.
Los editores abren la ruta absoluta informada por `status`. La CLI no necesita
otro escritor/editor propio: la composición con el editor está documentada.

## Salidas y errores

| Exit | Significado |
|------|-------------|
| `0` | Consulta/operación completada, o cancelación sin cambios |
| `1` | Uso, formato, lectura/escritura, identidad ambigua o conflicto de destino |
| `2` | No hay sesión compatible para la operación solicitada |
| `4` | Token de contexto/documento obsoleto; ninguna mutación |
| `5` | Revisión o contenido histórico requerido no encontrado |

Los códigos 4 y 5 pertenecen a la familia nueva y se prueban por contrato; no
cambian códigos de los verbos existentes. Diagnósticos y notas van a stderr;
resultados a stdout. Fallar un documento no degrada `status` de review a error
ni impide `next/prev/preview`; el refresh de comments representa el diagnóstico
por separado. Las mutaciones nuevas retornan su error sin tocar prosa ajena.

## Registros de `status --porcelain`

TSV mediante `porcelain_row`, una línea por registro. Se ignoran tags desconocidos
y campos adicionales. Paths/ids van inmediatamente después del tag cuando son
el sujeto. Texto mostrable sólo al final de un registro, sin cuerpos multilínea.
Las rutas mantienen la política de bytes del porcelain vigente.

```text
comments-capability<TAB>init|add<TAB>local|shared
comments-context<TAB>context<TAB>review|compare<TAB>active|saved|result|repository<TAB>guard-token<TAB>label
comments-owner<TAB>context<TAB>source<TAB>custodian-branch-or-empty
comments-guard<TAB>guard-token
comments-document<TAB>absolute-path<TAB>context<TAB>local|shared<TAB>present|absent<TAB>revision
comments-count<TAB>absolute-path<TAB>nonnegative-integer
comments-diagnostic<TAB>absolute-path<TAB>code<TAB>message
comments-identity<TAB>resolved|fresh|ambiguous<TAB>message
comments-candidate<TAB>context<TAB>label<TAB>description
comments-delivery<TAB>context<TAB>unchanged|prepared|pending|delivered<TAB>message
comments-capture<TAB>guard-token<TAB>base-OID<TAB>head-OID
```

`description` distingue revisiones de la misma rama con ordinal de selección,
fecha UTC de creación cuando esté disponible, presencia/counts de los documentos
y asunto del último tip revisado. Nunca incluye cuerpos ni usa el token opaco
como etiqueta. Los clientes aceptan también candidatos antiguos sin descripción;
los metadatos faltantes se informan, no se convierten en cero.

Por cada contexto seleccionado se emiten **ambas** filas `comments-document`,
incluso ausentes, para que el cliente conozca rutas y disponibilidad. La consulta
general omite el Shared guardado cuando el Shared del repositorio tiene prioridad;
`--all` conserva el inventario completo para custodia y guardado de buffers.
El estado `repository` usa la ruta fija `.review/comments.md` del working tree
actual, sin crear estado privado. Shared sólo ofrece lectura en ese estado;
Local conservado sigue siendo editable. Los resultados de una entrega correcta
guardan Local y metadata; Shared se lee del repositorio y no de otra copia privada.
`count`
se emite para documento legible/parseable, incluido cero; no se inventa cero
si hay fallo de lectura. Diagnóstico puede coexistir con count cuando sólo
una ubicación histórica es inválida. Los archivos fuente/baseline no son filas
editables adicionales. `comments-capture` sólo existe con extremos resueltos.

`comments-owner` declara la relación de custodia de la CLI: rama `review/…`,
`review-saved/…` o campo vacío si el contexto retenido ya no pertenece a una
sesión. No se deriva del label ni de las rutas. `status --all` añade los
contextos retenidos durante una sesión activa para que un descarte explícito
de otra sesión guarde sólo sus buffers. Es incompatible con `--context` y
no cambia el guard ni el alcance de captura de la sesión activa.
El `label` de `comments-context` es la rama de origen, también para resultados
retenidos de review o compare. Sale del manifiesto del contexto y no exige que
la rama siga existiendo; el token opaco no se usa como etiqueta visible.
`comments-identity` aparece aunque no haya documento; `ambiguous` se acompaña
de candidatos y bloquea sólo inicializar/agregar hasta elegir.

Si el archivo existe pero no puede leerse con seguridad, su fila conserva
`present`, usa la revisión explícita `unreadable` y se acompaña de diagnóstico
`read`, sin `comments-count`. `unreadable` no representa bytes ni es una guarda
que permita escribir: hay que resolver el fallo y obtener una revisión nueva.
El otro documento sigue informándose. Decisión D22, confirmada durante la
implementación el 2026-10-18.

`comments-guard` se emite siempre que existe una sesión compatible, incluso
fresh/ambiguous, sin contexto confirmado, en sesiones antiguas o para captura
general durante conflicto sin refs resolubles. Es el token que retiene el primer
compositor. Se deriva del estado actual sin escribir metadata; la primera
mutación lo valida antes de inicializar custodia. No requiere crear documentos.
La revisión para un destino aún inexistente es `absent`; al confirmar, la CLI
comprueba que sigue ausente además de validar el guard original de sesión.

En contexto nuevo sin token confirmado no hay `comments-context` ni rutas
fabricadas: se emite `comments-identity fresh`. El panel ofrece captura o
creación explícita y obtiene después las dos rutas del contexto confirmado.
La ausencia de contexto no significa que falte la CLI.

`status` es de sólo lectura: no crea carpetas, archivos de comentarios,
commit-tree, config ni refs. Calcular un hash para un token no escribe objetos.
No resuelve objetos por entrada ni vuelca sus cuerpos durante refresh.

## `entries --porcelain` y selector temporal

```text
comments-document<TAB>absolute-path<TAB>context<TAB>document<TAB>presence<TAB>revision
comment-entry<TAB>physical-ordinal<TAB>display-number<TAB>heading-line<TAB>title
comment-scope<TAB>physical-ordinal<TAB>general|file|selection<TAB>base|head|empty
comment-body<TAB>physical-ordinal<TAB>escaped-line
comment-version<TAB>physical-ordinal<TAB>base-OID<TAB>head-OID
comment-path<TAB>physical-ordinal<TAB>base|head<TAB>escaped-relative-path
comment-location<TAB>physical-ordinal<TAB>base|head<TAB>start-line<TAB>end-line
comment-columns<TAB>physical-ordinal<TAB>side<TAB>start-column<TAB>end-column
comment-unversioned<TAB>physical-ordinal
comment-diagnostic<TAB>physical-ordinal<TAB>code<TAB>message
```

Las filas opcionales sólo aparecen si hay datos. Un picker usa ordinal físico
y revisión del documento. Reordenar/editar/renumerar invalida la selección
anterior; no abre otra entrada con el mismo número visible. La CLI obtiene
todo el cuerpo de referencia del documento actual validado, sin ids persistidos.

## `diff` y receta para hosts

La salida humana calcula `git diff <base> <head> -- <paths-literales>` con
extremos separados, `--no-ext-diff` y sin textconv automático. Nunca `B..H`
como argumento ni `log/rev-list/shortlog/range-diff` sobre un tree. No consulta
el archivo actual para decidir si un histórico existe.

`--porcelain` devuelve una receta después de validar árboles y blobs:

```text
comment-diff<TAB>physical-ordinal<TAB>base-tree-OID<TAB>head-tree-OID
comment-blob<TAB>escaped-relative-path<TAB>base|head<TAB>present<TAB>blob-OID
comment-blob<TAB>escaped-relative-path<TAB>base|head<TAB>absent
comment-location<TAB>physical-ordinal<TAB>side<TAB>start-line<TAB>end-line
comment-columns<TAB>physical-ordinal<TAB>side<TAB>start-column<TAB>end-column
```

Para entrada general se emite el rango completo y el cliente ofrece su visor
de rango o la salida de `comments diff`; no inventa un archivo. `absent` declara
una adición/borrado legítimo; un objeto requerido perdido produce exit 5 y
diagnóstico, sin receta parcial utilizable. Los hosts pueden ejecutar lecturas
de blobs por OID para presentar esa receta; no derivan estado de la review.
No cambian de rama, hacen fetch ni reemplazan el head registrado por HEAD.

## Conflicto de entrega del documento

`comments prepare --context <id> --check` muestra la diferencia de prosa entre
preparado y destino y las ubicaciones del baseline y las dos versiones.
Su forma porcelain devuelve rutas/presencia/revisión para abrir una comparación
nativa de documentos, sin confundirla con `comments diff`, que compara código:

```text
comments-delivery-file<TAB>absolute-path<TAB>baseline|prepared|destination<TAB>present|absent<TAB>revision
```

Es una lectura y retorna 0 al poder inspeccionar, aunque siga habiendo un
conflicto indicado por `comments-delivery`; un fallo de lectura retorna 1.
Para resolver, el usuario edita deliberadamente preparado y destino hasta que
coincidan con el resultado deseado. `prepare` sin check reconoce esa igualdad
como entrega hecha; no adopta un baseline nuevo ni pisa cambios ajenos.
No existe `--force` para reemplazar una prosa concurrente. Los clientes ofrecen
esa comparación desde el diagnóstico de Shared y refrescan revisiones al guardar.

## Compatibilidad y release

`comments status` se añade al pipeline de refresh como consulta independiente,
cuando la CLI cumple el piso publicado requerido. Se conservan los wire records
de `status/config/list`, sus códigos y su tolerancia a registros nuevos.
Los contratos de invocación de cada cliente incluyen estos argv, stdin y las
lecturas de objetos de la receta. La CLI se publica antes de actualizar pisos.

### Prosa y detalle del selector

`comment-body` conserva una línea del cuerpo Markdown por registro, incluso las
vacías y los encabezados dentro de fences. Excluye el encabezado de entrada y
el bloque de metadata adyacente. Escapa `%`, tab y CR como `%25`, `%09` y `%0D`;
se decodifica una sola vez. El orden físico y la revisión del documento unen
cuerpo, ubicación y receta. La consulta vuelve a verificar los bytes al terminar.

`comment-scope` sólo se emite con metadata válida. Sin metadata no se inventa
General ni una ubicación. `status` continúa sin cuerpos ni resolución histórica.
Los registros de `diff --porcelain` no cambian: los clientes unen su receta
con el detalle elegido de `entries` usando ordinal y revisión.

`comment-columns` se emite sólo para selecciones exactas, tanto en `entries`
como en la receta de `diff`. Se asocia por ordinal físico y lado al registro
`comment-location`; sin él se conservan rangos de líneas inclusivos.

## Capacidades de captura y compare (D23)

`comments-capability` se emite sin depender de contexto ni presencia documental.
Describe sólo los destinos admitidos por `init/add` en la sesión consultada:
review emite Local y Shared para cada operación; compare sólo Local; fuera de
sesión no emite capacidades. Consultar otro contexto almacenado no habilita captura.
`--all` no mezcla capacidades de resultados con las de la sesión activa.

Los cuatro clientes filtran por operación y destino; ignoran destinos desconocidos,
no deducen permisos de `kind` ni de rutas y no suponen ambos por ausencia de registros.
Con un destino omiten el selector y lo pasan en `--document`; con varios exigen
elegir en cada captura. Shared preexistente no desaparece ni se vuelve ilegible.

Antes de abortar o limpiar compare se publican los documentos guardados como
resultado local sin código; la publicación fallida preserva la sesión. El checkpoint
`comments save` sigue siendo compatible y opcional; no hay acción de cliente.
