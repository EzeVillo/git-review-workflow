# Research: Contrato de salida legible por programas

El spec dejó deliberadamente fuera de sí mismo toda decisión de formato,
superficie de comandos y códigos de salida (ver
`checklists/requirements.md`, sección *"No implementation details"*). Este
documento resuelve esas decisiones. No hay dependencias externas que
investigar (no se agrega ninguna biblioteca ni herramienta): las preguntas son
todas de diseño interno, resueltas leyendo el código existente
(`bin/git-review-verbs/status`, `bin/git-review-verbs/list`,
`bin/git-review-lib.sh`) y las convenciones de `../../AGENTS.md`.

## Decisión 1: formato de la salida porcelain

**Decision**: Texto plano, una línea por registro, primer campo = etiqueta de
tipo de registro, resto de campos separados por tab. El path (cuando lo hay) va
inmediatamente después de la etiqueta, no al final de la línea. El "why" de una
entrada (prosa arbitraria) nunca entra en estas líneas: sale por un flag propio
(`--why <path>`) que vuelca sólo ese texto a stdout, sin ninguna otra línea
mezclada.

**Rationale**:

- **No hay JSON disponible sin escribirlo a mano.** El contenedor de tests
  (`tests/Dockerfile`, `bats/bats:latest`/Alpine) no tiene `jq` ni Node —
  `tests/packaging.bats:67` lo dice explícitamente al justificar por qué ese
  test usa `sed`/`grep`. El README ya trata "instalar sin Node" como opción de
  primera clase. Serializar JSON a mano en `awk`/`sh` para texto arbitrario (el
  "why") significa reimplementar escaping de comillas/backslashes/saltos de
  línea — exactamente la clase de bug invisible que el proyecto ya sufrió tres
  veces con paths (CRLF, BOM, whitespace; ver las tres "Pending release note"
  en la memoria del proyecto). Evitarlo por diseño es más barato que
  detectarlo después.
- **Mirror git idioms** (regla explícita de `../../AGENTS.md`, "principio rector del
  proyecto"): `git status --porcelain=v2` usa exactamente este esquema —
  líneas etiquetadas, campos de ancho fijo, aditividad documentada ("ignorar
  campos nuevos al final"). `git for-each-ref --format=...` resuelve la
  aditividad dejando que el consumidor pida sólo los campos que conoce. Este
  proyecto ya usa tab como separador de campo con path al final en
  `walk_sequence` (`ord<TAB>path`) precisamente porque un path de git nunca
  contiene un tab literal (`changed_paths` en `git-review-lib.sh:171-173`:
  git cita cualquier byte de control incluso con `core.quotePath=false`). Tab
  es, entonces, un separador ya probado en este código para el mismo dato.
  Ese mismo comentario deja asentado el corolario: un path con `"` o `\` sale
  **citado por git**, con `core.quotePath` en on o en off. El contrato no
  desarma esa cita — emite el path byte a byte tal como lo devuelve
  `changed_paths` (FR-015), porque desarmarla obligaría a reimplementar el
  escaping de git, es decir, exactamente el tercer punto de normalización que
  la feature existe para evitar.
- **Path inmediatamente después de la etiqueta, no al final**: al revés de
  `git status --porcelain`, donde el path va último. La razón es aditividad:
  si el path fuera el último campo, cualquier campo nuevo tendría que
  insertarse *antes* de él, rompiendo a un consumidor que lee "todo lo que
  sigue al tab N-ésimo es el path". Poniendo el path justo después de la
  etiqueta, los campos nuevos sólo se agregan al final de la línea, y un
  consumidor viejo que hace `cut -f1-2` (o el equivalente) para leer
  etiqueta+path nunca se entera de los campos nuevos. Es seguro porque, como
  se estableció arriba, un path de git jamás contiene un tab.

**Alternatives considered**:

- *JSON*: rechazado — requiere una herramienta ausente del entorno soportado
  (viola la restricción explícita del spec de "sin exigir herramientas que hoy
  no requiere"), o un serializador manual que reintroduce el bug de escaping
  que el proyecto lleva tres veces pagado.
- *Formato clave=valor libre (uno por línea, tipo `.env`)*: más simple de leer
  a ojo, pero no resuelve records repetidos (la secuencia es N filas) sin
  inventar un separador de bloque nuevo; el esquema de líneas etiquetadas ya
  resuelve records simples y repetidos con el mismo mecanismo.
- *NUL-separated (`-z`, como `git status -z`)*: más robusto aún (sin ninguna
  restricción sobre bytes en el path), pero innecesario acá porque
  `changed_paths` ya garantiza paths sin tab; añadirlo sería complejidad sin
  un problema real que resuelva, y bats en particular hace mucho más fácil
  escribir asserts sobre líneas de texto que sobre streams NUL-separados.

## Decisión 2: superficie de comandos

**Decision**: No se agrega ningún verbo nuevo. `status --porcelain` cubre
US1 (registro de estado), US2 (registros de secuencia — walk y step, ver
Decisión 3) y US5 (registros de cobertura/no-cubiertos), todo en una sola
invocación. `status --why <path>` cubre US4, por separado (FR-014). `list
--porcelain` cubre US6 (inventario).

**Rationale**: `status` ya es, hoy, "¿cuál es el estado de la review actual?"
— exactamente el mandato de US1/US2/US4/US5. `list` ya es "¿qué reviews hay en
el repo?" — exactamente US6. Emitir varios tipos de registro desde una sola
invocación de `status --porcelain` replica el propio `git status
--porcelain=v2` (una invocación, líneas `#`/`1`/`2`/`u`/`?` mezcladas) y
además supera cómodamente SC-002 ("como máximo 3 invocaciones" para
reconstruir la vista completa: acá alcanza con 1 para estado+secuencia+
cobertura, más 1 por cada "why" que el usuario decida leer). Mantener el
"why" fuera de esa invocación es un requisito explícito (FR-014): la
secuencia es tabular y barata (se pide en cada refresh), el "why" es prosa
que sólo hace falta al abrir una entrada puntual.

**Alternatives considered**:

- *Verbo nuevo (`git review porcelain`, o `git review walkthrough
  list/show`)*: el propio checklist del spec registra que un borrador
  anterior proponía `git review walkthrough list` y lo descartó por ser
  decisión de implementación — es decir, el spec deja la puerta abierta pero
  no la fuerza. Se rechaza como verbo dedicado porque el dato (secuencia)
  aplica también a modo *step* (Q2 = C), que no tiene nada que ver con
  `walkthrough`; atarlo a ese verbo mezclaría dos conceptos. Extender
  `status`, que ya es agnóstico al modo, es más simple y no agrega superficie
  al dispatcher.

## Decisión 3: secuencia unificada para walk y step (Q2 = C)

**Decision**: `status --porcelain` emite registros `entry` tanto en modo walk
(un registro por path de la secuencia, con marca de esencial) como en modo step
(un registro por commit del rango, con marca de "tiene edición bancada").
Ambos comparten el mismo tipo de registro (`entry`) con un campo adicional
específico de cada modo, **omitido** —no vacío— cuando no aplica (aditivo: un
consumidor que sólo entiende walk puede ignorar el campo de "bancado" y
viceversa). La omisión, y no el campo vacío, es lo que pide el spec: el
Acceptance Scenario 2 de US1 exige que la ausencia de un campo no se confunda
con un valor vacío legítimo. Vale para todo el contrato, no sólo para `entry`.

**Rationale**: la respuesta ya fijada en el spec para Q2 es la opción C
("Step expone secuencia, y además qué pasos tienen ediciones guardadas"). El
dato de "bancado" ya se calcula hoy en la ruta humana de `status`
(`refs/review-edits/$src/$i`, línea ~85 de `bin/git-review-verbs/status`);
exponerlo es reusar, no inventar.

**Alternatives considered**: tipos de registro separados (`entry-walk` /
`entry-step`) — rechazado por ser distinción sin diferencia: ambos son "la
secuencia de esta review, en orden, con un flag"; el consumidor ya sabe el modo
por el registro `state`, así que no necesita un tipo de línea distinto para
saber cómo interpretar el flag.

## Decisión 4: distinguir "no hay walkthrough" de "walkthrough inaplicable" sin estado nuevo

**Decision**: derivar la distinción en el momento de la consulta, no
persistirla. Con el review en modo `whole`: si `walk_read "$tip"` no devuelve
nada → no había walkthrough. Si devuelve contenido pero
`walk_sequence "$tip" "$(git rev-parse HEAD)"` es vacío → había walkthrough
pero ninguna entrada cae en el rango (degradado).

En modo `step` el campo vale siempre `none`. No es un dato omitido: `state` es
posicional, así que omitirlo correría todos los campos siguientes. `none` es
además literalmente cierto —una review step no tiene walkthrough aplicado— y
si algún día hace falta distinguir "el PR no traía walkthrough" de "traía uno
pero step no lo usa", se agrega un valor nuevo (`ignored`) sin romper a nadie:
un consumidor que no lo conozca lo tratará como "no aplicado", que es la
lectura correcta. Derivarlo en step, además, sería incorrecto de entrada: el
truco de `git rev-parse HEAD` como límite inferior no vale ahí, porque en step
HEAD avanza commit a commit en vez de quedarse clavado en la base.

`git rev-parse HEAD` alcanza como límite inferior sin recalcular nada más:
`start` deja HEAD parado exactamente en `lower` para *todo* modo no-step
(`git reset -q --soft "$lower"` en `bin/git-review-verbs/start`, antes de la
bifurcación walk/whole) — el mismo truco que `load_walk_review_meta` ya usa
para walk (`git-review-lib.sh:432`) vale igual para whole, sin distinguir los
dos casos ni tocar `reviewbase`/`fold_lower`/resolución de remoto en absoluto.

**Rationale**: la responsabilidad "sin estado nuevo persistido" (asunción
explícita del spec) obliga a esto — el dato ya es derivable con los mismos
helpers que usa `start` para decidir si degradar (`walk_read`, `walk_sequence`,
y el hecho ya establecido de que HEAD == lower en reposo), así que exponerlo
no crea una segunda fuente de verdad (FR-005) ni requiere extraer ninguna
lógica de resolución de base nueva.

## Decisión 5: códigos de salida (US3, FR-023)

**Decision**: `0` éxito; `2` reservado para "no hay review activa" (HEAD no
está en `review/*`); `3` para "el cursor quedó fuera del rango vigente porque
HEAD se movió de la base" (el drift recuperable que hoy diagnostica
`walk_range_error`); `1` para cualquier otro error, incluida la rama `review/*`
sin metadata o con metadata corrupta, los argumentos inválidos y el "no es un
repo git".

El alcance es **toda la CLI**, no sólo las superficies nuevas (FR-017, FR-023):
un mismo hecho no puede tener dos códigos según quién lo detecte. En concreto:

- El `2` va a los siete puntos que hoy emiten "not on a review/\* branch":
  `git-review-lib.sh:39` (`load_step_review_meta`), `git-review-lib.sh:411`
  (`load_walk_review_meta`), y los verbos `abort`, `finish`, `preview`, `save`
  y `status`.
- El `3` va a la rama de drift de `walk_range_error` (`git-review-lib.sh:380`),
  que alcanza a `status` y —vía `load_walk_review_meta`— a `next` y `prev`. La
  otra rama de esa misma función, la de corrupción genuina, se queda en `1`.
- En modo `step` no hay `3`: un cursor fuera de rango ahí es siempre corrupción
  (HEAD avanza por diseño, no hay base de la que salirse), así que
  `load_step_review_meta` y `goto_step` quedan como están.

Ni el modo humano ni el texto de un solo mensaje cambian: cambia el código con
el que se sale después de imprimirlo.

Una rama `review/*` hecha a mano, sin `reviewsource`/`reviewtip`, es error
(`1`) y **no** "no hay review activa" (`2`): HEAD sí está parado en algo que
dice ser una review, y el usuario necesita enterarse. `2` significa
literalmente "acá no hay nada que mostrar y eso es normal" — el caso más
frecuente de todos, y el único en el que un consumidor debe quedarse callado.

**Rationale**: los tests existentes que cubren estos caminos
(`tests/errors.bats:110-142`) sólo aseveran `[ "$status" -ne 0 ]`, nunca el
valor exacto; no hay ningún test que fije hoy el código en `1` para el caso
"fuera de una review". Eso deja introducir el `2` sin tocar una sola aserción
existente, y sin necesitar dos contratos de código de salida distintos según el
flag — más simple y más git-idiomático (el propio git usa códigos pequeños con
significado propio: `grep` 0/1/2, `diff --exit-code` 0/1).

El `3` sí cuesta dos aserciones: `tests/walk.bats:194` (`next` tras el drift) y
`tests/walk.bats:201` (`status` tras el drift) fijan hoy `[ "$status" -eq 1 ]`.
Las dos pasan a `-eq 3`; ningún `[[ "$output" == ... ]]` se toca. `walk.bats:220`
—corrupción genuina con HEAD en la base— se queda en `1` y es justamente la
prueba de que las dos ramas de `walk_range_error` siguen separadas. SC-008 se
reformuló para decir lo que siempre quiso decir: lo intocable es el **texto**
que lee la persona, no el código de salida, que es dato y que FR-017/FR-023
cambian a propósito. Sostener la letra anterior habría obligado a la única
alternativa que respeta cero aserciones —emitir el `3` sólo bajo `--porcelain`—
es decir, dos contratos de exit code según el flag: exactamente la complejidad
que esta decisión evita.

La distinción entre
"error" y "no es un repo git" (escenario 3 de US3) no necesita un tercer código
propio: el spec sólo exige que no se confunda con "no hay review", y comparten
el `1` de error genérico sin violar eso.

El `3` sale de FR-023 y del edge case "cursor fuera de rango" del spec. El
código ya distingue las dos causas —`walk_range_error`
(`git-review-lib.sh:380-401`) compara el total vigente contra el
`reviewwalkcount` registrado al iniciar y emite un diagnóstico accionable
("HEAD se movió de la base, deshacelo con `git reset --soft`") o el genérico de
corrupción— pero las dos ramas salen hoy con `1`, así que la distinción existe
sólo en la prosa. Dársela al `3` es exponer una decisión ya tomada, no
inventar una nueva: el drift es recuperable por el usuario y merece un aviso
accionable; la corrupción no lo es. Sin esto, US3 queda técnicamente cumplida
pero el consumidor sigue obligado a buscar frases en inglés para el caso que
más lo va a golpear (un `git commit` de más sobre una review walk).

**Alternatives considered**:

- *Un cuarto código específico para "no es un repositorio git"*: rechazado por
  sobre-especificar algo que el spec no pide (la escena 3 de US3 sólo exige "no
  confundirse con no-hay-review", no "tener su propio código").
- *Reportar el drift como un valor más del campo `walkthrough` con exit `0`*:
  rechazado porque obligaría a emitir un registro `state` con un cursor
  inválido (`position` > `total`) como si fuera un dato normal. Un estado
  inconsistente no es un estado; es una condición de salida.

## Decisión 6: `total` derivado y `recorded` registrado, como campos distintos

**Decision**: en el registro `state` de los modos con cursor, `total` es el
total **derivado en el momento de la consulta** (la cantidad de líneas `entry`
de esa misma salida) y `recorded` es el guard que se persistió al iniciar la
review (`reviewwalkcount` en walk, `reviewcount` en step). Son dos campos
separados, ambos presentes siempre que haya cursor.

**Rationale**: hoy la ruta humana de `status` mezcla los dos —imprime
`[%s/%s]` con el guard (`${walkcount:-$total}`) pero valida el rango contra el
derivado— y en reposo coinciden, así que la diferencia nunca se ve. Bajo drift
divergen, y ahí un solo campo obliga a elegir entre dos defectos: si `total`
es el guard, contradice la cantidad de líneas `entry` de su propia salida
(un consumidor que confíe en él pinta una barra de progreso sobre entradas que
no existen); si es el derivado, el panel dice un número distinto del que el
usuario está viendo en la terminal. Con los dos campos no hay que elegir, y el
consumidor detecta el drift comparándolos sin pedir nada más — el mismo dato
con el que `walk_range_error` ya decide qué diagnóstico emitir. El costo es un
campo, y ninguna lectura nueva: los dos valores ya se calculan en la ruta
actual.

**Alternatives considered**: exponer sólo el derivado y dejar que el consumidor
infiera el drift por el exit `3` — rechazado porque el `3` es una condición de
salida terminal (no se emite `state` en absoluto), así que no cubre el caso
donde el cursor sigue en rango pero la secuencia ya se achicó.

## Decisión 7: en el inventario, `position`/`total` salen de la config

**Decision**: `list --porcelain` toma `position` y `total` de las claves de
config de cada rama (`reviewstep`/`reviewcount`, `reviewwalkstep`/
`reviewwalkcount`), igual que hace hoy `describe()` para la salida humana. No
re-deriva la secuencia. Si la clave no está, el campo se omite — nunca se
emite el `?` que la salida humana usa como relleno visual.

**Rationale**: derivar exigiría, por cada rama del repositorio, leer su
walkthrough (`git show`) y diffear su rango (`git diff --name-only`) — en walk,
además, resolviendo el límite inferior de una rama en la que no estamos parados.
El inventario es la superficie menos crítica de la feature (US6 es P4,
"comodidad" según el propio spec) y la que más ramas toca de una vez. El dato
de config es exactamente el que ya se le muestra al usuario, así que panel y
terminal no pueden contradecirse. Un consumidor que necesite el número exacto
de una review concreta tiene `status --porcelain` sobre ella, que sí deriva.

**Alternatives considered**: emitir `?` como hace `list` humano — rechazado:
en la salida humana `?` es un relleno visual legible, en un contrato es un
valor no numérico que todo consumidor tendría que manejar como caso especial.
Omitir el campo ya significa "no hay dato" sin inventar un centinela (misma
regla que el resto del contrato, Decisión 3).
