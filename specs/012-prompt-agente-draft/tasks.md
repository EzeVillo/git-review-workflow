---

description: "Task list for 012-prompt-agente-draft"
---

# Tasks: El borrador del revisor, escrito por un agente

**Input**: Design documents from `/specs/012-prompt-agente-draft/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: incluidos y **no opcionales**. `CLAUDE.md` los exige como estándar del
proyecto (asserts fuertes, sin falsos positivos, efecto real sobre el estado de
git verificado) y CI corre las suites en ubuntu, macOS y Windows.

**Organization**: agrupadas por user story. Dentro de las que abarcan CLI y
cliente (US3), las secciones respetan el orden de fases de
[plan.md](plan.md) § *Fases de entrega*: la CLI primero, porque ningún cliente
puede consumir una superficie que la CLI todavía no expone.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: puede ir en paralelo (archivos distintos, sin dependencias pendientes)
- **[Story]**: a qué user story pertenece (US1..US5)
- Cada tarea nombra su archivo exacto

## Path Conventions

Monorepo, según [plan.md](plan.md) § Project Structure: CLI de shell en `bin/`,
suites bats en `tests/`, canónico multi-cliente en `contracts/` y
`scripts/`, extensión en `vscode-extension/`, plugin en `jetbrains-plugin/`,
extensión de Visual Studio en `visualstudio-extension/`.

**Recordatorios que aplican a toda la lista**:

- Shell POSIX (`sh`) con `set -eu`, sin bashisms. Todo script pasa
  `./lint-docker.sh` (shellcheck). Nada de `A && B || C` (SC2015): guardas con
  `if` invertido. Ediciones in-place vía archivo temporal (patrón `sed_i`).
- Las suites se corren **en el contenedor**: `./tests/run-docker.sh` y
  `./vscode-extension/test/run-docker.sh`. Nunca bats bajo Git Bash.
- Los nombres de `@test` van en **ASCII puro** (sin acentos ni em dashes);
  `tests/test-names.bats` lo verifica sobre toda la suite.
- Cada caso de error afirma **exit code + mensaje en stderr + ausencia de efecto
  colateral** (el borrador anterior byte por byte).
- Los **dos** README (`README.md` y `README.es.md`) se tocan siempre juntos, en
  el mismo cambio que el comportamiento que documentan.
- **Prohibido en todo el bloque de instrucciones**: `..` / `...` entre los dos
  extremos, y `git log` / `git rev-list` / `git shortlog` / `git range-diff`
  (research § Hallazgo 0 — con un `lower` de tipo tree no fallan: mienten).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: baseline verde y un sandbox capaz de mostrar los estados nuevos.

- [ ] T001 Tomar baseline en verde antes de tocar nada: `./lint-docker.sh`, `./tests/run-docker.sh`, `node scripts/check-client-product-surface.mjs` y `cd vscode-extension && npm run test:unit`. Anotar los conteos (bats, unit) para poder distinguir una regresión de un test nuevo
- [ ] T002 [P] Extender `tests/sandbox.sh` con una rama `feature/merged-base` sin walkthrough cuya historia **mergea la base adentro** (`develop` mergeado dentro de la rama), para poder recorrer a mano el caso de `lower` = tree OID de [quickstart.md](quickstart.md) § Escenario 2; documentarla en el texto de salida del script junto a `feature/telemetry` y `feature/pagos`. Encaja con lo que ese script ya hace —arma una rama por cada estado que el PR de juguete no puede mostrar— y vale la pena porque **es el caso que se diagnosticó mal tres veces seguidas**: poder mirarlo a mano es la diferencia entre razonar sobre él y medirlo. El nombre de la rama es normativo: el quickstart lo usa literal

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: el generador y el reconocedor del bloque, más el fixture de rango
sintético. **Bloquea US1 y US2**: la primera lo escribe, la segunda lo tiene que
conservar al instalar contenido externo.

**⚠️ CRÍTICO**: completar antes de empezar cualquier user story.

- [ ] T003 Implementar **dos** helpers en `bin/git-review-lib.sh`, porque generar y consumir son cosas distintas: `walk_emit_prompt_block` (**genera** el bloque a partir de `tip`, `lower`, la etiqueta, `<lower-kind>`, la situacion del arbol y los flags de origen/rango — unico generador, lo llaman `init`, `draft` y la reescritura) y `walk_prompt_block` (**consume** el bloque entrante del contenido para que la reescritura no lo arrastre ni lo duplique). Reconocimiento y region, según [contracts/walkthrough-prompt-block.md](contracts/walkthrough-prompt-block.md) § La pieza: reconocimiento por prefijo exacto con `index($0, "<!-- git-review-range:") == 1`, región limitada al preámbulo (corta en el primer `## N. ` / `## ?. `), cierre en el `-->`, **sólo el primero** si hay más de uno. Un `awk`, cero procesos por entrada
- [ ] T004 **No tocar `walk_preamble`** en `bin/git-review-lib.sh` (research § Hallazgo 1): dejar constancia en el comentario de `walk_prompt_block` de que el filtrado al leer ya lo hace `walk_preamble` para sus tres llamadores, y que este helper es un agregado de la reescritura, no una variante de aquélla. Anotar también que `status --why` **no** pasa por `walk_preamble` —nunca muestra el preámbulo— así que ahí el bloque tampoco se ve, pero por otro motivo: quien lea el comentario no debe concluir que ese camino está cubierto por el filtro
- [ ] T005 [P] Crear `tests/walkthrough-prompt-block.bats` con su `setup()` propio (el repo no tiene un helper compartido: cada archivo bats arma su repositorio, ver `tests/walkthrough-draft.bats`), incluyendo una rama cuyo rango de review tenga el límite inferior en un **tree OID** —la base mergeada dentro del PR, el caso que dispara `resolve_lower_bound` con `merge-tree --write-tree` ([bin/git-review-lib.sh:387](../../bin/git-review-lib.sh))— y un `@test` que afirme con `git cat-file -t` que ese lower es efectivamente `tree`. Sin este fixture, el caso central de FR-003 no se puede probar

**Checkpoint**: el bloque se reconoce y se puede extraer, pero todavía nadie lo
escribe.

---

## Phase 3: User Story 1 — El esqueleto ubica el cambio (Priority: P1) 🎯 MVP

**Goal**: que un agente que recibe el esqueleto anote el contenido **posterior**
al PR, desde la terminal, sin ningún cliente. Es la corrección de un error
silencioso.

**Independent Test**: [quickstart.md](quickstart.md) § Escenario 1 — generar el
esqueleto para un PR que *modifica* un archivo existente, comprobar que los dos
extremos resuelven con `git cat-file -e`, que el bloque no contiene un rango con
`..`, y que `git show <tip>:<path>` difiere del contenido del árbol de trabajo.

### Detección de situación y de tipo de objeto

- [ ] T006 [US1] En `bin/git-review-verbs/walkthrough`, resolver **una vez**, antes del parseo de la rama (o sea antes del bloque `if [ "$sub" = draft ]` de [walkthrough:208](../../bin/git-review-verbs/walkthrough)), si `HEAD` es una rama `review/*`, en una variable propia (p. ej. `head_in_review`). **No reusar `from_review`**: sólo vale 1 cuando el revisor omitió la rama ([walkthrough:220-229](../../bin/git-review-verbs/walkthrough)), así que `git review walkthrough draft feature/x` parado dentro de `review/feature/x` elegiría la frase equivocada — el desacuerdo que SC-002 prohíbe. `from_review` queda como está, sólo para derivar el nombre de la rama
- [ ] T007 [US1] En `bin/git-review-verbs/walkthrough`, resolver `<lower-kind>` con **un solo** `git cat-file -t "$lower"` (`commit` o `tree`), únicamente en el camino de generación del esqueleto — nunca en `--build` ni en ningún camino caliente

### El bloque

- [ ] T008 [US1] Escribir el bloque `<!-- git-review-range: ... -->` en el generador de esqueleto compartido de `bin/git-review-verbs/walkthrough` ([walkthrough:392-486](../../bin/git-review-verbs/walkthrough)), **inmediatamente después de `# Walkthrough`** y antes del comentario de andamiaje, con las cuatro secciones de [contracts/walkthrough-prompt-block.md](contracts/walkthrough-prompt-block.md) § Contenido byte a byte: encabezado y alcance, los dos extremos resueltos (`tip` / `lower` + `<tip-label>` + `<lower-kind>`), la frase de situación y los cuatro comandos. **Una sola cadena** para los dos lados, con los mismos dos pasajes conmutados inline que el esqueleto ya conmuta ([walkthrough:459-471](../../bin/git-review-verbs/walkthrough)) — dos copias derivarían y la deriva sería invisible (FR-007)
- [ ] T009 [US1] Implementar en `bin/git-review-verbs/walkthrough` la elección de **exactamente una** de las tres frases de situación de [contracts/walkthrough-prompt-block.md](contracts/walkthrough-prompt-block.md) § 3: `init` → «standing on the PR branch»; `draft` con `head_in_review = 0` → «standing on the base branch»; `draft` con `head_in_review = 1` → «inside an active review». La tercera **no** promete que el árbol tenga el PR completo (en modo `step` lo tiene sólo hasta el cursor) y remite a los comandos. Cerrar la sección en los tres casos con la regla de FR-006 («write the reading order over the range above, not over what your working tree happens to contain»)
- [ ] T010 [US1] Agregar en `bin/git-review-verbs/walkthrough` la línea de rango incremental cuando `--delta` está activo (FR-005): el bloque dice que cubre sólo lo agregado desde la review anterior de `<branch>`, y su `base` es el marcador previo (`$start` = `$prev`), no la merge-base
- [ ] T010a [US1] Agregar al bloque, en `bin/git-review-verbs/walkthrough`, la línea `Generated with: <flags>` con los flags de origen y rango **normalizados en orden fijo** (`--local` | `--offline`, después `--delta`) o el literal `(defaults)`, según [contracts/walkthrough-prompt-block.md](contracts/walkthrough-prompt-block.md) § 2b. **No es decorativa**: es la única casa de ese dato, la lee el registro `draft` de `config --porcelain` y la replica *Validate and start* del panel. Sin ella ese botón falla **siempre** sobre cualquier borrador hecho con `--delta`, `--local` u `--offline` (FR-005a, FR-029a)
- [ ] T011 [US1] Retirar de `bin/git-review-verbs/walkthrough` **las dos** notas del andamiaje que nombran el rango con palabras: la de `draft`, que dice literalmente `(base..tip)` ([walkthrough:461](../../bin/git-review-verbs/walkthrough)) y es el texto que la spec señala como el problema, **y la de `init`, que dice `(base..HEAD)`** ([walkthrough:466](../../bin/git-review-verbs/walkthrough)). `base` ahí es una palabra literal, no una ref: es exactamente la «palabra generica» que FR-001 prohibe, y FR-007 pide el mismo tratamiento en lo que aplique. Las dos se reemplazan por una redaccion en prosa que remita al bloque, que es el unico lugar donde el rango se nombra con objetos
- [ ] T012 [US1] En la reescritura canónica de `bin/git-review-verbs/walkthrough` ([walkthrough:698-758](../../bin/git-review-verbs/walkthrough)): consumir el bloque entrante con `walk_prompt_block` (para que no se duplique ni se cuele al preámbulo) y **emitir uno nuevo** con `walk_emit_prompt_block`, usando el `tip` y el `lower` que **esa misma corrida** resolvió para el chequeo de deriva, **entre `# Walkthrough` y el preámbulo**. Sirve por igual a `build` (autor) y a `draft --build` (revisor). **Regenerar, no arrastrar**: un bloque arrastrado sobrevive al cambio del rango y queda describiendo uno viejo, y la deriva no lo detecta si el conjunto de paths no cambió. Con `--check` no se emite nada, porque `--check` no escribe. Verificar que el bloque no altera ninguna de las ocho reglas de validación: las dos anclas de comentario son `^<!-- why` y `^<!-- heads-up`, y las líneas del bloque van indentadas

### Tests (bats, en el contenedor)

- [ ] T013 [P] [US1] `tests/walkthrough-prompt-block.bats`: los dos extremos del bloque son objetos resolubles — extraerlos del archivo y afirmar `git cat-file -e` con exit 0 sobre los dos, y que `<lower-kind>` coincide con `git cat-file -t "$lower"`
- [ ] T014 [P] [US1] `tests/walkthrough-prompt-block.bats`: **ninguna línea del bloque** contiene `..` ni `...` entre los dos extremos, ni `git log` / `git rev-list` / `git shortlog` / `git range-diff`. Afirmarlo en los cuatro orígenes: remoto, `--local`, `--offline` y `--delta`. **El grep va acotado al bloque** (de la línea `<!-- git-review-range:` hasta su `-->`), no al archivo entero: el andamiaje del esqueleto contiene `(1, 2, 3, ...)` y haría pasar un test que en realidad no mira nada
- [ ] T015 [P] [US1] `tests/walkthrough-prompt-block.bats`: con el fixture de T005 (lower = tree OID) el bloque se genera igual, dice `tree` en `<lower-kind>`, y **sus comandos funcionan**: `git show <tip>:<path>` y `git diff <lower> <tip> -- <path>` devuelven contenido no vacío y exit 0
- [ ] T016 [P] [US1] `tests/walkthrough-prompt-block.bats`: seguir el comando devuelve el contenido del PR — sobre un archivo que el PR **modifica** (no que agrega), afirmar que `git show <tip>:<path>` **difiere** del contenido del árbol de trabajo (SC-001, FR-002)
- [ ] T017 [P] [US1] `tests/walkthrough-prompt-block.bats`: las tres frases de situación. Desde la base sale la de base; **con la rama nombrada explícitamente desde adentro de `review/<branch>`** sale la de review (el caso que `from_review` erraría); `init` sale la de autor con el mismo cuerpo de comandos
- [ ] T018 [P] [US1] `tests/walkthrough-prompt-block.bats`: supervivencia e idempotencia — tras `draft --build` el bloque está presente **una sola vez**; tras un segundo `draft --build` el archivo es **byte por byte** idéntico al anterior (`cmp`). Lo mismo del lado del autor con `walkthrough build`
- [ ] T018a [P] [US1] `tests/walkthrough-prompt-block.bats`: **la reescritura regenera** — commitear en la rama del PR un cambio que toque **los mismos paths** (o sea sin deriva), correr `draft --build --force` y afirmar que el `tip` del bloque es el **nuevo**, no el viejo. Es el único test que distingue regenerar de preservar, y cubre el caso que la validación de deriva no ve (SC-018)
- [ ] T018b [P] [US1] `tests/walkthrough-prompt-block.bats`: un bloque escrito a mano en la entrada **no se duplica ni se cuela al preámbulo** — el archivo sale con un solo bloque y `start` no imprime ninguna de sus líneas como heads-up
- [ ] T018c [P] [US1] `tests/walkthrough-prompt-block.bats`: `draft --build --check` deja el archivo **byte por byte** igual (`cmp`), bloque incluido: `--check` no escribe
- [ ] T018d [P] [US1] `tests/walkthrough-prompt-block.bats`: **el rango incremental** (FR-005, hoy sin test que lo verifique) — con `--delta`, el bloque contiene la frase de rango incremental **y** su `<lower-oid>` es **igual** al valor de `git config reviewworkflow.<branch>.reviewed`. Afirmar la igualdad contra la clave, no que «hay un SHA»: es lo único que distingue un incremental correcto de uno que cubre el PR entero
- [ ] T018e [P] [US1] `tests/walkthrough-prompt-block.bats`: **la línea `Generated with:`** (FR-005a) en los cinco orígenes — `(defaults)`, `--local`, `--offline`, `--delta`, `--local --delta` — con el orden normalizado exacto
- [ ] T018f [P] [US1] `tests/walkthrough-prompt-block.bats`: **la regla de cierre de FR-006** está presente en los tres casos de situación: el bloque contiene la frase que manda anotar sobre el rango y no sobre lo que el árbol contenga. Sin este test, FR-006 se implementa en T009 y nada lo verifica
- [ ] T019 [P] [US1] `tests/walkthrough-prompt-block.bats`: el bloque nunca se le muestra al revisor — `git review start` no imprime ninguna línea del bloque y `git review status --why <path>` tampoco; un preámbulo con bloque **y** heads-up imprime sólo el heads-up; un preámbulo con **sólo** el bloque no imprime un heads-up vacío
- [ ] T020 [P] [US1] `tests/walkthrough-prompt-block.bats`: neutralidad para la validación — un borrador válido valida igual con y sin bloque (exit 0 en los dos), borrarlo a mano no invalida nada (`--build` exit 0 y `start` entra en walk), y los mensajes de las ocho reglas de rechazo son idénticos con y sin bloque

### Documentación

- [ ] T021 [P] [US1] Documentar el bloque de instrucciones en `README.md`: qué es, que sobrevive a la construcción, que nunca se le muestra al revisor ni se renderiza en el PR, y que sus comandos son descriptivos — el producto no ejecuta nada (FR-008, FR-037)
- [ ] T022 [P] [US1] Espejar exactamente ese cambio en `README.es.md` — los dos README se actualizan **siempre** juntos
- [ ] T023 [US1] **Control, no edición**: verificar en `docs/index.html` que el demo interactivo del formato del walkthrough sigue siendo fiel. El bloque es la única pieza del formato que nunca se muestra, así que la landing **no se toca**; si el demo hubiera que cambiarlo, el diseño se desvió del plan (plan § Constitution Check)
- [ ] T024 [US1] Correr `./lint-docker.sh` y `./tests/run-docker.sh walkthrough-prompt-block.bats walkthrough.bats walkthrough-draft.bats walk.bats` en verde

**Checkpoint**: US1 entregable sola. Un agente ya puede anotar un PR correctamente
desde la terminal.

---

## Phase 4: User Story 2 — El agente no escribe dentro del directorio de git (Priority: P1)

**Goal**: el circuito completo con un agente en sandbox, desde la terminal:
esqueleto por stdout, completado afuera, instalado con una sola invocación.

**Independent Test**: [quickstart.md](quickstart.md) §§ Escenarios 4 a 6.

**Depends on**: US1 sólo para que lo que sale por `--stdout` ya traiga el bloque.
El resto es independiente.

### Parseo y matriz de flags

- [ ] T025 [US2] Agregar `--stdout` y `--from <file>` / `--from=<file>` al parseo de `bin/git-review-verbs/walkthrough`, con la guarda de `--from` repetido y la de `--from` sin valor, y actualizar el `usage()` con las dos formas de invocación de [contracts/cli-walkthrough-draft-io.md](contracts/cli-walkthrough-draft-io.md) § Invocación
- [ ] T026 [US2] Implementar en `bin/git-review-verbs/walkthrough` la matriz de compatibilidad completa de [contracts/cli-walkthrough-draft-io.md](contracts/cli-walkthrough-draft-io.md), con los mensajes exactos: `--stdout` + `--build`, `--stdout` + `--force`, `--stdout` + `--from`, `--from` sin `--build`, `--from` dos veces, `--from` sin valor, y `--stdout`/`--from` en `init`/`build` (sumado a la guarda que ya existe en [walkthrough:144-146](../../bin/git-review-verbs/walkthrough)). Todas **antes de tocar nada**, con `if` invertido (nada de SC2015)
- [ ] T027 [US2] Modificar la guarda de `--force` con `--build` de [walkthrough:162-164](../../bin/git-review-verbs/walkthrough): con `--from` pasa a ser **legal** (ahí sí se reemplaza prosa por otra prosa, FR-016); sin `--from` sigue siendo el error de hoy, byte por byte

### `--stdout`

- [ ] T028 [US2] Implementar `--stdout` en el camino de generación de esqueleto de `bin/git-review-verbs/walkthrough`: emitir por stdout **byte por byte** lo que el archivo tendría, sin ejecutar el `mkdir -p`, sin el `: >"$tmp"`, sin el `mv` y **sin instalar los traps** de limpieza. La guarda de «ya existe» no aplica: imprimir no destruye, así que un borrador existente se imprime igual con exit 0 y queda intacto
- [ ] T029 [US2] En `bin/git-review-verbs/walkthrough`, suprimir con `--stdout` la línea informativa «wrote … with N file(s) …» y mandar a **stderr** todo lo demás (nota de precedencia sobre el walkthrough del autor, nota del archivado huérfano, guía de autoría opcional), de modo que `git review walkthrough draft --stdout feature/x > order.md` produzca un archivo válido sin filtrar nada
- [ ] T029a [US2] **Conmutar la línea de cierre del andamiaje** bajo `--stdout` en `bin/git-review-verbs/walkthrough` ([walkthrough:463](../../bin/git-review-verbs/walkthrough)): sin `--stdout` sigue diciendo `git review walkthrough draft --build <flags> <branch>`; **con** `--stdout` pasa a `git review walkthrough draft --build --from <file> <flags> <branch>` (y menciona `--from -`). Sin esto el esqueleto le indica al agente un comando que, o muere con `no draft for <branch>`, o —si esa rama ya tenía borrador— **valida y reescribe ese otro archivo** ignorando lo que el agente acaba de producir, con exit 0 y mensaje de éxito. Es el fallo silencioso que la feature viene a eliminar, escrito por nosotros (FR-006a, SC-016)
- [ ] T030 [US2] Verificar en `bin/git-review-verbs/walkthrough` que los errores previos a la escritura (`no base set`, `<src> not found`, `no changes vs <base>`, `--delta` sin marcador) siguen saliendo con exit 1 y **stdout vacío** bajo `--stdout`: nunca se imprime un esqueleto vacío

### `--build --from`

- [ ] T031 [US2] Reordenar las guardas del camino `build` de `bin/git-review-verbs/walkthrough` según [contracts/cli-walkthrough-draft-io.md](contracts/cli-walkthrough-draft-io.md) § Orden de las guardas: flags → rama/base/tip/rango → **existencia del borrador previo vs `--force`** → lectura de la fuente → vacío → las ocho reglas → escritura. La guarda de existencia va **antes de leer la entrada**: negarse después de consumir stdin deja al llamador sin forma de reintentar
- [ ] T032 [US2] Ajustar en `bin/git-review-verbs/walkthrough` la guarda `[ -e "$targetpath" ] || die "no draft for $branch..."` de [walkthrough:545-550](../../bin/git-review-verbs/walkthrough) para que sólo aplique **sin** `--from`: con `--from`, la ausencia de borrador previo es el caso normal (se instala fresco) y la **presencia** sin `--force` es el error `already exists; pass --force to overwrite`
- [ ] T033 [US2] Implementar en `bin/git-review-verbs/walkthrough` la lectura de la fuente: `--from <file>` con comprobación de legibilidad **previa** (para poder nombrar el archivo en `could not read <file>`, FR-018) y `--from -` desde stdin, los dos pasando por `walk_normalize` (CR final y BOM UTF-8 — un agente que escriba desde PowerShell produce los dos, y sin esto el drift nombraría el mismo archivo de los dos lados)
- [ ] T034 [US2] Implementar la guarda de TTY en `bin/git-review-verbs/walkthrough`: `--from -` con `[ -t 0 ]` verdadero muere con la explicación de FR-017 en vez de colgarse. `[ -t 0 ]` es POSIX y builtin — cero procesos
- [ ] T035 [US2] Implementar el rechazo de entrada vacía o de puro whitespace en `bin/git-review-verbs/walkthrough` (FR-015), con el origen nombrado en el mensaje y sin instalar nada
- [ ] T036 [US2] Sumar al paso de escritura del `build` de `bin/git-review-verbs/walkthrough` lo que hoy sólo vive en la rama del esqueleto: `mkdir -p "$(dirname "$targetpath")"` (el namespace puede no existir, y un nombre con `/` es un subdirectorio), la guarda de nombre de archivo reservado (`if ! : >"$tmp"`, mismo mensaje que ya existe), y los traps `EXIT`/`INT`/`TERM` con los `exit 130` / `exit 143` — un Ctrl-C no puede dejar un `.tmp.NNN` que nada recoge (`walk_draft_list` sólo matchea `*.md`, `clean` es hands-off ahí, `forget --draft` sólo deletrea nombres)
- [ ] T037 [US2] Confirmar en `bin/git-review-verbs/walkthrough` que **ninguna** regla de validación cambia con `--from` (FR-013): el mismo cuerpo, las mismas ocho reglas, contra el mismo rango resuelto por los mismos flags de origen y rango. Lo único que cambia es de dónde sale `$content`

### Tests (bats, en el contenedor)

- [ ] T038 [P] [US2] `tests/walkthrough-draft-io.bats`: `--stdout` no crea nada — el namespace no existe antes ni después, `git status --porcelain` idéntico byte por byte, exit 0 y stdout no vacío; y la salida capturada es **idéntica** (`cmp`) al archivo que produce el mismo comando sin `--stdout`
- [ ] T039 [P] [US2] `tests/walkthrough-draft-io.bats`: `--stdout` sobre una rama que ya tiene borrador sale 0, imprime, y deja el borrador **byte por byte** igual; con un nombre de rama reservado en Windows (`nul`) sale 0 porque no se escribe nada; sin base / rama inexistente / sin cambios sale 1 con el mensaje de siempre y **stdout vacío**
- [ ] T040 [P] [US2] `tests/walkthrough-draft-io.bats`: instalar desde archivo — exit 0, el archivo canónico existe con el contenido renumerado, y `git review start` entra en modo walk sobre él. Instalar el mismo contenido desde stdin produce un archivo canónico **byte por byte idéntico** (`cmp` entre los dos)
- [ ] T041 [P] [US2] `tests/walkthrough-draft-io.bats`: paridad de custodia (SC-003) — tras instalar por las dos vías, `git review status` dice `walk (draft)`, `git review list` marca la fila, `save` mueve el archivo al namespace archivado, `continue` lo devuelve y `forget --draft` lo borra, exactamente igual que con un borrador escrito en el lugar
- [ ] T042 [P] [US2] `tests/walkthrough-draft-io.bats`: atomicidad (FR-014, SC-004) — con un borrador previo guardado en una copia, cada uno de estos rechazos deja el archivo **byte por byte** como estaba: sin `--force`, entrada vacía, entrada de puro whitespace, archivo inexistente, archivo ilegible (se salta en Windows), y cada regla de validación (placeholder, `## ?.`, duplicado, `> key` con valor, drift). En todos: exit 1 + mensaje en stderr + `cmp` en verde contra la copia
- [ ] T043 [P] [US2] `tests/walkthrough-draft-io.bats`: `--from -` con stdin de terminal no cuelga — exit 1 con la explicación de FR-017. Forzar la rama sin depender de un TTY real (redirigir un `/dev/tty` no disponible, o el mecanismo que el runner permita); si no hay forma portable, probar la guarda con un stub y dejarlo dicho en el comentario del test
- [ ] T044 [P] [US2] `tests/walkthrough-draft-io.bats`: toda la matriz de flags ilegales de T026 — cada combinación afirma exit 1, su mensaje exacto en stderr, y que **no hubo efecto** (ni archivo creado ni borrador modificado)
- [ ] T045 [P] [US2] `tests/walkthrough-draft-io.bats`: una fuente con CRLF y BOM instala igual, sin drift; y un `<src>` con `/` crea el subdirectorio del namespace (`mkdir -p`)
- [ ] T046 [P] [US2] `tests/walkthrough-prompt-block.bats`: reanotar no reconstruye nada (FR-019, SC-014) — instalar desde `--from`, provocar drift moviendo el tip, y afirmar que el archivo instalado **conserva** el bloque (`grep -c 'git-review-range'` = 1) con los *whys* adentro

### Documentación

- [ ] T047 [P] [US2] Documentar en `README.md` el circuito recomendado con un agente (FR-038): `--stdout` → completar afuera → `--build --from <archivo>|-`, con la matriz de flags y la nota explícita de que el producto no completa el borrador, no ejecuta las instrucciones y no se conecta con ningún servicio (FR-037)
- [ ] T048 [P] [US2] Espejar exactamente ese cambio en `README.es.md`
- [ ] T049 [US2] Correr `./lint-docker.sh` y `./tests/run-docker.sh` completo en verde

**Checkpoint**: US1 + US2 = la feature entera para un usuario de terminal.

---

## Phase 5: User Story 3 — El borrador a medio escribir es visible en el panel (Priority: P2)

**Goal**: que un borrador empezado sobreviva al cierre del editor y vuelva a
estar a la vista en el primer vistazo al panel, con su progreso y sus cuatro
acciones, sin abrir ningún asistente.

**Independent Test**: [quickstart.md](quickstart.md) §§ Escenarios 8 y 9.

**Depends on**: nada de US1/US2 en lo funcional, pero se planifica después
porque la CLI tiene que reportar antes de que un cliente pueda mostrar.

### 5a — Lado CLI (plan § Fase 3)

- [ ] T050 [US3] Implementar `walk_gitdir_abs_init` en `bin/git-review-lib.sh`: el gitdir **absoluto**, resuelto **una vez por proceso** en una variable del shell del llamador (mismo patrón y misma justificación que `walk_gitdir_init`, [git-review-lib.sh:500-521](../../bin/git-review-lib.sh) — un `$(...)` no puede cachear nada). Un solo proceso, y sólo se paga cuando hay al menos un borrador
- [ ] T051 [US3] Implementar `walk_draft_progress` en `bin/git-review-lib.sh` (argumentos: las rutas de los borradores; stdout: `<ruta><TAB><annotated><TAB><total>`, una línea por archivo **con contenido**). Emite la **ruta**, no `<src>`: recuperar `<src>` desde `FILENAME` obligaría a pelar el prefijo del gitdir y el `.md` dentro del `awk`, con `<src>` conteniendo `/`, y el llamador ya tiene el `<src>` de la enumeración con **un solo `awk`** sobre todos los archivos a la vez, con normalización de BOM/CR incorporada y cierre por archivo con `FNR == 1` más el `END`. **Nunca `ENDFILE`** (extensión de gawk; CI corre mawk y BSD awk). Definiciones de [data-model.md](data-model.md) § Progreso: `annotated` = entrada con posición numérica **y** *why* resuelto (al menos una línea no vacía que no sea `> key` ni `> at: `, y ninguna línea `^<!-- why`); `total` = **todos** los encabezados de entrada, numerados y `## ?.`
- [ ] T052 [US3] Cubrir en `walk_draft_progress` (o en su llamador, en `bin/git-review-lib.sh`) el caso del **archivo de cero bytes**: un archivo vacío es invisible para `awk` —no dispara `FNR == 1` ni deja `FILENAME`, verificado—, así que un borrador vacío no emitiría línea y su registro desaparecería. El contrato exige que emita `0<TAB>0` y siga apareciendo, porque hay que poder abrirlo y descartarlo ([contracts/config-porcelain-drafts.md](contracts/config-porcelain-drafts.md) § El progreso). La enumeración manda: el resultado se arma sobre `walk_draft_list` y lo que `awk` no reportó cae a `0 0`
- [ ] T053 [US3] Implementar `emit_draft_records` en `bin/git-review-lib.sh`: un registro `draft<TAB><src><TAB><path><TAB><annotated><TAB><total><TAB><source><TAB><range>` por cada borrador del namespace **activo**, enumerado con `walk_draft_list` (cero procesos), ruta absoluta desde `walk_gitdir_abs_init`, progreso desde una única invocación de `walk_draft_progress`. Orden estable, el de `walk_draft_list`; nunca reordenado por locale
- [ ] T053a [US3] **Guarda de cero borradores** en `emit_draft_records`: si `walk_draft_list` viene vacía, salir **sin invocar `walk_draft_progress` ni `walk_gitdir_abs_init`**. `awk` sin argumentos de archivo lee la entrada estándar y **se cuelga**; `config --porcelain` corre en cada refresco del panel y a mano en una terminal, así que sería un cuelgue indefinido en el caso más común de todos (FR-021a, SC-005). Presupuesto con cero borradores: **cero procesos**
- [ ] T053b [US3] Emitir `<source>` (`remote` | `local` | `offline`) y `<range>` (`full` | `delta`) leyéndolos de la línea `Generated with:` del bloque, **en el mismo `awk` que ya cuenta el progreso** (coste cero). Si el bloque no está —borrarlo a mano es legal— los dos valen `unknown`, y el cliente entonces no ofrece *Validate and start* para esa fila (FR-005a, FR-029a)
- [ ] T054 [US3] Llamar `emit_draft_records` desde el modo `porcelain` de `bin/git-review-verbs/config`, **con y sin argumento de rama**, en la posición fijada por [contracts/config-porcelain-drafts.md](contracts/config-porcelain-drafts.md): después de `candidate` / `remote-candidate` y antes de `delta` / `offer`. El registro `offer` no cambia en nada
- [ ] T055 [US3] Agregar el campo de ruta absoluta al registro `draft` de `git review status --porcelain` en [bin/git-review-verbs/status:263-264](../../bin/git-review-verbs/status): `porcelain_row draft "<path>"`, con la ruta **última** (regla de texto libre del contrato). La condición de emisión **no cambia** (`mode = walk` y `walk_is_draft` sobre `${walk_draft_src:-$src}`) y la salida legible **no cambia** ni un byte
- [ ] T056 [US3] Emitir el registro `branch-draft<TAB><branch>` en `describe_porcelain` de `bin/git-review-verbs/list`, inmediatamente después de su registro `branch`, con la **misma** condición que hoy decide el sufijo `(draft)` de la salida legible ([list:114-130](../../bin/git-review-verbs/list)): nombre desde `walk_review_draft_src`, namespace archivado **más** `walk_saved_draft_filed` para una fila `review-saved/*`, condición de **custodia** (el archivo existe), y **en todos los modos**, no sólo walk
- [ ] T057 [US3] Extraer esa condición a un helper único en `bin/git-review-verbs/list` (o en `bin/git-review-lib.sh`) que consuman `describe` y `describe_porcelain`, para que la salida legible y la porcelain no puedan divergir: hoy son dos funciones distintas y la regla está escrita en una sola
- [ ] T058 [US3] Estampar la versión con `./bump-version.sh 0.7.0` (`VERSION`, `bin/git-review`, `package.json`), dejando el `sha256` de `Formula/git-review-workflow.rb` como está — lo fija el workflow de release
- [ ] T059 [P] [US3] `tests/walkthrough-draft-progress.bats`: el conteo — una entrada con número y sin *why* no cuenta; con *why* y sin número no cuenta; con las dos cuenta; `> key` a solas no es *why*; un borrador recién generado marca `0/N` con N los archivos del rango (SC-013); `annotated` nunca llega a `total` con una marca faltante
- [ ] T060 [P] [US3] `tests/walkthrough-draft-progress.bats`: el progreso se cuenta **sobre el archivo**, sin cruzarlo con el rango (FR-022) — un borrador con un archivo de más informa su total igual, y `draft --build` lo sigue rechazando por drift. Y `annotated == total` no promete validación: un borrador completo con una ruta duplicada informa el total y falla el build
- [ ] T061 [P] [US3] `tests/walkthrough-draft-progress.bats`: coste — el número de invocaciones de `awk` **no crece** con el número de borradores (contarlas con `set -x` sobre stderr o con un stub de `awk` en el `PATH` del test), con al menos tres borradores presentes
- [ ] T062 [P] [US3] `tests/config-offers-draft.bats`: sin borradores, ningún registro `draft` y la salida es **idéntica** a la de antes del cambio; un borrador recién generado emite un registro con ruta **absoluta y existente** (`[ -f ]`) y `0<TAB>N`; dos borradores emiten dos registros en orden estable; una rama con `/` sale con la barra en `<src>` y la ruta apunta al subdirectorio; los mismos registros con y sin argumento de rama; un borrador vacío emite `0<TAB>0`. **Y el caso sin borradores afirma que el comando termina** (con el `timeout` del runner o equivalente): sin esa aserción, un `awk` sin argivos se puede volver a colar y el síntoma sería un panel colgado, no un test rojo. Más `<source>`/`<range>` en los cinco orígenes, y `unknown` con el bloque borrado a mano
- [ ] T063 [P] [US3] `tests/config-offers-draft.bats`: un borrador de una review **pausada** no aparece (cero registros tras `git review save`) y **vuelve** tras `git review continue` (FR-024, SC-012); un borrador de una review **activa** sí se emite
- [ ] T064 [P] [US3] `tests/status-porcelain.bats`: en walk sobre borrador, el registro `draft` trae un segundo campo absoluto y `[ -f ]` sobre él es verdadero; en walk sobre el sidecar del autor **no** hay registro `draft`; en `whole` / `step` con borrador en custodia tampoco; un `compare` de una rama de tracking apunta al borrador de la **rama**, no al del ref con que se la nombró; y la salida legible de `status` es **byte por byte** idéntica a la de antes
- [ ] T065 [P] [US3] `tests/list.bats`: un `branch-draft` justo después de su `branch` con review activa y borrador; presente para una review pausada que **archivó** el suyo; **ausente** para una segunda review pausada de la misma rama que no lo archivó (`walk_saved_draft_filed`); presente en `whole` y en `step`; ningún `branch-draft` sin borradores y salida idéntica a la de antes; y **paridad**: toda fila con `(draft)` en la salida legible tiene su `branch-draft` y viceversa
- [ ] T066 [P] [US3] Documentar en `README.md` los tres registros porcelain nuevos (`draft` de `config`, el campo de ruta en `draft` de `status`, `branch-draft` de `list`) en la sección de formato porcelain de cada verbo
- [ ] T067 [P] [US3] Espejar exactamente ese cambio en `README.es.md`
- [ ] T068 [US3] Correr `./lint-docker.sh` y `./tests/run-docker.sh` completo en verde (incluye `tests/version-consistency.bats`, que cubre el bump de T058, y `tests/porcelain-bytes.bats`)

**Checkpoint 5a**: la CLI reporta. Nada visible todavía para el revisor de
terminal salvo el progreso — **no se puede cortar acá sin dejar trabajo muerto**.

### 5b — Contrato multi-cliente (plan § Fase 4, primero y atómico)

- [ ] T069 [US3] **Un solo cambio, atómico**: subir `min_cli_version` a `"0.7.0"` en `contracts/client-product-surface.yaml` **y** en las tres constantes — `vscode-extension/src/cli/version.ts`, `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/Version.kt`, `visualstudio-extension/src/GitReview.Domain/Version.cs`. `scripts/check-client-product-surface.mjs` compara las tres contra el YAML ([líneas 91-108 y 685](../../scripts/check-client-product-surface.mjs)), así que moverlas por separado rompe CI
- [ ] T070 [US3] Declarar en `contracts/client-product-surface.yaml` el bloque nuevo: `{block: draft_block, when: has_drafts}` como **primer** bloque de `panel_layout.no-review` (el cuerpo de siempre sigue entero debajo), y un mapa `draft_controls:` paralelo a `inventory_controls:` con los cuatro controles de [contracts/client-draft-panel.md](contracts/client-draft-panel.md) § Los cuatro controles (`openDraft` `Open` secondary; `copyDraftPrompt` `Copy for agent` secondary; `startFromDraft` `Validate and start` primary confirms; `discardDraft` `Discard` secondary confirms). **No** se crea una situación `no-review-drafts`
- [ ] T071 [US3] Agregar el texto del portapapeles a `strings:` de `contracts/client-product-surface.yaml`, con el contenido exacto de [contracts/client-draft-panel.md](contracts/client-draft-panel.md) § 2 (`Fill in the reading order at <path>. …`)
- [ ] T072 [US3] Extender `collectCanonicalControls()` de `scripts/check-client-product-surface.mjs` para leer `draft_controls:` —la misma extensión que ya existe para `inventory_controls`, [líneas 262-284](../../scripts/check-client-product-surface.mjs)— y agregar la comprobación del string del portapapeles contra las **tres rutas concretas**: `vscode-extension/src/review/userCopy.ts`, `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/UserCopy.kt` y `visualstudio-extension/src/GitReview.Domain/UserCopy.cs`, con el mismo patrón que `multi_root_error`
- [ ] T072a [US3] Crear `vscode-extension/src/review/userCopy.ts` — **el módulo no existe**: JetBrains y Visual Studio tienen su `UserCopy`, la extensión no. Ahí vive el texto del portapapeles como constante exportada. Dejarlo suelto dentro del archivo de comandos obligaría al verificador a buscarlo con una expresión sobre código en vez de sobre una constante, que es frágil justo cuando el texto cambia — lo único que ese check existe para detectar
- [ ] T073 [US3] Verificar en `scripts/check-client-product-surface.mjs` que **el conteo fijo `27` no se toca** en ninguno de sus dos puntos ([líneas 47 y 79](../../scripts/check-client-product-surface.mjs)): los cuatro controles son del cuerpo del panel, no acciones (research § Decisión 8). Dejarlo dicho en un comentario del YAML junto a `draft_controls:`, al lado de la lista de controles que ya no son acciones
- [ ] T074 [US3] Escribir la enmienda de invocaciones: dejar un puntero en `specs/011-walkthrough-draft-revisor/contracts/cli-invocation-draft.md` hacia [contracts/cli-invocation-draft-panel.md](contracts/cli-invocation-draft-panel.md), que pasa a ser la lista vigente — no pueden convivir dos listas que se contradigan

### 5c — Extensión de VS Code (plan § Fase 4)

- [ ] T075 [P] [US3] Parsear el registro `draft` de `config --porcelain` en `vscode-extension/src/cli/configPorcelain.ts`: tipo `DraftRecord` (`src`, `path`, `annotated`, `total`) y su array en `ConfigPorcelainResult`; un registro malformado se ignora, como cualquier otro desconocido
- [ ] T076 [P] [US3] Leer el campo de ruta del registro `draft` en `vscode-extension/src/cli/porcelain.ts` ([línea ~334](../../vscode-extension/src/cli/porcelain.ts)) sin cambiar el booleano de presencia: la ruta va aparte (`draftPath?: string`)
- [ ] T077 [US3] Propagar los dos datos en `vscode-extension/src/review/state.ts`: `drafts` desde `config --porcelain` y `draftPath` desde `status --porcelain`, sin invocaciones nuevas — `config --porcelain` ya se consulta en el mismo refresco
- [ ] T078 [US3] Agregar `PanelDraft` y `drafts: PanelDraft[]` a `vscode-extension/src/views/panelModel.ts`, poblado **sólo** con `situation === "no-review"` (misma regla que `reviews`), array vacío en cualquier otra situación. `PanelModel.draft: boolean` de 011 **no cambia**; el `draftPath` se guarda aparte
- [ ] T079 [US3] Dibujar el bloque en `vscode-extension/src/views/panelHtml.ts`: heading *Reading orders you started* sólo si hay ≥1, una fila por borrador con `<src>` verbatim y `<annotated>/<total>` **tal como los reporta la CLI**, y los cuatro controles con el índice de su fila (igual que `InventoryRows`), **arriba** del cuerpo `no-review` que sigue entero debajo. Ojo: el archivo entero es un template literal — **ningún backtick**, ni en comentarios
- [ ] T080 [US3] Agregar los cuatro ids (`openDraft`, `copyDraftPrompt`, `startFromDraft`, `discardDraft`) a `PANEL_MESSAGES` en `vscode-extension/src/views/walkthroughViewProvider.ts`, con el índice de fila en el mensaje
- [ ] T081 [US3] Crear `vscode-extension/src/commands/draftActions.ts` con los cuatro comandos como lógica separable del editor: `openDraft` abre `<path>` **tal como la reportó la CLI**; `copyDraftPrompt` arma el texto de [contracts/client-draft-panel.md](contracts/client-draft-panel.md) § 2 con la ruta de **esa** fila; `startFromDraft` implementa los cuatro pasos (guardar el documento del borrador si está abierto y sucio → `walkthrough draft --build <flags> -- <src>` → en verde `config --porcelain <flags> -- <src>` para saber si hay `keys` → confirmación y `start <flags>`), con `<flags>` derivados de la fila; **y no se ofrece** si `<source>` o `<range>` valen `unknown`; `discardDraft` confirma nombrando el verbo real y corre `forget --draft -- <src>`. Todas bajo el lock de mutación, `network: false`
- [ ] T082 [US3] Implementar el argv de las tres invocaciones en `vscode-extension/src/review/reviewIntent.ts` según [contracts/cli-invocation-draft-panel.md](contracts/cli-invocation-draft-panel.md): los flags de origen y rango **salen de los campos `<source>`/`<range>` de la fila** (`local`→`--local`, `offline`→`--offline`, `delta`→`--delta`), **no** de los defaults, y van iguales en los tres pasos (`--build`, `config --porcelain`, `start`). `<src>` verbatim detrás de `--`. **Prohibidos**: `--force`, `--from`, `--stdout` y `forget --draft --all`. Usar los defaults haría que *Validate and start* fallara **siempre** por deriva sobre cualquier borrador hecho con `--delta`, `--local` u `--offline` (FR-029a)
- [ ] T083 [US3] Implementar en `vscode-extension/src/commands/draftActions.ts` el camino en rojo de `startFromDraft` (FR-030): mostrar el **stderr aplanado** de la CLI —nunca un vocabulario de validación propio— y dejar el panel y el borrador exactamente como estaban
- [ ] T084 [US3] Retirar la derivación de la ruta en `vscode-extension/src/commands/startReview.ts` ([líneas 252-290](../../vscode-extension/src/commands/startReview.ts)): `openDraft` deja de armarla con `path.join(gitdir, "review-walkthrough", …)` y usa la que reporta la CLI; borrar `gitdirFromLink` de `vscode-extension/src/review/draftFlow.ts` y su caso de `.git`-como-archivo (SC-008). Retirar también sus tests en `vscode-extension/test/unit/draftFlow.spec.ts`
- [ ] T085 [P] [US3] Agregar el estado nuevo a `vscode-extension/preview/fixtures.ts` (uno y dos borradores, con progresos distintos) para que entre en `npm run preview`; si el bloque usa alguna variable `--vscode-*` que `vscode-extension/preview/build.ts` no lista, agregarla ahí es parte del cambio
- [ ] T086 [P] [US3] Unit tests en `vscode-extension/test/unit/`: parseo del registro `draft` de `config --porcelain` (campos, registro malformado ignorado, cero registros), el campo de ruta en `status --porcelain` sin romper el booleano, `PanelDraft` poblado sólo en `no-review`, el argv exacto de los cuatro controles, y el texto del portapapeles **byte por byte** contra el canónico
- [ ] T087 [P] [US3] Tests de integración en `vscode-extension/test/integration/` (en el contenedor): con dos borradores y sin review activa el bloque se dibuja con **dos** filas y el cuerpo de siempre —inventario y *Start a review*— sigue debajo; cada control invoca lo suyo; *Validate and start* sobre un borrador incompleto muestra el motivo y no cambia el estado; *Discard* pide confirmación y elimina **sólo esa** fila; con una review activa el bloque **no** aparece
- [ ] T087a [P] [US3] Tests de integración: la mitad no trivial de **FR-029** — dos borradores válidos, uno **con** entradas `> key` y otro **sin** ellas; *Validate and start* pregunta recorrido completo vs esenciales **sólo** en el primero y arranca directo en el segundo. Hoy T086 cubre el argv y T087 el camino rojo, y este caso quedaba sólo en la prueba manual
- [ ] T087b [P] [US3] Tests de integración: **FR-029a** — un borrador generado con `--delta` se valida y arranca desde el panel **en verde** (con los defaults fallaría por deriva); una fila con `<source>`/`<range>` en `unknown` se dibuja **sin** el control *Validate and start* (SC-017)
- [ ] T088 [P] [US3] Documentar el bloque de borradores y sus cuatro acciones en `vscode-extension/README.md` (inglés, links **absolutos** — `vsce` reescribe los relativos) y agregar la entrada a `vscode-extension/CHANGELOG.md`
- [ ] T089 [US3] Correr `node scripts/check-client-product-surface.mjs`, `npm run test:unit` y `./vscode-extension/test/run-docker.sh` en verde

**Checkpoint**: US3 completa — CLI + cliente de referencia.

---

## Phase 6: User Story 4 — El asistente deja de ser una sala de espera (Priority: P2)

**Goal**: que elegir armarse el orden de lectura desde el asistente termine en el
estado del panel de US3, sin ninguna notificación esperando.

**Independent Test**: [quickstart.md](quickstart.md) § Escenario 9, paso 8.

**Depends on**: US3 (es donde el revisor aterriza).

- [ ] T090 [US4] Reducir la máquina de `vscode-extension/src/review/draftFlow.ts` a los dos pasos de [contracts/client-draft-panel.md](contracts/client-draft-panel.md) § 3 (crear → terminar), retirando los casos `wait`, `dismiss`, `build`, `reload` y `pickKeys` del bucle del asistente: lo que hacían vive ahora en `startFromDraft`. Retirar también `draftWaitMessage` y sus tests
- [ ] T091 [US4] Conectar el asistente acortado en `vscode-extension/src/commands/startReview.ts` ([~línea 399](../../vscode-extension/src/commands/startReview.ts)): al elegir `draft` se crea el borrador y el asistente **termina** — **sin abrirlo** y sin dejar ninguna notificación; `draft-resume` **salta la creación** (el archivo existe y recrearlo pisaría lo escrito). Retirar el aviso no bloqueante de 011 con sus acciones `Continue` / `Cancel`, **y la apertura**: en el instante posterior a crear todavía no hay registro `draft` que traiga la ruta, así que abrir ahí exigiría o una invocación extra o volver a derivarla — que es justo lo que T084 retira. El refresco post-mutación que ya existe trae la fila con su `<path>` y el revisor abre con *Open draft* (FR-032)
- [ ] T092 [US4] Implementar el fallo de creación en `vscode-extension/src/commands/startReview.ts` (US4 escenario 3): mostrar el stderr y **volver al paso de forma de lectura**, sin rehacer la elección de rama
- [ ] T093 [US4] Reescribir la copy de las dos ofertas en `vscode-extension/src/review/layoutOffers.ts` con los textos de [contracts/client-draft-panel.md](contracts/client-draft-panel.md) § La copy de la oferta: `draft` → *Build a reading order first* / *nobody wrote one for this PR; otherwise you read the whole diff*; `draft-resume` → *Finish the reading order you started* / *pick up the one you left half-written*. Sin la palabra *walkthrough* como término conocido (SC-011). `OFFER_ORDER` no cambia; el registro `offer` de la CLI tampoco
- [ ] T094 [P] [US4] Actualizar los unit tests de `vscode-extension/test/unit/draftFlow.spec.ts` y los de las ofertas: la máquina tiene tres estados, no hay bucle de espera, y las dos copys son las nuevas
- [ ] T095 [P] [US4] Test de integración en `vscode-extension/test/integration/`: recorrer el asistente sobre un PR sin walkthrough, comprobar que la oferta se llama *Build a reading order first*, que elegirla abre el archivo y **cierra** el asistente, y que **no queda ninguna notificación pendiente** (SC-010)

**Checkpoint**: US3 + US4 completas en el cliente de referencia.

---

## Phase 7: User Story 5 — Lo mismo desde IntelliJ y desde Visual Studio (Priority: P3)

**Goal**: paridad de producto — el mismo bloque, los mismos controles, las mismas
etiquetas y el mismo asistente acortado en los tres clientes.

**Independent Test**: [quickstart.md](quickstart.md) § Escenario 10.

**Depends on**: US3 y US4 enteras. Las dos secciones de abajo son independientes
entre sí y pueden ir en paralelo.

### 7a — Plugin de JetBrains (plan § Fase 5)

- [ ] T096 [P] [US5] Parsear el registro `draft` de `config --porcelain` en `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/ConfigPorcelain.kt` (`DraftRecord`), y el campo de ruta del registro `draft` de `status --porcelain` en `.../domain/Porcelain.kt` ([línea ~241](../../jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/Porcelain.kt)), sin tocar el booleano
- [ ] T097 [US5] Agregar `PanelDraft` y `drafts` a `.../domain/PanelModel.kt`, poblado sólo en `no-review`
- [ ] T098 [US5] Agregar los cuatro `ControlId` y el bloque `DraftRows` a `.../domain/PanelLayout.kt`, como **primer** bloque de `no-review` con la condición `has_drafts`, con los mismos rótulos y énfasis del canónico. `PanelLayoutContractTest` compara contra el mismo YAML, así que la estructura tiene que salir idéntica
- [ ] T099 [US5] Dibujar el bloque en `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/ui/PanelRenderer.kt` (Swing nativo; paridad de producto, no de píxeles) y despacharlo desde `.../ui/PanelActionDispatcher.kt` con el índice de fila
- [ ] T100 [US5] Agregar el texto del portapapeles a `.../domain/UserCopy.kt`, **byte por byte** igual al canónico y al de la extensión
- [ ] T101 [US5] Reducir `.../domain/DraftFlow.kt` a los **dos** pasos (crear → terminar), reescribir la copy de las dos ofertas en `.../domain/LayoutOffers.kt` con los textos de T093, acortar `.../ui/StartWizard.kt` para que termine **en cuanto la creación sale en verde, sin abrir el borrador** (la ruta llega por el refresco, igual que en VS Code), y **borrar** `.../ui/DraftWaitDialog.kt` con su registro
- [ ] T102 [P] [US5] Tests de dominio en `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/`: parseo del registro nuevo (`ConfigPorcelainTest.kt`, `PorcelainTest.kt`), `PanelDraft` sólo en `no-review` (`PanelModelTest.kt`), estructura del bloque contra el YAML (`PanelLayoutContractTest.kt` / `PanelLayoutEmptyStateTest.kt`), las tres transiciones de `DraftFlowTest.kt`, y el texto del portapapeles en `UserCopyTest.kt`
- [ ] T103 [P] [US5] Agregar el estado nuevo (uno y dos borradores) a `jetbrains-plugin/fixtures/com/ezevillo/gitreview/fixtures/PanelFixtures.kt` para `./gradlew runPanelPreview`
- [ ] T104 [US5] Correr `cd jetbrains-plugin && ./gradlew test` y `./gradlew platformTest` en verde. En Windows, si el daemon aborta con *Unable to establish loopback connection*, exportar `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=<dir corto>` antes de correr

### 7b — Extensión de Visual Studio (plan § Fase 6)

- [ ] T105 [P] [US5] Port mecánico del parseo en `visualstudio-extension/src/GitReview.Domain/ConfigPorcelain.cs` y `.../Porcelain.cs` ([línea ~264](../../visualstudio-extension/src/GitReview.Domain/Porcelain.cs)), con la misma forma que el de JetBrains
- [ ] T106 [US5] `PanelDraft` + `drafts` en `.../GitReview.Domain/PanelModel.cs`, y los cuatro `ControlId` + el bloque de filas en `.../GitReview.Domain/PanelLayout.cs`, idénticos en orden y etiquetas
- [ ] T107 [US5] Dibujar el bloque en `visualstudio-extension/src/GitReview.VS/ToolWindows/PanelView.cs` y despacharlo desde `.../ToolWindows/ActionDispatcher.cs`. Los botones los pinta `PanelButtons`, **no** WPF: los `Primary` / `Secondary` **no** pueden asignar `Background`/`Foreground` en la instancia (un valor local le gana al setter del `Style` y `--verify` falla con `buttons:disabled-fill`)
- [ ] T108 [US5] Agregar el texto del portapapeles a `.../GitReview.Domain/UserCopy.cs`, byte por byte igual a las otras dos puntas
- [ ] T109 [US5] Reducir `.../GitReview.Domain/DraftFlow.cs` a los **dos** pasos (crear → terminar), reescribir la copy de las ofertas en `.../GitReview.Domain/LayoutOffers.cs`, y acortar `visualstudio-extension/src/GitReview.VS/Wizards/StartWizard.cs` para que termine **sin abrir el borrador**
- [ ] T110 [US5] **Verificar que el `.vsct` no se toca**: los cuatro controles son del cuerpo del panel, no acciones ni botones de la `ToolWindowToolbar`. Ningún `IDSymbol` nuevo, ninguna entrada nueva en `MenuCommands` de `GitReviewPackage`, ningún cambio en `title_actions:` del canónico ni en `contributes.commands` de la extensión ni en el menú **Tools → git review** de JetBrains
- [ ] T111 [P] [US5] Agregar el estado nuevo a `visualstudio-extension/src/GitReview.VS/Preview/PreviewApp.cs` y los casos a `visualstudio-extension/tests/GitReview.Domain.Tests/PanelLayoutContractTests.cs` y `PorcelainTests.cs`
- [ ] T112 [US5] Correr `cd visualstudio-extension && dotnet build GitReview.sln`, `dotnet test tests/GitReview.Domain.Tests`, `dotnet run --project src/GitReview.VS -- --verify` y `./build-vsix.ps1` (el gate de net472 — lo que sólo rompe ahí no rompe `dotnet build`)

**Checkpoint**: los tres clientes ofrecen las mismas decisiones.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [ ] T113 [P] Estampar las versiones de los tres clientes, **decididas en [plan.md](plan.md) § Fase 7**: `./vscode-extension/bump-version.sh 0.2.0` (de `0.1.3`), `./jetbrains-plugin/bump-version.sh 0.2.0` (de `0.1.3`) y `./visualstudio-extension/bump-version.sh 0.2.0` (de `0.1.0`). Minor y no patch: el panel gana un bloque y cuatro controles, y el asistente cambia de forma. Versionan **aparte** de la CLI y entre sí; que los tres lleguen a `0.2.0` es consecuencia de recibir la misma feature, no una regla. `tests/version-consistency.bats` cubre el drift de los cuatro
- [ ] T114 Escribir a mano el heading `## [0.2.0]` y las notas en `jetbrains-plugin/CHANGELOG.md`: **es lo que se publica** — `build.gradle.kts` busca la sección de `pluginVersion` y la renderiza al `<change-notes>` del descriptor (pestaña *What's New* del Marketplace y diálogo de actualización del IDE), y `release-jetbrains.yml` extrae la misma sección para el cuerpo del GitHub Release. **Si el heading no está no falla nada**: hay un fallback deliberado que cae a `[Unreleased]` y, si tampoco, a un enlace al CHANGELOG. O sea que el build sale verde, CI sale verde, y el error se ve recién en la tienda — por eso el número está decidido en el plan y esta tarea sólo lo transcribe
- [ ] T115 [P] Actualizar `visualstudio-extension/CHANGELOG.md` con el heading `## [0.2.0]` y, si existe, el `marketplace/overview.md`, con la superficie nueva del panel (el `listing:` del canónico no cambia: ni el tagline ni los keywords)
- [ ] T116 [P] Actualizar `CLAUDE.md` § Modelo de estado: el bloque de instrucciones como pieza reconocida del formato del walkthrough (**regenerada** al construir —con el rango que esa corrida validó, nunca arrastrada—, filtrada al leer, neutra para la validación, y portadora de los flags con los que se generó), `--stdout` / `--build --from`, y los tres registros porcelain nuevos, en el párrafo del borrador del revisor
- [ ] T117 Repaso final de los **dos** README: que `README.md` y `README.es.md` estén espejados byte a byte en la tabla de verbos, los flags nuevos, el bloque de instrucciones, el circuito con un agente y los tres formatos porcelain
- [ ] T118 Verificar `./tests/run-docker.sh test-names.bats` en verde: ningún `@test` nuevo con acentos, `ñ` o em dashes (bats en Windows trastabilla con los bytes UTF-8 del nombre de la función)
- [ ] T119 Correr las siete suites en verde: `./lint-docker.sh`, `./tests/run-docker.sh`, `node scripts/check-client-product-surface.mjs`, `cd vscode-extension && npm run test:unit`, `./vscode-extension/test/run-docker.sh`, `cd jetbrains-plugin && ./gradlew test`, y `cd visualstudio-extension && dotnet test tests/GitReview.Domain.Tests` + `dotnet run --project src/GitReview.VS -- --verify` + `./build-vsix.ps1`
- [ ] T120 Recorrer [quickstart.md](quickstart.md) a mano de punta a punta sobre `./tests/sandbox.sh`: los escenarios 1 a 8 en la terminal, el 9 con F5 desde `vscode-extension/` (incluido cerrar y reabrir la ventana, SC-006), y el 10 con `./gradlew runIde` y `./build-vsix.ps1 -Install -Experimental` + `devenv /rootsuffix Exp`. Comprobar en particular que *Copy for agent* deja **el mismo texto** en los tres

---

## Dependencies

```text
Setup (T001–T002)
   └─► Foundational (T003–T005)      ⚠️ bloquea US1 y US2
          ├─► US1 · el bloque (T006–T024)        🎯 MVP, entregable sola
          │      └─► US2 · stdout / --from (T025–T049)   entregable sola
          │
          └─► US3 · CLI (T050–T068)
                 └─► T069 (min_cli_version, atómico)
                        └─► US3 · canónico (T070–T074)
                               └─► US3 · VS Code (T075–T089)
                                      └─► US4 · asistente (T090–T095)
                                             ├─► US5 · JetBrains (T096–T104)
                                             └─► US5 · Visual Studio (T105–T112)
                                                    └─► Polish (T113–T120)
```

- **US1 y US2 son el camino crítico del valor** y no dependen de US3–US5: las dos
  se cortan solas para un usuario de terminal.
- **US3 lado CLI (T050–T068) no se puede cortar solo**: no entrega nada visible
  salvo el progreso, y existe para que las fases de cliente tengan qué leer. Se
  planifica pegado a 5b/5c.
- **T069 es una única tarea atómica de cuatro archivos**. El verificador compara
  las tres constantes contra el YAML: moverlas por separado rompe CI en el commit
  intermedio. Que JetBrains y Visual Studio exijan 0.7.0 antes de ofrecer nada es
  correcto — 0.7.0 ya existe desde T058.
- **US1 depende de T003** (`walk_prompt_block`) sólo para T012, la reescritura.
- **7a y 7b son independientes entre sí**; conviene JetBrains primero sólo para
  estabilizar el port antes de repetirlo.

## Parallel Execution Examples

**Foundational**: T005 en paralelo con T003–T004 (archivos distintos).

**US1 — tests**: T013 a T020 son ocho casos del mismo archivo bats
(`tests/walkthrough-prompt-block.bats`); se escriben en paralelo pero **se
integran como un solo cambio** — comparten archivo, así que no se editan a la vez.
T021 y T022 (los dos README) también van juntas por la regla del proyecto.

**US2 — tests**: T038 a T045 sobre `tests/walkthrough-draft-io.bats`, misma regla
que arriba. T046 toca otro archivo y sí va en paralelo real.

**US3 — CLI**: T059–T065 tocan **cinco** archivos bats distintos
(`walkthrough-draft-progress`, `config-offers-draft`, `status-porcelain`, `list`)
y van en paralelo real una vez que existen los registros.

**US3 — VS Code**: T075 y T076 son dos parsers en dos archivos; T085, T086, T087
y T088 (preview, unit, integración, README/CHANGELOG) van en paralelo con el
trabajo de UI.

**US5**: 7a completa en paralelo con 7b completa, si hay dos personas.

## Implementation Strategy

**MVP = Phase 1 + Phase 2 + Phase 3 (US1).** Es la corrección de un error
silencioso —hoy el flujo «funciona» y produce prosa equivocada, que es peor que
fallar— y se entrega sin tocar un solo cliente.

**Segundo incremento defendible = + Phase 4 (US2)**: con eso el circuito entero
con un agente en sandbox anda desde la terminal, que es el usuario de las dos
historias P1.

**Orden sugerido**: US1 → validar a mano con el sandbox → US2 → US3 (CLI) → T069
→ US3 (VS Code) → US4 → US5 JetBrains → US5 Visual Studio → cierre.

**Punto de no retorno**: T053–T056 fijan tres contratos porcelain. Una vez
publicados, cambiar la forma de esos registros rompe clientes instalados; por eso
son aditivos por diseño y se cierran antes de escribir el código de los clientes.

**Riesgo asumido y documentado** (research § Hallazgo 0): el tree OID que
`resolve_lower_bound` devuelve **no está referenciado**, así que un `git gc`
agresivo lo puede podar (`gc.pruneExpire` lo protege dos semanas por defecto). Un
borrador viejo da entonces un error de git ruidoso al intentar ver el cambio, que
es el comportamiento que el edge case de la spec pide. No se materializa un commit
ni se crea una ref para evitarlo.
