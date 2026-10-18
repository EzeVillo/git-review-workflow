# Tasks: Comentarios portables de una review

**Input**: Design documents from `/specs/016-comentarios-review/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/comments-format.md](contracts/comments-format.md),
[contracts/cli-porcelain.md](contracts/cli-porcelain.md),
[contracts/lifecycle.md](contracts/lifecycle.md),
[contracts/client-surface.md](contracts/client-surface.md) y [quickstart.md](quickstart.md).

**Tests**: obligatorios por el pedido del usuario y por los contratos. Cada grupo
de pruebas se escribe y se ejecuta antes de implementar su comportamiento; debe
fallar por una discrepancia observable con el contrato, no por un fixture roto,
una dependencia ausente o un error de compilación. Después de implementar se
ejecuta el mismo grupo sin relajar sus asserts. Una tarea de tests comprende
casos separados por comportamiento; no un único test gigante cuyo primer fallo
oculte el resto de la matriz.

**Organization**: una fase por historia. Dentro de P1, US4 precede a US3 porque
la entrega compartida necesita custodia y resultados durables. US6 sigue siendo
P1 y precede a US5 (P2). Las historias se validan por CLI antes de incorporar sus
adaptadores en US5. US5 completa la aceptación de las cinco superficies; su
prioridad no permite omitir ningún cliente de la primera entrega.

Esta lista planifica implementación futura. Generarla no implementa el producto,
no ejecuta sus aceptaciones, no cambia de rama ni autoriza publicar releases.
No se aplican skills de superpowers. La constitución sigue siendo una plantilla
sin ratificar: rigen `AGENTS.md` y las decisiones cerradas D01..D22.

## Format: `[ID] [P?] [Story] Description`

- Cada tarea tiene checkbox, ID secuencial y rutas concretas.
- `[P]` indica archivos distintos dentro de una tanda cuyos prerrequisitos ya
  terminaron. No autoriza a ejecutar implementación antes de sus tests ni a
  editar simultáneamente `bin/git-review-lib.sh`, el canónico o un mismo fixture.
- `[US1]`..`[US6]` conservan la numeración de la especificación.
- Setup, Foundational y Polish no llevan etiqueta de historia.
- Todas las tareas empiezan pendientes. La evidencia de cada ejecución futura
  se registra en `specs/016-comentarios-review/quickstart.md`.

## Path Conventions

Las rutas de las tareas son relativas a la raíz del repositorio. Los archivos
nombrados como nuevos deben crearse; los demás se amplían en su ubicación actual.
CLI: `bin/`; tests CLI: `tests/`; canónico: `contracts/`; gates: `scripts/`.
Los cuatro clientes conservan sus dominios puros y sus límites dominio/host/UI.
No se agrega runtime de Markdown, dependencia gráfica ni servicio de proveedor.

### Reglas de verificación contra falsos positivos

1. En bats, usar `run --separate-stderr` y afirmar el exit esperado **exacto**:
   `0`, `1`, `2`, `4` o `5` según el contrato. Verificar también stdout y stderr;
   un error esperado no pasa porque cualquier comando haya fallado. Afirmar el
   status de cada operación de una secuencia antes de ejecutar la siguiente.
2. Para prosa, comparar archivos con `cmp` contra fixtures esperados independientes.
   No usar sustitución de comandos para comparar bytes: pierde LF finales. No
   generar el esperado mediante el parser, renumerador o codec bajo prueba.
   Contar entradas no demuestra que se conservaron cuerpos, orden o referencias.
3. Capturar fuera del working tree HEAD/rama, refs ordenadas, índice mediante
   `git ls-files --stage -z`, diff staged/unstaged binarios, archivos untracked
   relevantes, config y presencia/bytes de documentos/manifests/punteros. Comparar
   los campos que cada operación debe conservar y afirmar por separado los que
   debe cambiar. `git status` limpio no demuestra ausencia de cambios en gitdir.
4. En consultas de sólo lectura, comparar también inventario de almacenamiento
   de comments y objetos antes/después. La captura del oráculo no debe escribir
   objetos, refrescar el índice ni producir sus propios cambios de metadata.
5. En errores y cancelación, afirmar bytes/presencia del original, del otro
   documento y del destino, ausencia de efectos colaterales y recuperación del
   candidato cuando corresponda. Distinguir archivo ausente, vacío y presente;
   ni cero inventado ni documento vacío creado implícitamente.
6. Sincronizar concurrencia con barreras explícitas y timeout acotado que falle
   el test. No usar sleeps como condición de carrera ni convertir timeout en
   éxito. Las fallas de I/O se inyectan por operación y fase; comprobar que la
   inyección ocurrió. `chmod` no basta si los tests corren como root.
7. Probar operaciones CLI reales en repositorios temporales para efectos Git;
   usar dobles en clientes para respuestas negativas de APIs y comprobar llamadas,
   orden y ausencia de llamadas. Un mock que siempre devuelve éxito no prueba
   persistencia, cancelación, dispatch real ni guardado selectivo.
8. Aislar configuración Git, locale cuando sea relevante y red. Los tests offline
   fallan si se intenta fetch/push/proveedor. Nombres `@test` en ASCII puro,
   asserts activos y pines bats 1.13.0 intactos. No esconder casos requeridos con
   skips amplios ni aceptar una suite que descubrió cero tests.
9. Antes de cerrar cada grupo crítico, introducir en una copia desechable una
   rotura representativa y comprobar que falla el test específico; restaurar y
   comprobar verde. Registrar qué aserción falló. No añadir un framework nuevo
   de mutation testing ni modificar el checkout del usuario para esta prueba.
10. Matrices obligatorias: whole/walk/step × Local/Shared para captura,
    renumeración y custodia; ambos documentos presentes y cada uno por separado;
    baseline ausente/vacío/con contenido en descartes; compare con cero/uno/dos
    guardados; cuatro clientes en contratos de registros, guardado y stale. Para
    ejes ortogonales adicionales usar casos dirigidos y justificar cualquier
    exclusión en la evidencia, sin prometer un producto cartesiano infinito.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: preparar oráculos reproducibles sin agregar comportamiento de producto.

- [X] T001 Crear fixtures fuente y esperados independientes en `tests/fixtures/comments/`, con inventario en `tests/fixtures/comments/README.md`: Markdown libre, 100 entradas, BOM, LF/CRLF/EOL mixtos, sin LF final, fences/HTML, paths y referencias; fijar en `.gitattributes` la conservación de bytes de esos fixtures sin cambiar la política de otros archivos.
- [X] T002 Crear `tests/helpers/comments.bash` con repos temporales whole/walk/step/compare, snapshots selectivos de Git/prosa, comparación de presencia/bytes y barreras/fallas por fase; aislar configuración y red y mantener los artefactos del oráculo fuera del working tree.
- [X] T003 Añadir `tests/comments-harness.bats` que pruebe los helpers de `tests/helpers/comments.bash`: detectar un byte cambiado con igual longitud/recuento, absent→empty, una ref/config/entrada de índice alterada y una barrera no alcanzada; comprobar que el propio snapshot no cambia el estado observado.
- [X] T004 Documentar en `specs/016-comentarios-review/quickstart.md` los comandos de ejecución y la matriz de evidencia por historia/cliente, separando contenedores, CI real de tres SO y smoke del host; registrar descubrimiento de tests y estado rojo/verde sin marcar aceptaciones aún no ejecutadas.

**Checkpoint**: fixtures y helpers detectan sus controles negativos y no contaminan
el repositorio bajo prueba. No se crea una toolchain nueva.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: identidad, custodia, guardas y escritura segura comunes a las historias.

### Tests

- [X] T005 [P] Probar en `tests/comments-status.bats` el TSV completo de status: fresh/ambiguous/resolved, sesión antigua sin claves, guard provisional, dos filas al confirmar contexto, count cero sólo si es legible, diagnóstico separado, ausencia de cuerpos y consultas sin crear directorios/config/refs/objetos ni resolver cada histórico.
- [X] T006 [P] Probar en `tests/comments-context.bats` marcador propio/heredado/manual, mismo PR con nuevo tip, rama reutilizada tras integración, delta/`--from` distintos del rango completo, base incompleta, force-push ambiguo, token portable frente a registro incompatible y pareja exacta de compare; comprobar candidatos y no mezclar documentos.
- [X] T007 [P] Probar en `tests/comments-safety.bats` validación de tokens/contextos antes de formar rutas, dueño de otro gitdir, symlinks y tipos inseguros, paths que intentan escapar, locks existentes/owner desconocido y liberación por error/señal; afirmar integridad de centinelas fuera del almacenamiento autorizado.
- [X] T008 [P] Probar en `tests/comments-concurrency.bats` guard obsoleto por rama, custodio, step con mismo tip, cursor, extremos o bytes/presencia; incluir primer compositor fresh/ambiguo y ausencia que dejó de serlo; dos escritores cooperantes y edición externa detectable antes de rename deben preservar originales y candidato recuperable.
- [X] T009 [P] Probar en `tests/comments-atomic.bats` fallos al crear/copiar cada documento, escribir manifest, validar y publicar `current`, con matrices absent/empty/present; un reintento debe recuperar una generación íntegra, nunca un par mezclado, y cada falla inyectada debe acreditarse.

### Implementation

Los tests T007..T009 ejercitan primero las puertas compartidas mediante un
driver de `tests/helpers/comments.bash`, sin exigir handlers de historias aún
no implementadas. US1 los repite a través del verbo público. T005 cubre lectura
de documentos conocidos y sus contornos, no el writer de renumeración de US2.

- [X] T010 Crear el verbo privado `bin/git-review-verbs/comments` con modo ejecutable 100755, `set -eu`, ayuda, dispatch de los ocho subcomandos y diagnóstico de uso, y agregarlo a la ayuda de `bin/git-review`; sourcear helpers sin ejecutar escrituras ni agregar otro ejecutable al PATH.
- [X] T011 Implementar `comments_context_resolve` y validación de tokens en `bin/git-review-lib.sh`: Bfull separado de lower/delta, marcador/linaje/origen/destino, candidatos, compare e inicialización explícita; conservar Markdown manual e identificar archivo heredado sin cargarlo como semilla.
- [X] T012 Implementar manifests de contexto/sesión, baselines y owner por `--absolute-git-dir` en `bin/git-review-lib.sh`; distinguir sesión provisional de contexto confirmado, leer claves con `|| true` y no apropiarse del gitdir de otro worktree.
- [X] T013 Implementar en `bin/git-review-lib.sh` lock por contexto con `mkdir`/trap, guardas revalidadas bajo lock, temporal hermano y recuperación optimista; publicar generaciones completas por cambio de puntero y rechazar tipos inseguros sin truncar documentos.
- [X] T014 Implementar `comments status [--porcelain] [--context]` en `bin/git-review-verbs/comments` y sus helpers en `bin/git-review-lib.sh`: lector compartido de contornos para count/diagnóstico, registros del contrato, enumeración de resultados sin elegir por recencia, revisiones de bytes/presencia y guard provisional sin mutaciones; US2 completa su transformación que preserva bytes.
- [X] T015 Verificar con `tests/comments-status.bats`, `tests/status-porcelain.bats`, `tests/config-porcelain.bats`, `tests/list.bats` y `tests/dispatcher-only.bats` que el pipeline antiguo conserva registros/códigos y que sourcear `bin/git-review-lib.sh` no tiene efectos; dejar la evidencia en `specs/016-comentarios-review/quickstart.md`.

**Checkpoint**: bases seguras y observables. Toda implementación que escriba prosa
usa estas puertas; no crea su propio protocolo de locks o normalización.

## Phase 3: User Story 1 - Anotar mientras se entiende el PR (Priority: P1) — MVP técnico

**Goal**: crear sólo el documento elegido y agregar una entrada por captura,
sin tocar código ni mezclar Local/Shared.

**Independent Test**: por CLI, capturar Local→Shared→Local, dos entradas con
igual ubicación y una general; editar/borrar manualmente una, refrescar y
comparar cuerpos/recuentos y snapshots de código/índice/refs.

### Tests for User Story 1

- [X] T016 [P] [US1] Probar en `tests/comments-add.bats` captura Local→Shared→Local en whole/walk/step, mismo path/línea repetidos, entrada general, edición/borrado manual y contenido distinto por destino; afirmar entrada exacta, orden, count y bytes del documento no elegido.
- [X] T017 [P] [US1] Probar en `tests/comments-input.bats` argumento/stdin/editor Git, UTF-8 y texto multilínea, comillas/backticks/`$()` como datos, `--text` incompatible con `--stdin`, editor con espacios/argumentos, cancelación vacía/whitespace y editor fallido; comprobar que no se ejecuta texto ni se crea documento al cancelar.
- [X] T018 [P] [US1] Probar en `tests/comments-location.bats` ubicación general/archivo/caret/rango, base/head de commit o tree SHA-1/SHA-256, rename/adición/borrado, pares incompletos, líneas cero/negativas/invertidas/fuera del blob y lado sin path; validar coordenadas y referencias reales del modo, nunca HEAD por comodidad.
- [X] T019 [P] [US1] Probar en `tests/comments-add-boundaries.bats` documento terminado en fence/HTML abierto, captura con encabezado reservado sin cercar, fences internas, citas y cuerpos incompletos manuales; rechazo sin mutar frente a corrección que agrega exactamente un bloque, sin renumerar los anteriores.
- [X] T020 [P] [US1] Probar el parser común de los ocho subcomandos en `tests/comments-cli.bats`: ayuda, opciones desconocidas/repetidas incompatibles, valores faltantes, argumentos sobrantes, terminador `--` y valores con guion; para init/add/status probar además destino obligatorio, contexto múltiple sin selección y ámbitos, afirmando uso=1, sesión incompatible=2 y stale=4 sin efectos; cada historia posterior agrega los recorridos válidos y ámbitos propios de su handler.
- [X] T021 [P] [US1] Probar en `tests/comments-create.bats` init idempotente sin truncar, ausencia/vacío por destino, cancelación del primero/segundo documento, elección explícita cada vez, `--new-context`/`--use-context` antes de editar y rechazo de reasignación con preparación nueva sin conservar; mantener accesible el contexto anterior.
- [X] T022 [P] [US1] Probar en `tests/comments-offline.bats` creación/captura/apertura por ruta en sandbox sin red, working tree sucio/untracked y sesión en finish-conflict: no guardar código, no inventar refs de conflicto ni crear objetos de retención, y preservar índice/refs salvo metadata de custodia declarada.

### Implementation for User Story 1

- [X] T023 [US1] Implementar parseo estricto de argv, ámbitos y códigos de salida de los ocho subcomandos en `bin/git-review-verbs/comments`, incluido `--`, destino obligatorio y opciones de contexto mutuamente excluyentes; las operaciones de historias posteriores quedan cubiertas al completarlas, sin éxitos no-op.
- [X] T024 [US1] Implementar `init` y materialización perezosa de contexto/documento en `bin/git-review-verbs/comments` y `bin/git-review-lib.sh`; crear sólo tras intención explícita o texto confirmado y no reutilizar un destino anterior.
- [X] T025 [US1] Implementar composición `--text`/`--stdin`/`git var GIT_EDITOR` en `bin/git-review-verbs/comments`, con temporal, UTF-8, cancelación y propagación de error; el texto permanece como dato y no se incluye en comandos ni logs internos.
- [X] T026 [US1] Implementar captura de extremos/ubicación en `bin/git-review-lib.sh`, usando modo/cursor reales, OID resueltos y `unversioned` si el contenido no coincide con blob; reutilizar `changed_paths`/`walk_normalize` para comparaciones sin introducir otra normalización.
- [X] T027 [US1] Reutilizar el lector de contornos de T014 para implementar append de un bloque en `bin/git-review-lib.sh`: cantidad física+1, metadata opcional, validación de fences/HTML y del texto recibido; usar la escritura protegida y conservar todo el original fuera de la entrada añadida.
- [X] T028 [US1] Implementar codec de paths y validación de metadata en `bin/git-review-lib.sh`: escapes exactos y una sola decodificación, claves futuras conservadas, diagnósticos sin fallback histórico y rutas literales sin usarlas como nombres internos ni shell.
- [X] T029 [US1] Ejecutar los tests de US1 y `tests/comments-concurrency.bats`/`tests/comments-safety.bats` en contenedor, acreditar que quitar la validación de destino o escribir en el otro documento hace fallar el test específico y registrar aceptación CLI en `specs/016-comentarios-review/quickstart.md`.

**Checkpoint**: US1 usable por CLI. La captura de selección/compositor de los
clientes se cierra en US5; no se declara completa esa aceptación todavía.

## Phase 4: User Story 2 - Repasar y renumerar el documento (Priority: P1)

**Goal**: cambiar sólo los dígitos de encabezados reales, por orden físico.

**Independent Test**: mover bloques con números 1/4/9 y repetidos, renumerar a
1/2/3, comparar bytes contra esperado y repetir sin ningún cambio adicional.

### Tests for User Story 2

- [X] T030 [P] [US2] Probar en `tests/comments-renumber.bats` huecos, repetidos, fuera de orden, cero, ordinales largos, etiqueta vacía, varios bloques del mismo path y eliminación/movimiento manual; afirmar números físicos, cuerpos y metadata completos frente a esperados independientes.
- [X] T031 [P] [US2] Probar en `tests/comments-fences.bats` backticks/tildes con longitud y carácter de cierre correctos/incorrectos, indentación 0..3 frente a 4 espacios, info-string con backticks, cierre con texto, fences anidadas aparentes, citas y HTML; una fence sin cerrar conserva el resto como código y HTML ambiguo rechaza la escritura.
- [X] T032 [P] [US2] Probar en `tests/comments-bytes.bats` BOM inicial, LF/CRLF/EOL mixtos y EOF sin LF, preámbulo/listas/links/citas/encabezados internos, documento vacío/sólo prosa y entrada sin cuerpo; comparar cada archivo con `cmp` y comprobar idempotencia de segunda ejecución.
- [X] T033 [P] [US2] Probar en `tests/comments-renumber-errors.bats` ausente sin creación, fallo de lectura/escritura/rename y cambio externo detectable; metadata duplicada/incompleta o refs ausentes con límites claros permite renumerar conservando metadata y diagnosticando la referencia, claves futuras se conservan y límites ambiguos fallan sin reescritura parcial.
- [X] T034 [P] [US2] Probar en `tests/comments-scale.bats` 100 entradas de cuerpos distintos, huecos, borrados y bloques movidos en ambos documentos; afirmar secuencia y documento esperado completo, no sólo count, e instrumentar que contar/renumerar no invoca Git por entrada ni intenta red.
- [X] T035 [P] [US2] Probar en `tests/comments-entries.bats` registros por ordinal físico, número visible repetido, heading-line con BOM/CRLF, metadata opcional/diagnósticos y separación del cuerpo; variar un número, ruta o campo de un registro esperado debe fallar, y tags/campos futuros quedan tolerados por consumidores en US5.

### Implementation for User Story 2

- [X] T036 [US2] Completar en `bin/git-review-lib.sh` la máquina de estados awk POSIX compartida por count/entries/renumber, con vistas original/normalizada, fences y HTML; no usar `gensub`, `RT` ni extensiones GNU de `match`.
- [X] T037 [US2] Implementar `renumber` en `bin/git-review-verbs/comments` y `bin/git-review-lib.sh`: sustituir exclusivamente dígitos, preservar BOM/EOL/EOF/cuerpos y escribir sólo tras validar el resultado completo y las guardas.
- [X] T038 [US2] Implementar `entries --porcelain` en `bin/git-review-verbs/comments` y `bin/git-review-lib.sh`, con ordinal/heading-line/revisión del documento y diagnósticos por entrada; nunca resolver identidad por número visible ni exigir historia para conservar prosa.
- [X] T039 [US2] Integrar count/diagnósticos del parser en `comments status` de `bin/git-review-lib.sh`, diferenciando error de contorno, referencia inválida y cero entradas, sin filtrar comentarios por el diff actual ni resolver objetos por entrada durante refresh.
- [ ] T040 [US2] Ejecutar `tests/comments-{renumber,fences,bytes,renumber-errors,scale,entries}.bats` con awk GNU/BSD/BusyBox y shell compatible según entornos disponibles, más CI macOS/Git Bash; registrar comandos/versiones y sensibilidad a pérdida de LF/BOM, orden por número o fence mal cerrada en `specs/016-comentarios-review/quickstart.md`.

**Checkpoint**: Local y Shared producen la misma transformación byte a byte;
una entrada inválida históricamente no se borra ni se interpreta como código actual.

## Phase 5: User Story 4 - Conservar las observaciones durante la review (Priority: P1)

**Goal**: custodiar ambos documentos al navegar, pausar, retomar, conservar y
descartar, sin bancarlos como correcciones de código.

**Independent Test**: whole/walk/step con y sin código editado: capturar en los
dos destinos, navegar, save/continue, terminar y limpiar; en recorridos distintos
abortar o descartar guardada y comparar contra baseline. En compare, guardar,
seguir editando y abortar conserva exactamente el checkpoint.

### Tests for User Story 4

- [X] T041 [P] [US4] Probar en `tests/comments-navigation.bats` next/prev en walk/step y permanencia en whole, con Local/Shared/ambos, archivo que desaparece en otro paso y refs B/H distintas; comprobar documentos completos, nuevas capturas del paso correcto y que la preparación no entra en árboles de `refs/review-edits/`, sin confundirla con `.review/comments.md` ya versionado por el PR.
- [X] T042 [P] [US4] Probar en `tests/comments-save-continue.bats` save/continue de los tres modos con baseline ausente/vacío/presente, ambos documentos y referencias, propietario transferido sin mover dos archivos parcialmente, ningún `.review/comments.md` publicado y snapshot de código conservado según el flujo existente.
- [X] T043 [P] [US4] Probar en `tests/comments-custody.bats` colisión durante pausa, documentos creados mientras está guardada, metadata incompleta/borrada y worktrees enlazados con config compartida; save/continue/forget/clean deben fallar antes de mover refs o tocar prosa ajena.
- [X] T044 [P] [US4] Probar en `tests/comments-abort.bats` abort/clean incompleto/forget saved con baseline ausente/vacío/con contenido, preparación nueva y resultado anterior; restaurar el límite correcto y respetar siempre el compartido versionado previo, sin confundir save de review con un checkpoint durable nuevo.
- [X] T045 [P] [US4] Probar en `tests/comments-clean.bats` clean completado y variantes `--keep-fixes`/`--fixes-only`, forget delta/draft y limpieza ajena; conservar resultados consultables y sus bytes/contextos, sin borrar comments por coincidencia de nombre de rama.
- [X] T046 [P] [US4] Probar en `tests/comments-compare-save.bats` compare sin rama escribible: guardar cero/uno/dos veces con un documento/ambos, seguir capturando y abortar; recuperar exactamente el último par guardado, no crear review-saved ni archivo versionado y conservar árbol/índice/refs de código.
- [X] T047 [P] [US4] Probar en `tests/comments-compare-errors.bats` save fuera de compare=2, guardas del par obsoletas=4, falla en cada fase de generación y fallo antes de avanzar checkpoint; el resultado/checkpoint anteriores siguen íntegros y el reintento no mezcla mitades ni cierra compare.
- [X] T048 [P] [US4] Probar en `tests/comments-legacy.bats` sesiones previas sin claves comments y claves comunes presentes en whole/walk/step, pérdidas manuales de metadata y prosa mal formada; consultas no inicializan custodia y next/prev/preview/status de código no se bloquean por parseo de comments.
- [X] T049 [P] [US4] Probar en `tests/comments-results.bats` lectura/edición/renumeración tras cerrar, un contexto y múltiples contextos, ambos destinos y tokens viejos; no seleccionar por recencia, no habilitar captura nueva fuera de sesión y mantener referencias/owner.
- [X] T050 [P] [US4] Probar en `tests/comments-source-reconcile.bats` las cuatro relaciones S/O/R del contrato, incluido absent/empty, fuente manual/mal formada y documento heredado sólo como baseline de entrega; conservar ambas versiones en conflicto, sin merge automático ni participación de Local.

### Implementation for User Story 4

- [X] T051 [US4] Integrar la sesión/baselines/checkpoint de comments en `bin/git-review-verbs/start`, `bin/git-review-verbs/compare` y `bin/git-review-lib.sh`, con carga perezosa, rango completo e independencia del banco de código y de la existencia de documentos.
- [X] T052 [US4] Integrar continuidad y conciliación S/O/R en `bin/git-review-lib.sh`, preservando fuente/preparado/baseline y documentos mal formados como bytes; el conflicto de Shared no cambia Local ni impide los verbos de código.
- [X] T053 [US4] Integrar lectura de cursor de captura y conservación de documentos en `bin/git-review-verbs/next`, `bin/git-review-verbs/prev` y `bin/git-review-lib.sh`; el movimiento no filtra entradas ni las incorpora a refs de ediciones.
- [X] T054 [US4] Incorporar preflight y transferencia de custodio en `bin/git-review-verbs/save` y `bin/git-review-verbs/continue`, reteniendo directorio/baseline y rechazando colisiones antes de mover la rama o sustituir archivos.
- [X] T055 [US4] Incorporar descarte protegido por checkpoint en `bin/git-review-verbs/abort` y `bin/git-review-verbs/forget`, limitado a la preparación propia; no eliminar resultados anteriores/guardados expresamente ni el documento versionado del PR.
- [X] T056 [US4] Incorporar la política completa/incompleta de conservación en `bin/git-review-verbs/clean`, sin ampliar el alcance de `--fixes-only` ni apropiarse de comments al limpiar delta/draft.
- [X] T057 [US4] Implementar `comments save` en `bin/git-review-verbs/comments` y `bin/git-review-lib.sh`: sólo compare, validar revisiones de ambos documentos, publicar generación íntegra, avanzar checkpoint tras publicar y continuar comparando sin guardar código.
- [X] T058 [US4] Integrar publicación de resultados locales en los caminos de cierre de `bin/git-review-verbs/finish` y helpers de `bin/git-review-lib.sh`, conservando preparación para undo; la entrega al repositorio se completa en US3 y no se anticipa al replay.
- [X] T059 [US4] Incorporar las claves `reviewcommentscontext`, `reviewcommentssession` y `reviewcommentsowner` como metadata común permitida en `bin/git-review-verbs/finish` y los cargadores de `bin/git-review-lib.sh`, manteniendo los guards step/walk contra corrupción real.
- [X] T060 [US4] Implementar selección/acceso protegido a generaciones existentes fuera de sesión en `bin/git-review-verbs/comments` y `bin/git-review-lib.sh`, distinguiendo resultado de compare, sesión guardada y review completada; no crear captura fuera de ámbito.
- [X] T061 [US4] Ejecutar las familias `tests/comments-*.bats` de custodia junto con `tests/save.bats`, `tests/compare.bats`, `tests/step.bats`, `tests/walk.bats`, `tests/clean.bats` y `tests/finish-abort.bats`; acreditar que checkpoint incorrecto o prosa bancada en step falla y registrar resultados en `specs/016-comentarios-review/quickstart.md`.

**Checkpoint**: los dos documentos sobreviven a los recorridos acordados y el
descarte respeta el baseline. Compare conserva prosa localmente sin convertirse
en una review de código guardada ni permitir entrega versionada.

## Phase 6: User Story 3 - Compartir una revisión como archivo (Priority: P1)

**Goal**: entregar sólo Shared modificado después del código, sin sobrescribir
prosa concurrente y con recuperación idempotente del cierre parcial.

**Independent Test**: continuar Shared preexistente, terminar sin correcciones,
abrir `.review/comments.md` como Markdown y comparar su contenido; Local no sale
del gitdir. En otro recorrido, provocar conflicto de destino, extraer código,
inspeccionar/resolver/reintentar sólo prosa y comprobar que no se repite replay.

### Tests for User Story 3

- [X] T062 [P] [US3] Probar en `tests/comments-finish-delivery.bats` whole/walk/step con/sin correcciones, Shared nuevo/preexistente/manual/vacío/sólo preámbulo, Local distinto y múltiples pasadas; afirmar archivo final exacto, rama de salida, índice y número/árbol de commits esperados, sin commit/push adicional por comments.
- [X] T063 [P] [US3] Probar en `tests/comments-finish-unchanged.bats` Shared sin editar, sólo Local modificado y documento heredado no elegido como semilla; finish no reescribe por existir el archivo ni entrega Local, y mantiene el destino y las guardas de undo correctos.
- [X] T064 [P] [US3] Probar en `tests/comments-delivery-conflict.bats` destino cambiado/borrado/creado/vacío, symlink/directorio y archivo igual al preparado; comparar presencia+bytes con baseline, preservar ambas prosas y afirmar éxito idempotente sólo si destino ya coincide con preparado.
- [X] T065 [P] [US3] Probar en `tests/comments-finish-partial.bats` fallo de entrega después de replay completado: exit 1, diagnóstico de resultado parcial, salida de código registrada, Shared pendiente y Local accesible; ni éxito total ni segunda extracción en un intento posterior.
- [X] T066 [P] [US3] Probar en `tests/comments-prepare.bats` `prepare --check` humano/porcelain como lectura, tres roles baseline/prepared/destination con presencia/revisión, conflicto inspeccionable=0 y error de lectura=1; sin check, rechazo de `--porcelain`, de compare y de reemplazo forzado inexistente.
- [X] T067 [P] [US3] Probar en `tests/comments-finish-resume.bats` resolución manual igualando preparado/destino, reintento por prepare y `finish --resume`, destino ya entregado y repetición; contar replay/commits reales, validar revisiones y rechazar rama/destino/custodio distintos sin cambios.
- [X] T068 [P] [US3] Probar en `tests/comments-finish-undo.bats` `finish --abort` tras entrega, conflicto de replay y entrega pendiente; restaurar código con guardas existentes y conservar prosa actual, incluyendo cambios posteriores en otro archivo que un retry no debe absorber en `reviewundoouttree`.
- [X] T069 [P] [US3] Probar en `tests/comments-finish-onto-source.bats` entrega sobre destino real con `--onto-source`, source avanzado, cambios concurrentes propios/ajenos y códigos existentes; no resolver el destino otra vez por un nombre móvil ni repetir extracción para resolver comments.
- [X] T070 [P] [US3] Probar en `tests/comments-delivery-io.bats` fallos de temporal/escritura/rename/publicación de resultado y repetición tras cada fase, incluidas revisiones stale; preservar destino/original/candidato y registros de salida coherentes, sin éxito falso ni pérdida de la generación previa.
- [X] T071 [P] [US3] Probar en `tests/comments-portable.bats` copia manual del Shared a otro clon/lector sin producto, contexto portable y copia/pegado de bloques Local↔Shared con referencias intactas; no exigir ids/estados/respuestas ni ejecutar contenido, agentes o instrucciones del Markdown.

### Implementation for User Story 3

- [X] T072 [US3] Implementar comparación seed/prepared/destination-baseline por presencia+bytes en `bin/git-review-lib.sh`, incluyendo archivo heredado y Shared sin modificar; Local queda excluido del cálculo y de la entrega.
- [X] T073 [US3] Integrar entrega posterior al replay y anterior a `record_exit` en todos los caminos de `bin/git-review-verbs/finish`, incluido sin correcciones y `--onto-source`; escribir Shared completo sin stage/commit/push adicional.
- [X] T074 [US3] Implementar estados de entrega y registro de cierre parcial en `bin/git-review-lib.sh` y `bin/git-review-verbs/finish`: ante conflicto/I/O conservar preparado, publicar resultados recuperables, registrar salida de código y retornar error preciso sin repetir extracción.
- [X] T075 [US3] Implementar `comments prepare --context --check [--porcelain]` en `bin/git-review-verbs/comments` y `bin/git-review-lib.sh`, con comparación de prosa y rutas/presencia/revisiones para los tres roles; inspeccionar no adopta un baseline nuevo ni escribe documentos.
- [X] T076 [US3] Implementar reintento `comments prepare --context` en `bin/git-review-verbs/comments` y `bin/git-review-lib.sh`, aceptando igualdad deliberada destino/preparado y guardando conflicto en otro caso, sin `--force` ni conversión de compare a entrega versionada.
- [X] T077 [US3] Atender entrega pendiente en `finish --resume` antes del guard de rama review en `bin/git-review-verbs/finish`; verificar rama/destino/owner y reintentar exclusivamente prosa con resultado idempotente.
- [X] T078 [US3] Ajustar `record_exit`, actualización acotada de `reviewundoouttree` y `finish --abort` en `bin/git-review-verbs/finish`: incorporar sólo la escritura propia de Shared y preservar guardas frente a cambios posteriores de código.
- [X] T079 [US3] Exponer entrega prepared/pending/delivered y diagnósticos en `comments status` de `bin/git-review-lib.sh`, con resultado parcial distinguible de finish-conflict y sin obligar a interpretar stdout humano.
- [X] T080 [US3] Completar protección de destino/tipos, temporales recuperables y publicación íntegra en `bin/git-review-lib.sh`, conservando bytes de documentos mal formados sin exigir resolver su histórico para entregar o terminar.
- [X] T081 [US3] Ejecutar las familias de entrega y `tests/finish-state.bats`, `tests/finish-abort.bats`, `tests/step-replay.bats`/`tests/merge.bats`; probar sensibilidad a replay duplicado, baseline adoptado silenciosamente y snapshot de undo absorbente, y registrar evidencia en `specs/016-comentarios-review/quickstart.md`.

**Checkpoint**: una review sólo con comentarios termina sin inventar correcciones;
un resultado parcial se recupera sin perder prosa ni repetir código extraído.

## Phase 7: User Story 6 - Volver al código que motivó un comentario (Priority: P1)

**Goal**: consultar cada entrada con sus OID originales y distinguir lado ausente,
historia perdida y ubicación no reproducible sin modificar la sesión actual.

**Independent Test**: capturar B1/H1 y B2/H2, renumerar, avanzar a H3 y borrar
el archivo actual; comparar ambos diffs y recetas con árboles/blobs esperados.
Un objeto faltante da exit 5 sin fallback y un picker viejo da exit 4.

### Tests for User Story 6

- [X] T082 [P] [US6] Probar en `tests/comments-history.bats` dos pares B1/H1 y B2/H2 tras H3/renumeración/cambio de rama, archivo eliminado actualmente, cambio step intermedio y entrada general; afirmar diff y OID exactos de cada entrada sin consultar HEAD como reemplazo.
- [X] T083 [P] [US6] Probar en `tests/comments-history-paths.bats` rename con paths distintos, adición/borrado legítimo y archivo vacío; espacios/acentos/guion inicial/`*`/`?`/`:`/`%`/`>`/backticks, doble escape y TAB/CR/LF no representables en TSV deben mantener paths literales o diagnosticar sin emitir registros ambiguos.
- [X] T084 [P] [US6] Probar en `tests/comments-history-missing.bats` objetos commit/tree/blob requeridos ausentes y clon superficial real frente a archivo ausente sólo en working tree; exit 5 y stderr específico, sin receta parcial utilizable, fetch, ref nueva ni sustitución por head actual.
- [X] T085 [P] [US6] Probar en `tests/comments-history-invalid.bats` entrada manual sin refs, metadata duplicada/desconocida/incompleta, OID inválido y `unversioned` con/sin rango versionado; comentario intacto y diagnóstico que no promete reproducir el buffer sucio.
- [X] T086 [P] [US6] Probar en `tests/comments-history-stale.bats` ordinal cero/fuera de rango, números visibles repetidos y documento editado/reordenado/renumerado después del picker; revision stale=4 sin abrir otra entrada ni cambiar ningún documento/contexto.
- [X] T087 [P] [US6] Probar en `tests/comments-history-argv.bats` argv Git capturados por wrapper delegado al Git real: extremos como argumentos separados, pathspec literal, `--no-ext-diff`, sin textconv, sin `B..H` ni log/rev-list/shortlog/range-diff; incluir lower de tipo tree y cwd profundo.
- [X] T088 [P] [US6] Probar en `tests/comments-history-recipe.bats` TSV completo con árboles, blobs present/absent y líneas, general sin archivo inventado y falla de blob diferenciada de blob vacío; afirmar cantidad/campos de todas las filas y ausencia de código adjunto.
- [X] T089 [P] [US6] Probar en `tests/comments-history-readonly.bats` consulta con otra review activa y tras guardar/limpiar, snapshots de refs/objetos/config/índice/working tree y almacenamiento, sin sesiones/retención/fetch nuevos; ext-diff/textconv maliciosos configurados no se ejecutan.

### Implementation for User Story 6

- [X] T090 [US6] Implementar selección por contexto/documento/revisión/ordinal y validación de metadata en `bin/git-review-lib.sh`, con OID inmutables originales y diagnóstico explícito para manual/unversioned; no usar número visible como identidad.
- [X] T091 [US6] Implementar resolución/validación de árboles y blobs en `bin/git-review-lib.sh`, soportando commit/tree y SHA-1/SHA-256, rename y lados legítimamente ausentes; diagnosticar objeto perdido sin consultar existencia del archivo actual como criterio histórico.
- [X] T092 [US6] Implementar `comments diff` humano en `bin/git-review-verbs/comments` y `bin/git-review-lib.sh` con extremos separados, rutas literales y ejecución sin ext-diff/textconv, checkout, fetch ni retención de código.
- [X] T093 [US6] Implementar receta `comments diff --porcelain` en `bin/git-review-verbs/comments` y `bin/git-review-lib.sh`: validar todo antes de emitir filas utilizables y distinguir present/absent/error; conservar los límites de bytes del TSV.
- [X] T094 [US6] Completar diagnósticos/códigos 4/5 e integración con entries/status en `bin/git-review-verbs/comments` y `bin/git-review-lib.sh`, sin bloquear renumeración/custodia o navegación por objetos ausentes y sin actualizar OID al volver a consultar.
- [X] T095 [US6] Completar captura de referencias por modo/paso y marca `unversioned` en `bin/git-review-lib.sh`, validando blob/coordenadas y guard de cursor; no crear snapshots o refs para hacer reproducible contenido que Git no contiene.
- [ ] T096 [US6] Ejecutar las familias `tests/comments-history*.bats` y `tests/porcelain-bytes.bats`/`tests/range.bats` en contenedor y CI real; demostrar que fallback a HEAD, pathspec expansivo y blob perdido convertido en vacío fallan, y registrar evidencia en `specs/016-comentarios-review/quickstart.md`.

**Checkpoint**: histórico disponible consultable incluso sin archivo actual;
histórico perdido diagnosticado y comentario conservado. Los visores de hosts
se conectan a esta receta en US5, no reconstruyen rango/identidad por su cuenta.

## Phase 8: User Story 5 - Acceder desde la CLI y los cuatro clientes (Priority: P2)

**Goal**: cinco superficies con los mismos documentos/reglas, captura explícita,
guardado selectivo, refresco y diff histórico en cada entorno.

**Independent Test**: el mismo fixture produce la misma renumeración por CLI y
cuatro clientes; los tres IDE capturan selección/caret sin guardar código, la
TUI compone sin editor gráfico, y ninguno cambia el destino por defecto.

### Puerta de release de la CLI

Esta puerta antecede a la habilitación de consumidores de los nuevos argv. Se
pueden preparar tests en rojo; no se integra un cliente con piso futuro o que
declare compatible una CLI sin comments. La publicación se realiza por el flujo
de release del repositorio cuando corresponda, fuera de la generación de tareas.

- [ ] T097 [US5] Ampliar pruebas de versión/capacidad en `vscode-extension/test/unit/version.spec.ts`, `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/VersionTest.kt`, `visualstudio-extension/tests/GitReview.Domain.Tests/VersionTests.cs` y `tui/internal/domain/version_test.go`: una CLI anterior al primer release con comments informa actualización antes de invocar sus argv y el piso local coincide con el canónico de su cliente.
- [X] T098 [US5] Documentar los ocho subcomandos/guards/códigos/entrada por editor y el flujo CLI en `CLI.md`, `CLI.es.md`, `README.md` y `README.es.md`, y actualizar `completions/git-review-workflow.bash`, `completions/git-review-workflow.zsh` y `completions/git-review-workflow.fish`; conservar traducciones espejo y no publicar capacidades aún ausentes.
- [ ] T099 [US5] Preparar y verificar el release CLI con `bump-version.sh`, `VERSION`, `bin/git-review`, `package.json`, `Formula/git-review-workflow.rb` y `CHANGELOG.md`, eligiendo versión al cortar release; registrar en `specs/016-comentarios-review/quickstart.md` tag/release publicado y evidencia de sus ocho argv antes de habilitar T122..T143, sin inventar un piso ni publicar desde esta etapa documental.

### Tests for User Story 5

- [ ] T100 [US5] Añadir pruebas negativas del canónico en `scripts/check-client-product-surface.test.mjs` y ampliar `scripts/check-client-product-surface.mjs`: 29 acciones bidireccionales, cinco controles de fila fuera de menús, `comments_rows`, labels/tooltips/iconos, dos filas, exclusión vigente y `reveals.addComment` condicionado a `comments_block_born`; una mutación por regla debe hacer fallar su gate.
- [ ] T101 [P] [US5] Añadir `vscode-extension/test/unit/commentsRecords.spec.ts` y `vscode-extension/test/unit/commentsFlow.spec.ts` con fixtures TSV: todos los tags de comments, filas extra/desconocidas, ausencia frente a count ilegible, contextos múltiples, guards y ordinal+revision; no parsear Markdown ni stdout humano.
- [ ] T102 [P] [US5] Añadir `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/CommentsTest.kt` con los mismos vectores de registros/argv/guards/identidad y diagnóstico independiente del estado de código; el dominio permanece sin imports IntelliJ.
- [ ] T103 [P] [US5] Añadir `visualstudio-extension/tests/GitReview.Domain.Tests/CommentsTests.cs` con los mismos vectores de registros/argv/guards/identidad, delivery pending y falta de count sin inventar cero; el dominio permanece sin APIs de Visual Studio.
- [ ] T104 [P] [US5] Añadir `tui/internal/domain/comments_test.go` con los mismos vectores de registros/argv/guards/identidad, acciones por situación y resultados múltiples sin selección por recencia; comprobar dominio sin filesystem ni procesos.
- [ ] T105 [P] [US5] Añadir `vscode-extension/test/integration/comments-panel.spec.ts` y `vscode-extension/test/unit/commentsCapture.spec.ts`: compositor multilínea, selección invertida/columna cero/caret, Local→Shared→Local, cancelación/whitespace, destino no retenido, contexto cambiado y save=false/throw/still-dirty; afirmar cero invocaciones tras fallo, texto conservado y código sucio intacto.
- [ ] T106 [P] [US5] Añadir `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/host/CommentsActionsTest.kt` y ampliar `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/ui/VfsAccessTest.kt`: captura previa al foco, rangos, compositor cancelado, EDT de save y VFS fuera del EDT, postcondición unsaved, guards originales y cero mutación si no persistió.
- [ ] T107 [P] [US5] Añadir `visualstudio-extension/tests/GitReview.Host.Tests/CommentsActionsTests.cs` y escenarios en `visualstudio-extension/src/GitReview.VS/Preview/PreviewApp.cs`: callback de guardado exacto con HRESULT fallido/cancelado/dirty, selección/caret y compositor multilínea, destino obligatorio y retención de texto; reservar la prueba de APIs VSIX reales para el smoke de host.
- [ ] T108 [P] [US5] Añadir `tui/internal/ui/comments_test.go`: Enter como nueva línea, Ctrl+Enter y Save por Tab/Enter, Esc, foco y pegado multilínea, destino obligatorio/no retenido, contexto stale y error con texto conservado; demostrar que las teclas no disparan acciones globales ni exigen editor gráfico.
- [ ] T109 [P] [US5] Añadir `vscode-extension/test/unit/commentsWatch.spec.ts` y ampliar `vscode-extension/test/unit/state.spec.ts`: rutas sólo desde porcelain, guardar Markdown exacto, debounce/refresh vigente, cierre de watchers, diagnóstico comments sin error global y estado inicial Reading sin modelo de entorno viejo.
- [ ] T110 [P] [US5] Añadir `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/host/CommentsWatchTest.kt` y ampliar `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/host/RepositoryRefreshTest.kt`: refresh tras guardar/mutar, rutas ausentes/presentes de ambos documentos, cierre/cambio de contexto y fallos comments separados.
- [ ] T111 [P] [US5] Ampliar `visualstudio-extension/tests/GitReview.Host.Tests/DraftWatcherTests.cs` y `visualstudio-extension/tests/GitReview.Host.Tests/ReviewStateManagerTests.cs`: rutas reportadas, guardado exacto, cambio de contexto, dispose y diagnóstico aislado, sin leer contenido en watchers.
- [ ] T112 [P] [US5] Ampliar `tui/internal/host/watchset_test.go`, `tui/internal/host/statecycle_test.go` y `tui/internal/ui/repaint_test.go`: vigilancia explícita 0/1, refresh manual correcto, rutas desde CLI, no sondeo nuevo de comments ni redibujado que pierda formulario; no redefinir el default vigente.
- [ ] T113 [P] [US5] Ampliar `vscode-extension/test/unit/cliLog.spec.ts` y añadir `vscode-extension/test/unit/commentsInvoke.spec.ts`: stdin UTF-8 completo con saltos/EOF, guards en argv, cancelación/error/timeout del proceso y ningún cuerpo en logs, salida diagnóstica o cadena de shell del cliente.
- [ ] T114 [P] [US5] Ampliar `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/host/CliInvokerIT.kt` y `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/CliLogTest.kt`: stdin UTF-8 mediante proceso real controlado, timeout/cancelación, cierre de stdin y cuerpo ausente de logs.
- [ ] T115 [P] [US5] Ampliar `visualstudio-extension/tests/GitReview.Host.Tests/CliInvokerTests.cs`: stdin UTF-8, cierre del stream, error/timeout/cancelación y redacción de cuerpo en logging; afirmar orden de invocaciones y que el lock cubre refresh/guard/mutación.
- [ ] T116 [P] [US5] Ampliar `tui/internal/host/invoke_test.go`: stdin UTF-8, error/timeout/cancelación, cuerpo fuera de argv/logs y valores con metacaracteres como datos; impedir mutación después de guard obsoleto.
- [ ] T117 [US5] Ampliar los tests de layout/confirmación/revelado en `vscode-extension/test/unit/panelHtml.spec.ts`, `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutContractTest.kt`, `visualstudio-extension/tests/GitReview.Domain.Tests/PanelLayoutContractTests.cs` y `tui/internal/domain/layout_contract_test.go`: bloque en cuerpo sin tools dentro de review, dos filas sin precedencia, Prepare sólo pending de review, diálogo de entrada declarado, sin confirmación de Add/Create ni toast/apertura automática/agente, revelado sólo al nacer bloque.
- [ ] T118 [P] [US5] Añadir `vscode-extension/test/integration/comments-diff.spec.ts`: recetas H1/H2 desde H3, base/head de diff propio, URI con procedencia transitoria, archivo actual borrado, blob ausente frente a vacío y picker stale; validar contenidos inmutables y no cambio de rama.
- [ ] T119 [P] [US5] Añadir `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/diff/CommentsDiffTest.kt`: receta histórica, contenidos base/head y coordenadas del lado anterior, generales y objetos faltantes sin contenido vacío sustituto; comprobar no dependencia de editor/archivo actual.
- [ ] T120 [P] [US5] Añadir `visualstudio-extension/tests/GitReview.Host.Tests/CommentsDiffTests.cs`: receta/blobs, fallo de lectura, side base/head, general y selector stale; registrar en `specs/016-comentarios-review/quickstart.md` el complemento de smoke para el visor nativo y vistas opacas.
- [ ] T121 [P] [US5] Ampliar `tui/internal/host/open_test.go` y añadir `tui/internal/ui/comments_diff_test.go`: selector ordinal+revision, pager con diff calculado, lado explícito, salida/fallo del editor configurado y vuelta al panel, sin capturar selección externa ni cambiar de sesión.

### Implementation for User Story 5

T122..T143 se integran como un cambio coherente después de T099: el canónico,
sus cuatro consumidores y los gates quedan alineados en el resultado integrado.
No se mergean bypasses `existsSync`, contadores transitorios ni gates decorativos.

- [ ] T122 [US5] Ampliar `contracts/client-product-surface.yaml` y `scripts/check-client-product-surface.mjs` con 29 acciones, `comments_rows`, cinco controles, copy/teclado/condición de revelado y diálogos de entrada declarados; conservar los mapas de iconos, puertas únicas y exclusión de `openAllChanges` en Visual Studio.
- [ ] T123 [P] [US5] Implementar modelos/parser/flow de comments en `vscode-extension/src/cli/commentsPorcelain.ts`, `vscode-extension/src/review/commentsFlow.ts` y `vscode-extension/src/views/panelModel.ts`, con guard provisional, revisiones, diagnóstico independiente y receta histórica; no leer Markdown ni reconstruir paths.
- [ ] T124 [P] [US5] Implementar registros/argv/flow/copy/layout en `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/Comments.kt`, `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/ActionArgv.kt`, `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/UserCopy.kt` y `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/PanelLayout.kt`.
- [ ] T125 [P] [US5] Implementar registros/argv/flow/copy/layout en `visualstudio-extension/src/GitReview.Domain/Comments.cs`, `visualstudio-extension/src/GitReview.Domain/ActionArgv.cs`, `visualstudio-extension/src/GitReview.Domain/UserCopy.cs` y `visualstudio-extension/src/GitReview.Domain/PanelLayout.cs`, sin APIs del host ni otro archivo con `#if`.
- [ ] T126 [P] [US5] Implementar registros/argv/flow/copy/layout en `tui/internal/domain/comments.go`, `tui/internal/domain/actions.go`, `tui/internal/domain/intent.go`, `tui/internal/domain/layout.go`, `tui/internal/domain/keymap.go` y `tui/internal/domain/usercopy.go`; declarar 24 nativas+4 delegadas+1 excluida y controles fuera de acciones.
- [ ] T127 [P] [US5] Incorporar stdin UTF-8 y logging sin cuerpo en `vscode-extension/src/cli/invoke.ts` y `vscode-extension/src/cli/cliLog.ts`, conservando `GIT_REVIEW_ADVICE=0`, timeout/cancelación y ejecución por argv sin shell para texto.
- [ ] T128 [P] [US5] Incorporar stdin UTF-8 y logging sin cuerpo en `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/host/CliInvoker.kt` y `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/CliLog.kt`, preservando contratos de timeout/cancelación y advice.
- [ ] T129 [P] [US5] Incorporar stdin UTF-8 y logging sin cuerpo en `visualstudio-extension/src/GitReview.Host/CliInvoker.cs` y `visualstudio-extension/src/GitReview.Domain/CliLog.cs`; ubicar compatibilidad BCL necesaria exclusivamente en `visualstudio-extension/src/GitReview.Host/Compat/ProcessCompat.cs`.
- [ ] T130 [P] [US5] Incorporar stdin UTF-8, guards y logging sin cuerpo en `tui/internal/host/invoke.go`, preservando locks de mutación, cancelación/timeout y advice sin ejecutar texto como shell.
- [ ] T131 [P] [US5] Implementar captura y comandos en `vscode-extension/src/commands/comments.ts`, compositor textarea en `vscode-extension/src/views/commentsComposer.ts`, filas en `vscode-extension/src/views/panelHtml.ts` y copy en `vscode-extension/src/review/userCopy.ts`; capturar selección antes del foco, guardar sólo Markdown exacto, refrescar revisión de bytes conservando guard original y gestionar ambos buffers antes de save/finish/abort/forget.
- [ ] T132 [P] [US5] Implementar compositor multilínea y dispatch en `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/ui/CommentsComposer.kt`, `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/ui/PanelActionDispatcher.kt`, `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/ui/actions/ReviewActions.kt` y `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/host/EditorFiles.kt`; VFS sólo por puerta fuera de EDT, save exacto en EDT con persistencia comprobada y buffers de sesión gestionados antes del descarte.
- [ ] T133 [P] [US5] Implementar compositor WPF con AcceptsReturn y callbacks en `visualstudio-extension/src/GitReview.VS/ToolWindows/CommentsComposer.cs`, `visualstudio-extension/src/GitReview.VS/ToolWindows/PanelHost.cs`, `visualstudio-extension/src/GitReview.VS/ToolWindows/ActionDispatcher.cs` y `visualstudio-extension/src/GitReview.VS/Vsix/VsHostActions.cs`; retornar guardado verificable de SavePathAsync/HRESULT y gestionar únicamente buffers de comments afectados.
- [ ] T134 [P] [US5] Implementar formulario textarea y controles en `tui/internal/ui/comments.go`, `tui/internal/ui/program.go`, `tui/internal/ui/keys.go` y `tui/internal/ui/render.go`: destino inicialmente sin elegir, texto conservado ante error/stale, Enter multilínea, Ctrl+Enter/Save y Esc consumidos antes del keymap global, apertura con editor configurado.
- [ ] T135 [P] [US5] Conectar selector/revisión y receta histórica a `vscode-extension/src/commands/openEntry.ts` y `vscode-extension/src/views/previewContentProvider.ts`, asociando procedencia transitoria de diffs propios a refs/ruta/lado; abrir `vscode.diff` con versiones inmutables y comparar prosa de prepare por su camino separado.
- [ ] T136 [P] [US5] Conectar receta histórica/procedencia de lados a `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/diff/OpenEntryActions.kt`, usando SimpleDiffRequest de blobs y selector ordinal+revision; diagnóstico para visor opaco, objeto perdido y unversioned, sin depender del archivo actual ni iniciar otra sesión.
- [ ] T137 [P] [US5] Conectar receta histórica al servicio nativo de diferencias en `visualstudio-extension/src/GitReview.VS/Vsix/VsHostActions.cs` y `visualstudio-extension/src/GitReview.VS/Diff/RangeChanges.cs`, conservando procedencia de vistas propias y selector ordinal+revision; separar diff de código de comparación de prosa pending y no inventar contenido vacío ante error.
- [ ] T138 [P] [US5] Conectar selector temporal, diff calculado y comparación de prosa de entrega en `tui/internal/ui/comments.go` y `tui/internal/host/open.go`, con pager/terminal y contexto/lado explícitos; permitir regreso al panel y explicar límites sin crear sesiones históricas.
- [ ] T139 [P] [US5] Integrar refresh/watch/guardado/acciones y revelado condicionado en `vscode-extension/src/review/state.ts`, `vscode-extension/src/review/draftWatch.ts`, `vscode-extension/src/extension.ts`, `vscode-extension/src/views/reveal.ts` y `vscode-extension/package.json`; registrar sólo Add/Save como acciones y conservar panelHtml como un único template literal.
- [ ] T140 [P] [US5] Integrar refresh/watch/menús/layout/revelado en `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/host/GitReviewService.kt`, `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/host/DraftWatcher.kt`, `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/host/PanelReveal.kt`, `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/ui/PanelRenderer.kt` y `jetbrains-plugin/src/main/resources/META-INF/plugin.xml`, sin VFS desde EDT ni controles de fila en Tools.
- [ ] T141 [P] [US5] Integrar refresh/watch/listener/layout/revelado en `visualstudio-extension/src/GitReview.Host/ReviewStateManager.cs`, `visualstudio-extension/src/GitReview.Host/DraftWatcher.cs`, `visualstudio-extension/src/GitReview.VS/Vsix/DocumentSaveListener.cs`, `visualstudio-extension/src/GitReview.VS/ToolWindows/GitReviewPanelController.cs`, `visualstudio-extension/src/GitReview.VS/ToolWindows/PanelView.cs`, `visualstudio-extension/src/GitReview.VS/ToolWindows/PanelReveal.cs` y `visualstudio-extension/src/GitReview.VS/Vsix/GitReviewPackage.vsct`; usar PanelButtons y mantener controles de fila fuera de `.vsct`.
- [ ] T142 [P] [US5] Integrar refresh/watch/alcance del bloque en `tui/internal/host/statecycle.go`, `tui/internal/host/watchset.go`, `tui/internal/domain/watchset.go` y `tui/internal/ui/render.go`, consumiendo sólo rutas de porcelain, vigilancia efectiva 0/1 y refresh manual, sin sondeo de comments ni perder el formulario en repaint.
- [ ] T143 [US5] Tras acreditar T099, recalcular y actualizar juntos `min_cli_version` por cliente en `contracts/client-product-surface.yaml` y sus constantes en `vscode-extension/src/cli/version.ts`, `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/Version.kt`, `visualstudio-extension/src/GitReview.Domain/Version.cs` y `tui/internal/domain/version.go`; usar la primera CLI publicada que satisfaga las invocaciones de cada uno y ejecutar T097.
- [ ] T144 [US5] Ejecutar las suites de registros/host/UI de US5 y los escenarios de igual fixture por cinco superficies de `specs/016-comentarios-review/quickstart.md`; comprobar bytes iguales, fallo de save que impide CLI, elección renovada, stale por step y diff histórico con archivo borrado, dejando smoke real pendiente explícito si aún no se ejecutó.

**Checkpoint**: cuatro adaptadores consumen los mismos contratos; el panel
refresca antes de informar, no duplica éxitos, no abre documentos al terminar y
no ofrece botones para agentes. Sólo el smoke puede acreditar APIs reales del
host; los tests de dominio no lo sustituyen.

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: cerrar regresiones, portabilidad, documentación y evidencia integral.

- [ ] T145 [P] Actualizar flujo y límites por cliente en `vscode-extension/README.md`, `jetbrains-plugin/README.md`, `visualstudio-extension/README.md` y `tui/README.md`, sin promesas de paridad, Ctrl+click, estados ni histórico garantizado cuando faltan objetos; conservar links absolutos en README empaquetado de VS Code.
- [ ] T146 [P] Actualizar instrucciones de desarrollo/tests y rationale en `CONTRIBUTING.md`, `vscode-extension/CONTRIBUTING.md`, `jetbrains-plugin/CONTRIBUTING.md`, `visualstudio-extension/CONTRIBUTING.md`, `tui/CONTRIBUTING.md`, `decisiones.md` y `AGENTS.md`, con custodia, reintentos, matrices, límites de CAS/identidad y número canónico 29; escribir documentos de trabajo en español y preservar encabezados de plantillas.
- [ ] T147 Actualizar/enlazar listas cerradas de invocación en `specs/002-extension-vscode/contracts/cli-invocation.md`, `specs/006-superficie-panel-completa/contracts/cli-invocation.md`, `specs/009-plugin-intellij/contracts/cli-invocation.md` y `specs/015-cliente-tui/contracts/cli-invocation.md`, y la tabla de `visualstudio-extension/src/GitReview.Domain/ActionArgv.cs`, incluyendo argv/stdin/lecturas de blobs permitidas sin ensanchar invocaciones ajenas a comments.
- [ ] T148 Añadir escenarios/expected y revisar individualmente cambios en `tui/internal/ui/fixtures_test.go`, `tui/internal/ui/golden_test.go` y `tui/testdata/golden/`: Local/Shared/ambos/ausente, identidad ambigua, pending y formulario, normal/ASCII y ambos tamaños; no aceptar regeneración masiva sin revisar ni depender sólo de snapshots para acciones.
- [ ] T149 Ejecutar `./lint-docker.sh` y `./tests/run-docker.sh` para el alcance de `bin/`/`tests/`, luego la suite CLI completa; validar nombres ASCII, empaquetado del verbo nuevo, pines bats y suites de delta/walkthrough/undo, registrando comandos/exit/test count en `specs/016-comentarios-review/quickstart.md`.
- [ ] T150 Ejecutar en contenedor, desde raíz, `node --test scripts/check-client-product-surface.test.mjs`, `node scripts/check-client-product-surface.mjs` y `node scripts/check-logo-assets.mjs`; desde `vscode-extension/`, `npm run pretest` y `npm run test:unit`; desde raíz, `./vscode-extension/test/run-docker.sh`; registrar resultados sin dar por verde una suite omitida en `specs/016-comentarios-review/quickstart.md`.
- [ ] T151 Ejecutar en contenedor desde `jetbrains-plugin/` `./gradlew test checkDomainNoIntellij verifyPluginProjectConfiguration verifyPluginStructure --no-daemon` y la verificación de plugin requerida por `jetbrains-plugin/CONTRIBUTING.md`; comprobar plataforma mínima vigente y VFS gate, registrando resultados en `specs/016-comentarios-review/quickstart.md`.
- [ ] T152 Ejecutar en contenedor desde `visualstudio-extension/` `dotnet test tests/GitReview.Domain.Tests` y `dotnet test tests/GitReview.Host.Tests`; en Windows ejecutar el verificador WPF `dotnet run --project src/GitReview.VS -- --verify` y `./build-vsix.ps1` con MSBuild/net472, registrando ambas clases de evidencia en `specs/016-comentarios-review/quickstart.md`.
- [ ] T153 Ejecutar en contenedor desde `tui/` `gofmt -l .` (salida vacía), `go vet ./...` y `go test ./...`, incluyendo tests de alcance/teclado/mouse y todos los golden revisados; registrar versiones, vigilancia explícita 0/1 y resultados en `specs/016-comentarios-review/quickstart.md`.
- [ ] T154 Verificar en `.github/workflows/ci.yml` la inclusión de las nuevas familias/gates y correr la matriz real Ubuntu/macOS/Windows con fixtures de bytes y awk pertinentes; no sustituirla por Docker ni omitir casos de Git Bash, SHA-256, symlinks o permisos sin evidencia de capacidad y cobertura equivalente registrada en `specs/016-comentarios-review/quickstart.md`.
- [ ] T155 Ejecutar smoke real de los tres IDE y TUI según `specs/016-comentarios-review/quickstart.md`: selección actual/anterior/invertida, guardado fallido/cancelado, código que sigue sucio, dos destinos, compare save, pending resuelto y diff con archivo actual borrado; declarar límites de visor opaco y Ctrl+Enter con alternativa Save accesible.
- [ ] T156 Auditar sensibilidad de asserts conforme a `tests/fixtures/comments/README.md`, reutilizando evidencia vigente de checkpoints y completando huecos en copias desechables: alterar dígitos/cuerpo/EOL, eliminar un guard, mezclar documentos/generación, reejecutar replay, falsear count cero, fallback a HEAD y save fallido continuado; registrar test/aserción que detecta cada mutación y posterior verde en `specs/016-comentarios-review/quickstart.md`.
- [ ] T157 Preparar notas y artefactos de los cuatro clientes en `vscode-extension/CHANGELOG.md`, `jetbrains-plugin/CHANGELOG.md`, `visualstudio-extension/CHANGELOG.md` y `tui/CHANGELOG.md`, usando sus `bump-version.sh` sólo al elegir versiones de release; comprobar `tests/release-notes.bats`, `tests/version-consistency.bats` y que el release CLI de T099 precede a cualquier publicación de consumidores.
- [ ] T158 Cerrar trazabilidad de FR-001..FR-056 y SC-001..SC-014 en `specs/016-comentarios-review/tasks.md` y `specs/016-comentarios-review/quickstart.md`, contrastar docs bilingües con contratos/copy y ejecutar `git diff --check`; reportar checks no ejecutados/fallidos sin marcarlos completos ni publicar releases como efecto de esta tarea documental.

## Dependencies & Execution Order

### Phase Dependencies

```text
Setup T001..T004
  └─ Foundational T005..T015
       └─ US1 T016..T029
            ├─ US2 T030..T040
            └─ US4 T041..T061
                 └─ US3 T062..T081
US1 + US2 + US4 + US3
  └─ US6 T082..T096
       └─ US5 T097..T144
            ├─ CLI publicada T099 → consumidores T122..T143
            └─ cuatro clientes → Polish T145..T158
```

El orden de IDs es la ruta secuencial recomendada. El grafo muestra las
dependencias de habilitación, no permisos para editar un archivo compartido a
la vez. US2 y la preparación de tests de US4 pueden avanzar por separado tras
US1; sus cambios en la librería se integran secuencialmente. US6 usa el selector
de US2 y el ciclo de US4/US3 para validar referencias tras cierre/reintento.

### Within Each User Story

- Escribir tests y comprobar rojo antes de implementar el comportamiento.
- Las tandas `[P]` de tests parten de helpers/fixtures ya terminados; no alteran
  esos archivos compartidos simultáneamente.
- Completar modelos/helpers antes de dispatch/adaptadores y éstos antes de
  integración con UI/watchers. Toda mutación usa la misma puerta de escritura.
- En US5, T123..T126 requieren T100..T104 y T122; T127..T130 requieren los
  tests de stdin T113..T116. T131..T134 requieren modelos/invocadores respectivos
  y T105..T108; T135..T138 requieren además T118..T121. T139..T142 requieren
  los tests de refresh T109..T112 y las piezas correspondientes del cliente.
- T131/T135/T139, T132/T136/T140, T133/T137/T141 y T134/T138/T142 son
  secuenciales dentro de cada cliente por archivos e integración compartidos.
- T117 y T100 cambian tests/gates distintos pero se coordinan con T122:
  canónico, tablas, manifests y consumidores deben quedar verdes juntos.
- No tomar un checkpoint técnico como aceptación pendiente de otro cliente,
  smoke pendiente o autorización para publicar.

### Parallel Opportunities

La siguiente tabla describe tandas posibles para una ejecución futura; no
implica iniciar agentes ni repartir trabajo sin autorización.

| Historia | Ejemplo de tanda paralela | Condición previa |
|----------|--------------------------|------------------|
| US1 | T016 `tests/comments-add.bats` + T017 `tests/comments-input.bats` + T018 `tests/comments-location.bats` | Foundational terminada; fixtures compartidos congelados |
| US2 | T030 `tests/comments-renumber.bats` + T031 `tests/comments-fences.bats` + T032 `tests/comments-bytes.bats` | US1 terminada |
| US4 | T041 `tests/comments-navigation.bats` + T042 `tests/comments-save-continue.bats` + T046 `tests/comments-compare-save.bats` | US1 terminada; integración de librería secuencial |
| US3 | T062 `tests/comments-finish-delivery.bats` + T064 `tests/comments-delivery-conflict.bats` + T068 `tests/comments-finish-undo.bats` | US4 terminada |
| US6 | T082 `tests/comments-history.bats` + T083 `tests/comments-history-paths.bats` + T084 `tests/comments-history-missing.bats` | US2/US3/US4 terminadas |
| US5 | T101..T104 (dominios), luego T123..T126 (implementaciones por cliente) | Tests con fixtures comunes listos; implementación tras T099/T122 |

Los adaptadores de clientes distintos pueden progresar en paralelo después de
modelos e invocadores. Los cuatro cambios en pisos/canónico de T143 se hacen en
una sola integración coherente, nunca copiando el piso de otro cliente.

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Completar Setup y Foundational con oráculos confiables.
2. Completar US1 por CLI: captura Local/Shared explícita, entradas generales o
   localizadas, cancelación y edición manual, sin tocar código.
3. Validar su checkpoint antes de ampliar parser/ciclo. Es un MVP técnico para
   probar el núcleo, no el alcance publicable acordado: faltan las demás
   historias y los cuatro clientes.

### Incremental Delivery

1. US2 aporta renumeración/selector y conservación exacta de bytes.
2. US4 aporta navegación/custodia/resultados y checkpoint de compare.
3. US3 aporta entrega tras finish, conflicto, resultado parcial, retry y undo.
4. US6 aporta histórico inmutable con objetos disponibles y diagnóstico de
   faltantes. Ninguna fase incorpora snapshots o retención de código.
5. Validar/publicar CLI mediante el flujo habitual; acreditar T099.
6. US5 integra los cuatro clientes y sus pisos ya publicados con canónico/gates.
7. Polish cierra matrices, sensibilidad de asserts, documentación, hosts reales
   y artefactos de clientes. Ningún cliente queda diferido a otra entrega.

## Trazabilidad de aceptación y requisitos

Las referencias de esta tabla señalan tareas que implementan y prueban cada
requisito. La columna de evidencia se completa al ejecutar, no al generar esta
lista. FR-038/FR-039 gobiernan alcance y decisiones, no necesitan un test
tautológico sobre prosa que repita el texto de la especificación.

| Requisitos | Tareas principales / oráculo |
|------------|------------------------------|
| FR-001..FR-005 | T016..T019, T024..T028, T030..T032, T071; edición libre y cuerpos íntegros |
| FR-006..FR-009 | T030..T032, T034..T038; esperado byte a byte y segunda pasada idéntica |
| FR-010..FR-012 | T019, T031..T034, T036..T039; no filtrar por diff, WIP y error sin escritura |
| FR-013..FR-015 | T016, T021..T024, T041, T062..T064, T072..T073; par independiente y Local privado |
| FR-016..FR-017 | T062, T069, T071, T073; Markdown portable, sin commit/push/envío |
| FR-018 | T008..T009, T064..T067, T070, T072..T080; baseline exacto, conflicto y recuperación |
| FR-019..FR-021 | T041..T045, T049..T061, T068, T078; modos, custodia, cierre/undo/clean |
| FR-022..FR-024 | T018, T041, T062, T068, T082..T095; sin código ficticio y referencias fieles |
| FR-025..FR-027 | T097..T104, T117..T144, T148, T155; acceso simultáneo y cinco superficies |
| FR-028..FR-029 | T017, T025, T105..T108, T113..T116, T127..T134; multilinea/selección/stdin/editor |
| FR-030..FR-031 | T005, T014, T035, T101..T104, T109..T112, T139..T142; autoridad CLI y refresh |
| FR-032..FR-033 | T008, T086, T105..T108, T118..T121, T131..T138; save exacto, guards y picker stale |
| FR-034..FR-035 | T007..T009, T033, T048, T065, T100, T117, T122, T139..T142; copy/gates y errores aislados |
| FR-036..FR-037 | T022, T071, T089, T145; offline y texto libre, sin ejecutar agentes |
| FR-038..FR-039 | T004, T028, T071, T082..T096, T146, T158; D15/D17 vigentes, sin decisiones inventadas |
| FR-040 | T098, T145..T147, T157..T158; contratos/docs bilingües y límites por host |
| FR-041..FR-042 | T041..T042, T050..T054, T062, T072; sin banco step y seed propio |
| FR-043 | T016, T020..T021, T024, T105..T108, T131..T134; destino explícito por captura |
| FR-044..FR-045 | T020..T021, T044..T049, T055..T060; descarte por checkpoint y ámbitos |
| FR-046..FR-048 | T018, T026, T082..T095, T118..T121, T135..T138; OID/ordinal/revisión y faltantes |
| FR-049 | T105..T108, T118..T121, T131..T138, T145, T155; lados propios, selección y límites declarados |
| FR-050..FR-052 | T087..T089, T100, T117..T122, T135..T138; sin agente/Ctrl+click/sesiones/retención |
| FR-053..FR-054 | T046..T047, T057, T107..T108, T117, T133..T134; compare sólo prosa y checkpoint |
| FR-055 | T062..T070, T072..T080; entrega tras código y retry sin replay |
| FR-056 | T006, T011, T050..T052; rango completo/linaje, heredado y resolución explícita |

| Criterio | Verificación independiente requerida |
|----------|--------------------------------------|
| SC-001 | T016..T022/T029: capturar/editar/borrar con código/índice intactos |
| SC-002..SC-003 | T030..T040: 100 entradas, orden/cuerpos completos e idempotencia por bytes |
| SC-004 | T041..T045/T061 + T062/T068/T081: ciclo en whole/walk/step |
| SC-005 | T062/T071: un Shared legible sin el producto y sin Local |
| SC-006 | T101..T104/T117/T144/T155: mismo fixture renumerado por cinco superficies |
| SC-007 | T105..T107/T118..T120/T155: selección/caret/rangos en tres IDE reales |
| SC-008 | T007..T009/T033/T043/T047/T064..T070/T105..T107: fallos y concurrencia sin pérdida |
| SC-009 | T062/T073/T081: finish sólo prosa sin commit de correcciones ficticio |
| SC-010 | T022/T034/T089: operaciones locales sin red |
| SC-011 | T016/T021/T041/T105..T108/T144: Local→Shared→Local y otro destino intacto |
| SC-012 | T082..T096/T118..T121/T144/T155: H1/H2 desde H3 y archivo actual borrado |
| SC-013 | T042..T045/T050/T061/T068: guardar/continuar/descartar respetando lo previo |
| SC-014 | T046..T047/T057/T061/T144: compare conserva exactamente lo guardado sin código |

## Notes

- 158 tareas: Setup 4, Foundational 11, US1 14, US2 11, US4 21,
  US3 20, US6 15, US5 48 y Polish 14.
- Las verificaciones de tests de producto se ejecutarán durante implementación.
  Esta etapa sólo genera y valida el plan de tareas.
- Setup de Spec Kit: `setup-tasks.sh --json` ejecutado en contenedor, feature y
  plantilla resueltas a rutas absolutas; todos los documentos opcionales leídos.
- No hay `.specify/extensions.yml`: no se despachan hooks before_tasks/after_tasks.
- Preservar la rama actual y los cambios preexistentes de selección/documentos.
- Si aparece una ambigüedad de producto nueva, registrarla y comunicarla en el
  chat; no reabrir decisiones cerradas ni inventar una respuesta en una tarea.
