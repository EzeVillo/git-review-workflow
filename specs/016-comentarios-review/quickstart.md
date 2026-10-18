# Quickstart: validación de comentarios portables

La implementación está en curso: los ocho subcomandos `comments` existen en el
checkout de trabajo. Las pruebas citadas abajo acreditan sólo los recorridos
ejecutados; la aceptación de clientes y la publicación siguen pendientes.
Contratos: [CLI](contracts/cli-porcelain.md),
[formato](contracts/comments-format.md), [ciclo](contracts/lifecycle.md) y
[clientes](contracts/client-surface.md).

## Prerrequisitos

Git y shell POSIX, checkout con la función implementada, `bin/` de ese checkout
al principio del PATH, identidad de Git para el sandbox y herramientas de cada
cliente según su `CONTRIBUTING.md`. Suites y herramientas disponibles en
contenedor se ejecutan allí. No correr bats nativo en Windows como sustituto.
Los smoke de IDE y MSBuild/VSIX requieren su host real.

## Evidencia de implementación

### 2026-10-18 — Setup, T001..T004

Prerrequisitos ejecutados en `git-review-tests` mediante
`.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks`:
feature `/repo/specs/016-comentarios-review`, todos los documentos detectados.
Checklist `requirements.md`: 16/16, sin pendientes. No existe
`.specify/extensions.yml`, por lo que no hay hooks de implementación.

Fixtures fuente/esperados en `tests/fixtures/comments/`, protegidos con `-text`.
El arnés aísla configuración Git, permite sólo protocolo file y no necesita red.
Sus snapshots se guardan fuera del working tree, no usan `write-tree` y comparan
también índice crudo, inventario de objetos y almacenamiento de comentarios.
La configuración de ignores existente cubre los artefactos de las toolchains;
el tarball npm tiene allowlist `files`. No hizo falta agregar ignores generales.

Comando reproducible desde PowerShell, con la raíz como directorio actual:

```powershell
docker run --rm -v "${PWD}:/repo:ro" -w /repo git-review-tests tests/comments-harness.bats tests/test-names.bats
docker run --rm -v "${PWD}:/mnt:ro" -w /mnt koalaman/shellcheck:stable -s bash tests/helpers/comments.bash
```

Descubrimiento: 14 tests del arnés y 2 del gate de nombres; 16/16 verdes.
Controles negativos: byte cambiado con igual longitud, ausencia frente a vacío,
ref/config/índice/prosa alterados y barrera sin participante producen el fallo
exacto esperado. La primera snapshot conserva el índice crudo y el inventario
previo; la segunda coincide íntegramente. Los fixtures de whole/walk/step/compare
se iniciaron con los verbos reales y verificaron su registro `state`.

Sensibilidad: en una copia temporal dentro del contenedor se reemplazó sólo la
comparación de bytes de `comments_assert_file` por una condición siempre falsa.
El test `comments oracle detects a same-length byte edit` falló en
`[ "$status" -eq 1 ]`; el checkout del usuario no se modificó para esta prueba.
El arnés original está verde. No se atribuye un ciclo rojo/verde de producto a
esta comprobación de infraestructura.

### 2026-10-18 — CLI, fundamentos y recorridos parciales de historias

Se implementaron identidad, manifiestos, custodia por gitdir, lock, guardas de
sesión/documento, generaciones completas y los ocho handlers. Cada start y
compare recibe una sesión exclusiva incluso sin contexto confirmado; esto
invalida formularios de una pasada idéntica anterior sin crear documentos.
Las sesiones antiguas siguen siendo consultables sin inicialización por lectura.
El valor `unreadable` para una revisión imposible de leer fue confirmado por el
usuario (D22); status conserva ambas filas y el diagnóstico sin inventar count.

Evidencia de contenedor, sin atribuirla a CI o a hosts reales:

- Regresión de status/config/list/dispatcher: 87 tests descubiertos, exit 0,
  con el skip del instalador que requiere filesystem escribible.
- Regresión de finish-abort/finish-state/step-replay/save/compare/clean:
  118 tests descubiertos, exit 0.
- Captura de ubicación/contexto y finish-abort, tras agregar sesiones exclusivas:
  57 tests descubiertos, exit 0. Coordenadas enormes y lado sin path tuvieron
  rojo específico y luego verde; no hay overflow de enteros del shell.
- Status/resultados/cierre/custodia básica: 19 tests, exit 0. La sesión pausada
  se informa como `saved`, conserva el path editable y permite renumerar antes
  de continue. Dos contextos tienen guards distintos y no se eligen por recencia.
- Fences dirigidas y fallos de renumeración: 8 tests, exit 0. Se comparan los
  bytes, carácter/longitud/indentación de fences, quotes e info-string; las fallas
  de copia/rename acreditan su inyección y preservan original/candidato.
- Compare con cero y dos checkpoints e inyección antes de publicar `current`:
  2 tests, exit 0. El puntero de resultado es también el checkpoint de descarte;
  no hay un segundo puntero susceptible de fallar después de publicar el par.
- Colisiones de custodio en save/continue: ambos tests fueron rojos por cambios
  reales en refs/HEAD y quedaron verdes al adelantar el preflight. El caso de
  worktree enlazado también quedó verde sin adoptar el gitdir ajeno.
- Parser con GNU Awk 5.3.2 y con One True AWK (`original-awk`): los mismos
  30 tests de renumber/entries/status terminaron con exit 0 en cada entorno.
  La imagen habitual usa BusyBox awk. Shellcheck de helpers y producción: exit 0.

Comandos reproducibles de grupos nuevos, desde PowerShell:

```powershell
docker run --rm -v "${PWD}:/repo" -w /repo git-review-tests tests/comments-results.bats tests/comments-custody.bats tests/comments-compare-errors.bats
docker run --rm -v "${PWD}:/repo" -w /repo git-review-tests tests/comments-fences.bats tests/comments-renumber-errors.bats
docker run --rm -v "${PWD}:/mnt:ro" -w /mnt koalaman/shellcheck:stable bin/git-review-lib.sh bin/git-review-verbs/comments bin/git-review-verbs/save bin/git-review-verbs/continue
```

Sensibilidad en una copia desechable, restaurando cada cambio antes del siguiente:
los seis mutantes fueron detectados. Aceptar cualquier token rompió el assert
del diagnóstico exacto; ignorar guard stale rompió exit 4; copiar Local como
Shared rompió la publicación válida; emitir la vista normalizada rompió `cmp`
del BOM en el primer byte; forzar destino Shared rompió la ausencia del segundo
documento; absorber todo el working tree en el retry de undo rompió el rechazo
del código editado después del cierre. Los seis tests restaurados quedaron verdes.

La nueva corrida completa descubrió 1.193 tests y terminó con exit 0, con los
skips de entorno declarados por la suite. Se agregaron después casos dirigidos
y ajustes: esa corrida no se atribuye al estado final de todos esos ajustes.
Persisten matrices por ampliar en entrega e histórico y todos los adaptadores.
Los casos consolidados en
`comments-lifecycle.bats`, `comments-finish.bats` y `comments-renumber.bats` no
acreditan por sí solos las matrices exhaustivas de sus tareas de tests.

Ampliación posterior, con discrepancias observables antes de corregirlas:

- `comments-save-continue.bats` y `comments-abort.bats`: 12 tests, exit 0.
  Whole/walk/step × baseline ausente/vacío/presente, ambos documentos, código
  editado, pausa/continuación/abort y descarte de la guardada. Se preservan los
  bytes del baseline; guardar una review no publica el Shared ni avanza ese límite.
- `comments-clean.bats`: 5 tests, exit 0. Limpieza incompleta en los tres modos,
  retención de ediciones posteriores al finish y límites de fixes-only/delta.
- `comments-finish-delivery.bats`: 7 tests, exit 0. Whole/walk/step con y sin
  código editado, ambos documentos distintos y Shared vacío; HEAD queda en el
  tip esperado y sólo las correcciones de código quedan staged. Clean conserva
  los resultados. La entrega propia de prosa no añade un commit de correcciones.
- `comments-navigation.bats`: 5 tests, exit 0. El cursor step captura sus dos
  pares reales, conserva documentos al volver a un paso sin el archivo y no
  banca prosa; walk conserva B/H completos y cambia el guard. La renumeración
  funciona en ambos documentos de los tres modos, con cero y ordinales enormes.
- Históricos: 13 tests de history/missing/paths, exit 0. Árbol y blob realmente
  eliminados, clon shallow real, rename/adición/borrado y blob vacío, rutas
  literales UTF-8 y metacaracteres con una sola decodificación. El caso general
  con blob perdido fue rojo por exit incorrecto/salida parcial; ahora retorna 5
  sin receta ni diff incompletos. Los controles TSV se rechazan antes de emitir.
- `comments-history-argv.bats`: 2 tests, exit 0. Desde cwd profundo y con trees,
  se registra argv exacto con extremos separados y `:(top,literal)`; el caso
  fue rojo porque el path se interpretaba desde el subdirectorio. Ext-diff y
  textconv configurados no se ejecutan. Las consultas exportan `GIT_NO_LAZY_FETCH=1`.
- Repo SHA-256 real: captura con commits y con trees, tokens/OID completos de
  64 caracteres y recetas de ambos documentos, exit 0.
- Legacy: 4 tests, exit 0. Consultas/navegación sin claves nuevas no inicializan
  custodia. Un resultado previo nunca se ofrece como preparación editable de
  una sesión antigua: ese caso fue rojo y quedó verde con rutas prospectivas
  ausentes hasta la inicialización explícita, conservando el límite de abort.
- Las barreras tienen handshake ready/release con timeout en ambos extremos.
  Ya no dependen de abrir un FIFO sin límite en el proceso de bats. La falta de
  participante es un control negativo separado. Arnés/concurrencia/seguridad:
  32 tests, exit 0, incluido TERM y liberación del lock.
- Add y save revalidan contexto después de preparar candidatos. Carreras con
  barrera y cursor/extremo cambiado fueron rojas y ahora devuelven 4 sin
  sustituir el documento ni publicar otro checkpoint. El candidato queda recuperable.
- Fallo de publicación después de extraer código: caso rojo y luego verde;
  status expone la preparación completa y prepare la conserva sin replay nuevo.
  El diagnóstico distingue fallo de entrega de fallo de retención del resultado.

Documentación de los ocho argv/guards/códigos/editor en ambos CLI y README.
Completions bash/zsh/fish: sintaxis validada en contenedor; handlers bash/zsh
ejecutados con adaptadores de completion, y fish con `complete -C` comprobando
Local/Shared y flags de status sin sugerir los de add. Esto no acredita smoke
de una terminal interactiva ni de clientes.

### 2026-10-18 — Cierre de matrices CLI en contenedor

La regresión ampliada de comments, status/config/list/dispatcher, finish,
step-replay/merge/save/compare/step/walk/clean y porcelain/range descubrió
574 tests y terminó con exit 0. Los cambios posteriores de rutas literales y
arnés se verificaron en grupos dirigidos de 42 y 26 tests, ambos con exit 0.
La suite completa se vuelve a ejecutar sobre el candidato antes de publicarlo.

Las 56 familias `comments-*.bats` contienen 281 tests. Además de las matrices
anteriores, cubren compare con cero/uno/dos checkpoints, ambos documentos o
uno solo, colisiones y metadata borrada antes de mutaciones Git, cuatro
relaciones S/O/R y presencia ausente/vacía/con contenido. La entrega cubre
whole/walk/step con/sin correcciones, sólo preámbulo, múltiples pasadas,
`--onto-source` y source avanzado. Shared se lee en otro clon con Git y E/S
ordinaria; Local no viaja y el contenido de la prosa no se ejecuta.

Los fallos de entrega/publicación conservan la preparación completa y la
salida de código registrada. Prepare valida los tres roles antes de emitir
porcelain; no produce un stream parcial ante fallo de lectura. Undo conserva
ausencia/vacío, rechaza sobrescribir ediciones de un editor antiguo y limpia
la metadata de entrega anterior. Sus revisiones de publicación se guardan
en el manifiesto, sin absorber código editado después del finish.

Renumber/bytes/fences/errors/scale/entries: 37 tests, exit 0 por entorno con
BusyBox awk, GNU Awk 5.3.2 y One True AWK. Después se añadió un caso de carrera
externa que también pasó en la imagen habitual. Las rutas con espacios al
principio/final tuvieron rojo por comparación recortada y luego verde al usar
la normalización única sin recortar el argv literal. El arnés usa la ruta
canónica de Git y exige un symlink real; no acepta la copia de respaldo de MSYS.
Esto todavía no acredita ejecución macOS ni Git Bash en CI.

Sensibilidad adicional, siempre en copias desechables: fallback histórico a
HEAD rompió el assert de los dos pares originales; pathspec expansivo rompió
el diff desde cwd profundo; blob perdido tratado como vacío rompió exit 5.
Repetir extracción durante prepare rompió el HEAD inmutable; omitir la
comparación con baseline rompió el exit 1 del conflicto; retroceder el segundo
checkpoint rompió `cmp` del último Local guardado; bancar prosa en step rompió
la lista exacta de paths de código. Los siete tests restaurados pasaron.

Las tareas CLI ejecutadas se marcan completas en `tasks.md`; T040 y T096
mantienen pendiente su requisito de CI real. T099 todavía requiere un release
publicado: no hay pisos nuevos ni integración de clientes anticipada.

### Matriz de ejecución

| Alcance | Evidencia requerida | Estado |
|---------|---------------------|--------|
| Foundational / CLI | T005..T015: status, identidad, guardas, locks, generaciones y regresión | Implementado; evidencia arriba |
| US1 / CLI | T016..T029: whole/walk/step × Local/Shared, captura y cancelación | Verificado en contenedor |
| US2 / CLI | T030..T040: bytes, fences, 100 entradas, segunda pasada e inyección negativa | Verificado en contenedor; CI pendiente |
| US4 / CLI | T041..T061: custodia, navegación, descarte y compare con cero/uno/dos guardados | Verificado en contenedor |
| US3 / CLI | T062..T081: entrega, ausencia/vacío/contenido, retry/undo y errores de I/O | Verificado en contenedor |
| US6 / CLI | T082..T096: pares históricos, objetos perdidos y consultas sin efectos | Verificado en contenedor; CI pendiente |
| US5 / cuatro clientes | T097..T144: registros, guardado selectivo, stdin, stale, selección y layout | Pendiente |
| Linux en contenedor | Suites/gates de CLI y toolchains de clientes; acreditar tests descubiertos y rojo/verde por grupo | CLI parcial verificada; clientes pendientes |
| CI real | Ubuntu/macOS/Windows y tests de PowerShell; registrar ejecución real, sin inferir del contenedor | Pendiente |
| Hosts reales | Selección/diff/guardado en tres IDE, MSBuild/VSIX y terminal TUI | Pendiente |
| Release CLI | Tag publicado con los ocho argv antes de fijar pisos de clientes (T099) | Pendiente; sin publicación autorizada por este documento |

Hay recorridos CLI ejecutados y documentados; no está cerrada la aceptación
completa de la función. Conservar esta matriz y añadir evidencia por grupo;
no marcar smoke o CI como ejecutados a partir de tests de dominio.

## Sandbox mínimo

Desde la raíz del checkout implementado, dentro del entorno Linux de validación:

```sh
repo_root="$(pwd)"
export PATH="$repo_root/bin:$PATH"
sandbox="$(mktemp -d)"
git init -b main "$sandbox"
cd "$sandbox"
git config user.name 'Comments test'
git config user.email 'comments@example.invalid'
git config reviewworkflow.base main
printf 'first\nsecond\nthird\n' > sample.txt
git add sample.txt
git commit -m base
git switch -c feature/comments
printf 'first\nchanged\nthird\n' > sample.txt
git commit -am feature
git review start --offline --no-walk feature/comments
```

Es un repositorio temporal sin remotos ni envíos. Capturar `git status
--porcelain=v1`, `git write-tree`, `git diff --binary` y `git for-each-ref`
antes de las operaciones locales; compararlos después permite demostrar que
no se tocaron código/índice/refs. Guardar esas capturas fuera del working tree.

## 1. Captura, destino y cancelación

```sh
git review comments status --porcelain
git review comments add --document local --path sample.txt --side head \
  --start-line 2 --end-line 2 --text 'Why is this branch needed?'
printf 'Should we document recovery?\nThere may be two failure cases.\n' |
  git review comments add --document shared --stdin
git review comments add --document local --text 'Check the interaction with retries.'
git review comments status --porcelain
```

Esperado: Local 2, Shared 1; dos rutas del gitdir y ningún archivo nuevo en el
working tree. Repetir con sólo Local existente y cancelar una captura Shared:
Shared continúa ausente. Probar texto explícito vacío, stdin whitespace y
composición sin texto mediante `GIT_EDITOR`: no crean documento/entrada.
No se conserva el destino de una captura a la siguiente.

Abrir los paths de `comments-document` con el editor habitual. La CLI es la
autoridad de esos paths; no reconstruirlos desde el nombre de rama.

## 2. Repaso y renumeración

En Local, preparar 100 entradas con huecos/números repetidos, dos del mismo
archivo y una general. Mover un bloque completo al comienzo; incluir ejemplos
`## 9. example` en fences de backticks y tildes. Guardar sólo ese documento.

```sh
git review comments renumber --document local
git review comments entries --document local --porcelain
git review comments renumber --document local
```

Esperado: orden físico elegido y números 1..100; cuerpos/refs/Shared idénticos.
La segunda ejecución es idéntica por bytes. Usar fixtures BOM+CRLF, EOL mixtos
y sin LF final; comparar contra bytes esperados, no contra Markdown renderizado.
Un bloque de metadata sin cierre devuelve error y conserva el original.
Una referencia histórica inválida con límites claros se conserva y diagnostica,
sin bloquear la renumeración del documento.
Intentar agregar cuando el archivo acaba en una fence abierta o cuando el texto
de la captura contiene otro encabezado reservado sin cercar: se rechaza sin
mutación y el compositor conserva el texto. Corregir/cercar y repetir agrega
exactamente una entrada.

## 3. Navegación y custodia

Repetir un sandbox con dos commits y otro con walkthrough válido para cubrir
whole, step y walk. Después de capturar en ambos documentos:

```sh
git review save
git review continue feature/comments
git review comments status --porcelain
git review finish
git review comments status --porcelain
```

En step/walk, intercalar `next`/`prev` antes de guardar. Esperado: mismos cuerpos
y referencias originales; ningún documento bancado en `refs/review-edits/`.
Shared modificado queda en `.review/comments.md` en la rama resultante sin
commit ni push, Local permanece privado. `finish` sin cambios de código también
lo entrega. `clean` completado conserva los resultados consultables por contexto.

En otro recorrido, `finish --abort` vuelve a edición con ambos documentos.
Después, `abort` de sesión descarta sólo la pasada nueva y respeta el contenido
previo. `save` seguido de `forget --saved` descarta la preparación guardada,
sin borrar el baseline anterior ni el documento versionado del PR.

## 4. Guardar comentarios de compare

Desde fuera de una review y con árbol limpio:

```sh
git review compare main feature/comments --no-walk
git review comments add --document local --text 'First local result.'
git review comments add --document shared --text 'Separate shared preparation.'
git review comments save
git review comments add --document local --text 'Discard this later addition.'
git review abort
git review comments status --porcelain
```

Esperado: sobreviven ambos resultados guardados, sin la última entrada. Guardar
no cierra compare, no crea review-saved ni escribe `.review/comments.md`.
Repetir guardando por segunda vez para comprobar que el checkpoint avanza.
Comparar índice, working tree y refs de código antes/después de `comments save`.

## 5. Mismo PR, otro PR y prosa concurrente

| Caso | Preparación | Resultado verificable |
|------|-------------|-----------------------|
| Otra pasada mismo linaje | Actualizar feature sin integrar su tip en main | Continúa contexto y documentos |
| Compartido anterior no entregado al source | Nueva pasada con source igual al baseline | Conserva resultado preparado |
| PR nuevo con documento heredado | Integrar anterior y crear otra rama desde main | Contexto nuevo sin cargar comentarios heredados |
| Delta | El documento no cambió dentro del delta | Se usa rango completo para identidad |
| Rama reutilizada | Tip anterior integrado en base | No reutiliza por nombre |
| Force-push ambiguo | Linaje incompatible con registro local | Pide contexto explícito; no mezcla |
| Cambios en source y preparado | Ambos difieren del baseline | Preserva las dos versiones de Shared; Local no interviene |
| Pausa y colisión de dueño | Otro trabajo reclama los mismos archivos | Falla antes de mover rama/sustituir prosa |
| Worktree enlazado | Intentar continuar con dueño de otro gitdir | No se apropia del documento ajeno |

El fallback se valida con `comments init --document local --new-context` o
`--use-context <id>`. La elección no cambia el destino de capturas posteriores.

## 6. Consulta histórica y contexto obsoleto

Capturar una entrada contra B1/H1; actualizar el PR a H2 y capturar otra;
renumerar y avanzar a H3, donde se elimina `sample.txt`.

```sh
git review comments entries --document local --context <context> --porcelain
git review comments diff --document local --context <context> --entry 1
git review comments diff --document local --context <context> --entry 1 --porcelain
```

Esperado: primer diff usa B1/H1, segundo usa los suyos, aunque falte el archivo
actual. Renombres conservan ambas rutas; adición/borrado declara lado ausente.
Objeto requerido faltante devuelve exit 5 y No encontrado, sin cambiar rama,
hacer fetch ni sustituir por H3. Un buffer sin commit conserva ubicación sin
prometer reconstrucción de sus líneas.

Dejar abierto un formulario y cambiar step; dejar abierto un picker y editar
el Markdown. Confirmar con las guardas anteriores devuelve exit 4 y STALE,
sin tocar otro contexto ni abrir otra entrada con el mismo número visible.

## 7. Entrega parcial y recuperación

Intercalar un cambio externo de `.review/comments.md` después de capturar el
baseline. Ejecutar finish con Shared modificado. Esperado: código extraído,
destino ajeno intacto, preparado recuperable y entrega pendiente explícita.
Resolver manualmente el destino conforme al contrato; reintentar mediante
`comments prepare --context <id>` o `finish --resume`. No debe repetirse replay.
Antes, `comments prepare --context <id> --check --porcelain` ofrece rutas de
baseline/preparado/destino para comparar prosa. Igualar preparado y destino a
la resolución elegida permite completar sin aceptar sobrescritura implícita.

Modificar además un archivo de código después del finish y antes del reintento:
la snapshot de undo no absorbe ese cambio. `finish --abort` conserva su guarda
de divergencia. Repetir con fallo de I/O y con destino ya igual al preparado
para comprobar recuperación e idempotencia. No se hacen commits nuevos por
guardar el documento ni se notifica éxito total ante entrega fallida.

## 8. Clientes, suites y smoke

En cada IDE: selección invertida/multilínea, lado anterior de un diff propio,
buffer sucio, dos destinos intercalados, Cancelar y guardado del Markdown
fallido/cancelado. Comprobar que sólo se guarda ese documento y el código sigue
sucio. En TUI: multilinea, destino obligatorio, teclado completo, cancelar,
guardar compare y consulta con pager, sin editor gráfico.

Comandos existentes para verificación tras implementar:

```sh
./lint-docker.sh
./tests/run-docker.sh
./vscode-extension/test/run-docker.sh
node scripts/check-client-product-surface.mjs
```

Los dos últimos tipos de herramienta disponibles en Linux también corren en
contenedor. Además, en contenedores con sus toolchains, desde cada directorio:
`npm run pretest` y `npm run test:unit`; `./gradlew test`; pruebas de dominio/host
.NET 8; `gofmt -l .`, `go vet ./...` y `go test ./...`. Usar los comandos y
prerrequisitos de los CONTRIBUTING vigentes para evitar inventar wrappers.
`./build-vsix.ps1` y el smoke WPF/VSIX se ejecutan en Windows. CI conserva su
matriz real de tres sistemas y sus cuatro pines bats.

Revisar goldens TUI, layout/copy y las dos versiones bilingües de documentación.
Confirmar 29 acciones y cinco controles de fila, sin botón para agentes ni
apertura automática al terminar. Ejecutar smoke en los hosts reales antes de
publicar clientes; los tests de dominio no prueban APIs de editor.
