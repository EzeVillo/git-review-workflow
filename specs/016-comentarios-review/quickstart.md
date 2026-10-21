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

### 2026-10-18 — Candidato CLI y empaquetado

Se preparó `codex/comments-cli` en un worktree administrado separado, conservando
`main` y sus cambios. `bump-version.sh 0.10.0` se ejecutó en contenedor y agregó
el heading correspondiente al changelog; el SHA de Homebrew queda para el flujo
de release. [PR borrador #12](https://github.com/EzeVillo/git-review-workflow/pull/12).
No se creó un tag, release ni publicación npm.

`npm pack --ignore-scripts --json` desde un clon Linux del candidato produjo
`git-review-workflow-0.10.0.tgz`, 29 archivos, con el verbo privado `comments`
en modo 0755. Instalación local con `npm install --ignore-scripts --no-audit
--no-fund`: exit 0. Las ayudas y un smoke operativo de los ocho subcomandos
pasaron desde ese paquete instalado: captura UTF-8 multilínea, renumeración,
receta histórica, checkpoint de compare y entrega pendiente resuelta con
prepare. El reintento mantiene las entradas originales del índice; no stagea
la resolución de Shared.

CI macOS detectó un error de sintaxis de Bash 3.2 al sourcear la biblioteca.
Se reprodujo con `bash:3.2 bash -n bin/git-review-lib.sh` (exit 1 en el `case`
de comments_status), se balancearon los patrones dentro de la sustitución y
el mismo comando pasó (exit 0). La regresión status/context/legacy/results
descubrió 31 tests y terminó con exit 0. El commit de corrección es
`671ade0ffc800055c7745371079233ab8b749c86`; la nueva matriz CI está en curso.
Las ejecuciones CI del commit anterior fueron canceladas por estar superadas.

La suite completa sobre `f91b8d98bb28dcda215bb36375c750608e7ac9e4`, clonada
dentro del contenedor, descubrió **1.340 tests y terminó con exit 0**. Se
conservan los skips de capacidad explícitos de la suite; npm se comprobó por
el smoke separado anterior. Shellcheck sobre toda la lista vigente de CI,
incluido el bump de TUI, terminó con exit 0 después de la corrección de Bash.
La lista binaria de fixtures conserva `-text` y desactiva sólo en ese directorio
el control de whitespace deliberado (CRLF, espacios y EOF de los oráculos).
`git diff --check` del candidato pasó sin normalizar esos datos.

Auditoría adicional en copia desechable: añadir LF al EOF falló por EOF en
`cmp`; cerrar una fence con delimitador insuficiente falló en byte 35/línea 4;
emitir count cero falló en la igualdad exacta del stream de status; alterar
un cuerpo falló en byte 33/línea 5; ordenar bloques por su número visible
falló en byte 30/línea 3 del esperado de cien entradas. Los cuatro casos
restaurados (dos mutantes usan el mismo caso de cien entradas) pasaron, exit 0.

Ubuntu CI todavía falla en lecturas de status; no se atribuye verde de CI al
resultado del contenedor. El arnés ahora informa stdout/stderr al fallar esa
lectura para aislar la diferencia. Los mismos 15 casos de status/add pasaron
con dash y One True AWK y luego con dash y mawk 1.3.4.

T097 se comenzó fuera de la rama candidata de CLI: los tests de versión de
VS Code, Visual Studio y TUI compilaron y fallaron por su assert de aceptar
0.9.x como compatible. Es el rojo esperado antes de elevar los pisos, no
una suite de clientes aprobada. El intento de JetBrains falló por una caché
inmutable de Gradle alterada antes de ejecutar el test; se reintenta en una
caché propia, sin borrar la anterior. El reintento compiló y ejecutó
`VersionTest.commentsRequiresUpdatingAnOlderCli`: 1 test, 1 fallo en
`VersionTest.kt:12`, el assert previsto. Quedan acreditados los cuatro rojos
de clasificación de versión. Falta integrar su gate antes de invocar comments
y verificar el piso publicado/canónico; T097 permanece pendiente.

El aborto de Ubuntu se aisló después en GNU Awk 5.2.1: pasar al predicado de
rutas un elemento opcional ausente del array provoca `free(): double free
detected in tcache 2`. Se reprodujo en Ubuntu 24.04 con Git 2.43, descartando
que requiriera el Git 2.55 del runner. El fixture mínimo tiene sólo base/head
y ninguna ruta. El nuevo test de entries falló en su status esperado; después
de materializar esos dos argumentos como cadenas, pasó sin cambiar el stream
esperado. No se adoptó la variante exploratoria de vaciar arrays de otra forma,
que no resolvía el aborto.

Regresión posterior: 61 tests en GNU Awk 5.2.1, 35 con BusyBox awk y 35 con
One True AWK, todos exit 0. Sintaxis Bash 3.2 y shellcheck, exit 0. Ahora hay
282 tests de comments y la suite completa descubre 1.341. El control corto de
status agregado al inicio de CI pasó en Ubuntu para el commit
`f663c1eaea042ce9dc54e404b7d79dbb1a976e64`; la matriz completa sigue pendiente.

Para ese mismo commit, [CI Ubuntu](https://github.com/EzeVillo/git-review-workflow/actions/runs/39180555294/job/117832191170)
completó la suite: `1..1341`, último test 1341 aprobado, job `success`.
El contrato inicial de nueve tests pasó además en macOS y Windows; sus suites
completas continúan en ejecución. Esto aún no cierra T040, T096 ni T154.

El tarball del commit final volvió a pasar el smoke operativo de los ocho
comandos y quedó en `dist/git-review-workflow-0.10.0.tgz` del worktree candidato.
SHA-256: `c42ef4f82deb5262e0107ab20c7c94832415878e7eafac12eecda63ad6c7bd34`.
Es el hash del paquete npm local, no el SHA del tarball fuente de GitHub que
fijará el workflow de release. El release público sigue pendiente de T099.

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

## Evidencia local de clientes — 2026-10-19

El usuario autorizó adelantar el desarrollo de los cuatro consumidores para
probar el conjunto desde sus interfaces, sin enviar ni publicar cambios. Se
prepararon versiones candidatas CLI 0.10.0, VS Code/JetBrains 0.5.0, Visual Studio
0.4.0 y TUI 0.2.0. No acreditan T099/T143 ni se cambiaron la PR, tags o releases.

Todos los procesos ejecutables que admiten Linux se corrieron en Docker. Se
copió el código a un filesystem Linux, con scripts LF y permisos ejecutables;
no se normalizaron los fixtures de bytes. Se usaron Node 22, JDK 21, SDK .NET 8,
Go 1.25 y bats 1.13.0. Los logs locales están en `dist/comments-*.log`.

| Verificación | Resultado |
|---|---|
| `node --test scripts/check-client-product-surface.test.mjs` | exit 0, 14 pruebas; mutaciones de filas, 29 acciones, revelado y diálogos rechazadas |
| Canónico y assets del logo | exit 0; 29 acciones, 47 controles, 11 iconos, 13 confirmaciones |
| VS Code `npm run pretest` y `npm run test:unit` | exit 0; 495 aprobadas, 1 pending preexistente |
| VS Code Electron, suite completa | exit 0; 100 aprobadas, incluidas 8 nuevas de comentarios |
| JetBrains `test checkDomainNoIntellij verifyPluginProjectConfiguration verifyPluginStructure buildPlugin verifyPlugin -PverifierIdes=idea --no-daemon` | exit 0; 346 pruebas, 0 omitidas/fallos/errores; Compatible con IU-261.22158.277 |
| Visual Studio dominio / host | exit 0; 405 / 62 aprobadas, sin omitidas |
| Windows `build-vsix.ps1`, MSBuild con net472 y verificador WPF | exit 0; 30 fixtures, incluidos Local/Shared/ambos/ausente/pending |
| TUI `gofmt -l .`, `go vet ./...`, `go test ./...` | salida de formato vacía; exit 0; cinco paquetes aprobados |
| TUI golden | 68 previos + 42 de comentarios = 110; siete escenarios, dos tamaños y tres modos |
| Shellcheck, lista completa de CI y `.shellcheckrc` | exit 0, sin salida |
| Suite CLI completa en copia Linux | 1343 casos; 284 de comentarios aprobados; cuatro fallos de empaquetado por haber omitido `.git` de la copia inicial |
| Repetición CLI con índice real montado read-only | exit 0, 53 aprobadas: packaging/version-consistency/release-notes/test-names/comments-status/comments-client-custody; resuelve los cuatro fallos de infraestructura anteriores |
| `npm pack --ignore-scripts` de CLI y VSIX/ZIP/binario de clientes | empaquetados localmente; metadatos y SHA256 en el manifiesto del conjunto |
| `git diff --check` | exit 0 |

La primera copia de pruebas de JetBrains no tenía Git ni los assets externos que
sus tests existentes comparan; se corrigió la preparación y no se omitieron esos
tests. En VS Code, repetir la misma identidad de fixture abría legítimamente el
selector de contextos; los casos ahora tienen fuentes independientes. La API
TextDocument es inmutable, por eso el test de save falso/excepción/still-dirty
inyecta exclusivamente la frontera de guardado en el extension host de pruebas;
no pretende haber provocado un fallo de disco real en el IDE del usuario.

Las pruebas nuevas confirman Local → Shared → Local, selección invertida,
código que sigue sucio y con disco/índice intactos, cancelación/whitespace sin
creación, texto retenido ante fallo de save o cambio de sesión, diff de blobs
inmutables aunque el archivo actual se borre y rechazo de un picker con revisión
obsoleta. El fixture TSV común comprueba los 19 tags en los cuatro adaptadores,
count ilegible frente a cero y custodia por `comments-owner`. La TUI detectó en
rojo un envío ocupado que bloqueaba su formulario; la corrección conserva su
usabilidad. Otro test en rojo detectó Comments después del inventario; se corrigió
la ubicación antes de inventario/footer en los paneles. Se probó también un
padre de documento reportado más profundo que la clausura habitual del watcher.

La captura de stdin de los invocadores de Kotlin y C# se ejercitó con más de
120 kB de UTF-8, CRLF y sin salto final, usando el hash Git esperado. Los errores
que devuelven el cuerpo no lo vuelcan al log. Los casos específicos de timeout,
cancelación, visores opacos y procedencia de todos los lados todavía no acreditan
por completo T106/T107/T109..T121; las casillas conservan ese límite explícito.

El conjunto de prueba está en `dist/comments-preview-20261019/`: cuatro paquetes,
CLI extraída, binario TUI de Windows, sandbox limpio sobre main con dos commits
feature/comments y remoto bare exclusivamente local. No se inició la review con
Git Linux para evitar fijar una custodia ajena al host Windows. El usuario puede
iniciarla desde el panel. `abrir-vscode.ps1` prepara un perfil aislado únicamente
cuando el usuario lo ejecuta; los scripts no se lanzaron ni se instalaron plugins.

Quedan pendientes el smoke interactivo de los IDE/TUI (T155), la matriz remota de
estos cambios (T154), los casos y la auditoría completa aún sin casilla y cualquier
publicación. La compatibilidad estática del ZIP y la compilación con SDK reales
no sustituyen las APIs de selección, VFS/RDT y diferencias en un IDE interactivo.
El control del contenido del VSIX detectó que el build incremental había
conservado el manifiesto 0.3.0. Se ejecutó MSBuild con -t:Rebuild y
GitReviewPackVsix=true (exit 0); el VSIX final contiene Identity Version=0.4.0.
También se inspeccionaron package.json de VS Code (0.5.0 y 29 acciones),
META-INF/plugin.xml dentro del JAR del ZIP JetBrains (0.5.0), el --version
del ejecutable Windows TUI (0.2.0) y el dispatcher incluido (0.10.0).

La verificación de atributos detectó que el patrón antiguo de golden no
alcanzaba el subdirectorio nuevo. Se añadió una regla explícita LF y
-whitespace para los 42 snapshots de comentarios; git check-attr confirma
los valores. Conserva el padding del terminal y evita CRLF en Windows.

## Legibilidad y descarte de comentarios — 2026-10-19

Se implementó la etiqueta visible del cuerpo en los cuatro formularios, el
explorador con fragmentos, alcance, lado y líneas, el detalle completo previo
al diff y la marca de coordenadas sobre los objetos originales. La TUI añade
extracto numerado con contexto y detalle desplazable. Inicialmente los IDE
mantenían el explorador abierto junto al diff; la iteración de cierre descrita
al final reemplaza ese comportamiento. No se requiere abrir el Markdown.
Delete admite copias conservadas después de Finish y deja intacta la copia ya
entregada. Un descarte Shared pendiente no se transforma en borrado del destino.

Evidencia de esta iteración (logs locales `dist/reading-*.log`):

| Verificación | Resultado |
|---|---|
| CLI, todas las specs `comments-*.bats` | 292 aprobadas, exit 0; después, 7 focalizadas aprobadas con un caso nuevo de concurrencia durante la lectura |
| ShellCheck, lista completa de CI | exit 0, sin salida |
| Contrato de superficie y assets | exit 0; 29 pruebas del gate, incluidos controles negativos de etiqueta, detalle, rango y borrado posterior |
| VS Code, compilación y unitarias | exit 0; 497 aprobadas y 1 pending preexistente |
| VS Code real, integración de comentarios | exit 0; 9 aprobadas, incluidas selecciones históricas base/head tras borrar el archivo actual y rechazo de una instantánea obsoleta |
| JetBrains, dominio/host/UI y frontera de dominio | exit 0; 363 pruebas, sin fallos ni omisiones |
| JetBrains, ZIP/estructura/Plugin Verifier | exit 0; Compatible con IU-261.22158.277 |
| Visual Studio, dominio/host | exit 0; 407 / 62 aprobadas |
| Windows, MSBuild net472/VSIX y verificador WPF | exit 0; 30 fixtures |
| TUI, formato, `go vet` y tests | exit 0; 122 golden: 110 previos y 12 nuevos de explorador/diff |
| `git diff --check` | exit 0 |

La copia Linux inicial necesitó permisos ejecutables. Se evitó volver a extraer
scripts mientras una suite los ejecutaba. El empaquetado headless de IntelliJ
necesitó crear el directorio config del sandbox antes de ejecutar
buildSearchableOptions; después se ejecutó la tarea real y el verificador sin
omitirla. Estos preparativos no cambian la configuración del repositorio.

La selección real de VS Code está probada en Electron. La compilación y el
Plugin Verifier no sustituyen el smoke interactivo de IntelliJ/Visual Studio;
ese chequeo manual sigue pendiente antes de publicar. No se publicaron ni
instalaron clientes en esta iteración.

## Cierre del explorador al abrir el diff — 2026-10-19

Open diff cierra el explorador sólo después de abrir correctamente la vista
histórica en VS Code, JetBrains, Visual Studio y TUI. Un error conserva la
selección y permite reintentar. JetBrains espera la apertura efectiva en el EDT
antes de informar éxito. En la TUI el diff conserva sólo el comentario elegido:
Tab permite leer su prosa, Enter vuelve al diff y Esc regresa al panel sin lista.

Verificación de esta iteración:

- Contrato compartido: 37 pruebas del gate y checker aprobados, exit 0.
- VS Code en contenedor: compilación y tipos aprobados; integración real de
  comentarios con 11 casos aprobados, exit 0, incluidos cierre en base/head y
  rechazo de una revisión obsoleta con el explorador conservado.
- Visual Studio en Windows: `dotnet run --project src/GitReview.VS -- --verify`,
  exit 0 con 30 fixtures; incluye la compilación WPF del cambio.
- JetBrains en contenedor con JDK 21 y Git: `gradlew test --rerun`, exit 0;
  compilación del plugin y suite completa aprobadas. Se normalizó el launcher
  CRLF únicamente en una copia temporal del contenedor.
- TUI en contenedor: `go test ./internal/ui`, `go vet ./...` y formato de los
  archivos modificados aprobados. Las regresiones comprueban cierre al abrir,
  retorno directo al panel y conservación de la selección ante errores.
  `go test ./...` conserva un fallo ajeno en `TestIconVocabularyMatchesCanonical`:
  exige cinco iconos mientras el contrato vigente declara siete. Host y UI
  pasan tras copiar los scripts con permisos ejecutables al contenedor.

El fallo del vocabulario quedó resuelto en la iteración siguiente del mismo día:
la TUI incorpora `eye` y `numbered`, con glifos Unicode seguros y alternativa
ASCII, y el test compara los nombres con el contrato leído. Verificación en
contenedor: `go test ./...`, `go vet ./...`, `go build ./cmd/git-review-ui` y
`gofmt -l .`, todos con exit 0 y sin archivos pendientes de formato. El checker
compartido también termina con exit 0; no se regeneraron golden.

## Correcciones de la reauditoría — 2026-10-19

El usuario cambió el contrato de entrega: Shared queda staged junto con las
correcciones, sin commit ni push adicionales. Se corrigieron CRLF limpio, tema
y tamaño mínimo del compositor WPF y selección de contextos con nombres iguales.
La descripción de candidatos sigue viniendo de la CLI y no expone cuerpos.

Evidencia final en `dist/comments-fixes-20261019/`:

- `cli-final.log`: 338 casos de comentarios aprobados, sin omisiones, exit 0.
  Incluye nueve regresiones nuevas; `staging-verified.log` repite 35 casos de
  entrega, I/O, concurrencia, Prepare y Undo con la implementación final.
- `vscode-verified.log`: compilación/tipos, 506 unitarias aprobadas y un pending
  preexistente; 108 integraciones Electron aprobadas. Checker, 41 tests del gate
  y assets aprobados en la misma ejecución.
- `gradle-final.log`: test, frontera de dominio, buildPlugin, configuración y
  estructura aprobados con JDK 21 y Git dentro del contenedor.
- `dotnet.log`: 409 tests de dominio y 68 de host aprobados en contenedor.
- `wpf-final.log`: 30 fixtures existentes y 40 checks nuevos del compositor
  aprobados. `renders-final.log` e imágenes revisadas visualmente.
- `vsix-final.log`: MSBuild/net472/VSIX aprobado en Windows.
- `tui-final.log`: formato, vet y tests de los cinco paquetes aprobados. El
  detector de carreras también aprobó durante esta iteración.
- ShellCheck completo más helper de equipo, revisión final focal de la librería,
  gate ASCII de nombres de tests y `git diff --check`: exit 0.

Al comparar snapshots, el helper desactiva `diff.autoRefreshIndex` explícitamente
para que observar un índice con entradas cacheinfo no cambie sus bytes. Se
conservó el assert de índice idéntico ante un Undo rechazado.

Alcance, decisión y límites en
[el registro de correcciones](correcciones-auditoria-2026-10-19.md). T154/T155
continúan pendientes: no se sustituyen IDEs reales ni la matriz nativa por estos
tests. No se instalaron clientes personales ni se publicaron releases.

## Undo de Finish y cancelación posterior — 2026-10-19

Undo devuelve ambos textos actuales a la preparación, revierte la entrega
staged de Shared y restaura el resultado anterior al cierre (o su ausencia).
Cancelar después descarta la pasada deshecha y conserva lo previo.

Verificación en Docker, con `bin/` y `tests/` copiados a `/tmp/review-check`
y permisos ejecutables restaurados en esa copia; el checkout se montó sólo lectura:

- `bats tests/comments-*.bats tests/finish-abort.bats tests/finish-state.bats tests/test-names.bats`:
  399 casos aprobados, sin omisiones, exit 0. Incluye las 12 regresiones de
  `comments-finish-undo-cancel.bats`: modos, resultados previos ausentes/vacíos/con
  contenido, ciclos repetidos, reintentos y fallo de restauración del puntero.
- ShellCheck sobre la lista completa de `lint-docker.sh`: exit 0.
- `git diff --check` sobre los archivos modificados: exit 0.

## Cierre de revisión de TUI — 2026-10-20

Se corrigieron dos regresiones detectadas al revisar el checkout completo:

- Las reviews largas desplazan su contenido completo después del ajuste de
  líneas. El foco en ambos sentidos y la rueda permiten llegar a Comments sin
  perder la barra de teclas ni las coordenadas de clic. El resize mantiene
  visible el control enfocado. No se agregan herramientas de autor a la review.
- El watcher incorpora el padre del Shared del repositorio informado por la
  CLI, aunque esté fuera del gitdir. Allí filtra por el nombre exacto, sin
  vigilar recursivamente el working tree ni reaccionar a un walkthrough vecino.
  Se conservan los filtros de los documentos privados.

Las regresiones nuevas fallaron con el comportamiento anterior. La comprobación
de pantalla cubre whole/step/walk en 80×24 y 120×40, navegación en ambos sentidos,
rueda, clics y resize. La de vigilancia cubre repositorio normal y worktree
enlazado; fsnotify comprueba dos reemplazos atómicos de Shared sin cambios de Git.

Las notas de `[Unreleased]` se incorporaron a las versiones ya preparadas de
los cuatro clientes, sin cambiar sus números ni publicar versiones.

Verificaciones ejecutadas en contenedores sobre este checkout:

- CLI completa con Bats 1.13.0: 1.480 casos descubiertos, 1.475 aprobados,
  cinco omisiones de entorno declaradas y ningún fallo; exit 0. La copia de
  fuentes conserva acceso de sólo lectura al índice real para los tests de
  empaquetado y bits de ejecución.
- TUI: formato sin pendientes, `go vet`, suite completa con los 128 golden,
  detector de carreras y build; exit 0. El recorrido por pseudoterminal con
  watcher real captura Local → Shared → Local, entrega Shared sin Local al
  terminar y separa el contexto de una revisión posterior; exit 0.
- JetBrains: tests, frontera de dominio, `buildPlugin` y verificaciones de
  configuración y estructura; exit 0. La copia inicial omitía los assets de
  VS Code que necesita el test de iconos; se repitió con esos inputs presentes.
- Visual Studio: 417 tests de dominio y 68 de host aprobados en .NET 8.
- Canónico: 52 pruebas del gate, checker y assets aprobados. ShellCheck sobre
  la lista completa de CI: exit 0.
- VS Code había aprobado en esta misma revisión compilación, tipos y 520
  unitarias, con una pendiente preexistente; las correcciones posteriores sólo
  afectan TUI, documentación y las notas de las versiones preparadas.

Esto no sustituye la matriz nativa de tres SO ni los smokes interactivos en
los IDE o en una terminal real de Windows. T154/T155 conservan esos pendientes.
