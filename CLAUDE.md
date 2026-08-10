# CLAUDE.md

## Qué es esto

Una suite de verbos de `git review` (shell POSIX) para revisar un pull request
**editándolo y ejecutándolo**. Todo cuelga del dispatcher `git review <verbo>`,
al estilo de `git bisect`/`git stash`. `git review start` materializa el diff
completo del PR como cambios *staged y sin commitear* sobre una rama
`review/<branch>` cuyo `HEAD` queda en el merge-base; editás/ejecutás en tu
working tree y después `git review finish` extrae *tus* ediciones a una rama
aparte `review-fixes/<branch>`. Ver `README.md` para la superficie completa de
comandos.

## Comandos (desarrollo)

```sh
# Lint — todo script de shell debe pasar shellcheck. shellcheck no viene con
# ninguna de las tres herramientas del proyecto (git, node, docker), así que
# corrélo por el contenedor: la lista de archivos es la misma de CI.
./lint-docker.sh                      # los archivos que lintea CI
./lint-docker.sh algun-script.sh      # uno solo, mientras iterás

# Tests de la CLI — bats. En Windows NO corras bats bajo Git Bash (minutos por
# archivo, fork emulado lento). Corré en el contenedor Linux:
./tests/run-docker.sh                 # toda la suite
./tests/run-docker.sh review.bats     # un solo archivo
./tests/run-docker.sh tests/range.bats extras.bats   # cualquier arg/path de bats

# Tests de integración de la extensión — misma regla, mismo motivo, otro
# contenedor (trae node + el VS Code headless). Ver la sección de la extensión.
./vscode-extension/test/run-docker.sh             # los 70 tests
./vscode-extension/test/run-docker.sh open-entry  # las specs que matcheen

# Pruebas manuales — arma un PR de juguete descartable (feature/checkout: 4
# commits, 5 archivos, walkthrough committeado, paths con espacio y acento) para
# probar --step y walk a mano, más una rama por cada estado que ese PR no puede
# mostrar (entradas sin anotar al final del orden, whole sin walkthrough,
# walkthrough stale que degrada) y
# tres reviews guardadas que arman el inventario del estado vacío. Reconstruye
# desde cero en cada corrida; el estado inicial es siempre el mismo. Los tests no
# lo usan: es solo para manotear los comandos.
./tests/sandbox.sh                    # (re)construye y dice cómo entrar
./tests/sandbox.sh -d /tmp/box        # en otro lado
```

**Todo lo que se puede correr en el contenedor se corre en el contenedor.** No
es preferencia: en Windows crear un proceso cuesta ~50 ms (CreateProcess + DLLs
+ Defender) contra ~1 ms en Linux, y las dos suites son básicamente procesos —
un `git review status --porcelain` son 9 procesos `git` más dos de shell, o sea
~960 ms en Windows contra ~41 ms en Linux. Un mismo escenario de spec midió
15,0 s nativo contra 0,69 s en el contenedor (~22×). CI igual corre las dos
suites en runners reales de ubuntu, macos y windows, así que el contenedor no
saltea nada: lo único que evita es esperar de más para aprender lo mismo. Cada
script construye su imagen en el primer uso.

La imagen de Docker (bats + git, `tests/Dockerfile`) se construye en el primer
uso y el repo se monta read-only; los tests crean sus repos temporales dentro
del contenedor. Los tests del instalador de PowerShell (`*-ps1.bats`) necesitan
`pwsh`, que no está en el contenedor, así que solo corren de verdad en CI / en
Windows local. CI corre shellcheck + bats en runners reales de **ubuntu, macos
y windows** en cada push y PR. **bats está pinneado a una única versión**
(`npm install -g bats@1.13.0`) en los tres runners, en `release.yml` y en
`tests/Dockerfile`: antes cada OS lo instalaba de una fuente distinta (`apt` /
`brew` / `npm`) con versiones distintas, y un flag que andaba en la más nueva
abortaba la suite en la vieja de apt — un fallo que sólo aparecía en CI. Si
subís la versión, subila en los cuatro lugares a la vez. **shellcheck** sigue
viniendo de tres fuentes distintas (`apt` / `brew` / `choco`), así que ahí sí
vale apuntar al mínimo común denominador.

## Arquitectura

- **`bin/git-review`** — el dispatcher, el **único** ejecutable que va al `PATH`
  (`git` lo descubre como `git review`). Rutea `git review <verbo> [args]` al
  ejecutable del verbo: resuelve su propia ubicación real (siguiendo symlinks),
  exporta `GIT_REVIEW_LIBEXEC=<su dir>`, hace `shift` y `exec`utea
  `git-review-verbs/<verbo>`. `-h`/sin args lista los verbos; `--version`/`-V`
  imprime la versión. Un verbo inexistente da `error:` a stderr (exit ≠ 0).
- **`bin/git-review-verbs/*`** — un ejecutable de shell POSIX por verbo (sin
  extensión; `chmod +x`), `prog="git review <verbo>"`. Son **privados**: no van
  al `PATH` ni se llaman `git-*`, así que `git` no los descubre como
  `git <verbo>`; el único punto de entrada es el dispatcher. Los que usan helpers
  compartidos sourcean `"${GIT_REVIEW_LIBEXEC:?}/git-review-lib.sh"`.
- **`bin/git-review-lib.sh`** — se *sourcea, nunca se ejecuta*. Tiene los
  helpers compartidos por los verbos de modo `--step` (`show_commit`,
  `load_step_review_meta`, `goto_step`). Los verbos lo sourcean vía
  `"${GIT_REVIEW_LIBEXEC:?}/git-review-lib.sh"` (el dispatcher exporta esa var con
  su dir real resuelto). Como solo define funciones, sourcearlo no tiene efectos
  secundarios. Es **libexec**: vive junto al dispatcher y los verbos, nunca en el
  `PATH` (symlink/copia según el instalador; ver `install.sh` / Homebrew /
  `web-install`).

### Modelo de estado — dónde vive el estado del review

Las sesiones de review son stateful y guardan todo en los datos de git del
repo, no en archivos del working tree:

- **Ramas:** `review/<branch>` (review activo), `review-fixes/<branch>`
  (ediciones extraídas), `review-saved/<branch>` (review pausado).
- **Config por rama** (`branch.review/<x>.review*`): `reviewmode`,
  `reviewsource`, `reviewtip`, `reviewstart`, `reviewcount`, `reviewstep` —
  llevan el modo y la posición en `--step`. Se leen defensivamente (`|| true`)
  porque con `set -eu` una clave borrada a mano abortaría el script en silencio.
- **Modo walk** (`reviewmode = walk`): un walkthrough (sidecar
  `.review/walkthrough.md`, committeado al PR por el autor con `git review
  walkthrough init/build`) convierte el `start` en un cursor de lectura sobre la
  review completa. El formato tiene tres piezas: el **preámbulo** (`## Heads-up`,
  todo lo previo a la primera entrada — `build` lo preserva verbatim menos los
  comentarios HTML, y `start`/`compare` lo imprimen una vez al entrar), las
  **entradas** (`## N. <path>` + el why) y el marcador reservado **`> key`** (línea
  suelta al tope del body: presencia = entrada esencial, ausencia = default; se
  filtra del why y se muestra como `(key)`). Los marcadores reservados van todos
  como líneas `> ...` al inicio del body — ver también el `> at: ` de v2. El
  cursor vive en claves **propias** — `reviewwalkstep`
  (1-based) y `reviewwalkcount` (guard) — nunca en `reviewstart/reviewcount/
  reviewstep`: el guard de metadata de `finish` aborta si esas claves de step
  existen sin `reviewmode=step` (y hay un guard espejo para claves walk sin
  `reviewmode=walk`). La secuencia de entradas NO se persiste: se re-deriva en
  cada verbo parseando el walkthrough del tip y filtrando por intersección de
  paths con el rango real, igual que step re-deriva `commits` con `rev-list`. En
  walk `HEAD` queda clavado en el lower bound, así que la derivación es estable
  aunque el usuario edite. Walk no banca refs (las ediciones viven en el working
  tree, como whole); el cursor muere con la rama. **Toda comparación de paths
  entre el walkthrough y git pasa por dos puntos únicos de normalización, y solo
  por ahí:** `walk_normalize` (bytes del sidecar — CR final y BOM UTF-8) y
  `changed_paths` (lado git — `core.quotePath=false`, más el trim de whitespace en
  `walk_parse`/`walk_body`). Si agregás una superficie nueva donde un path de git
  se compara contra uno escrito a mano, hacela pasar por esas dos: cada byte
  invisible que se cuela produce el mismo síntoma — el mismo archivo listado a los
  dos lados del error de drift, o la entrada desapareciendo del orden de lectura
  en silencio. Un walkthrough roto/stale nunca
  falla una review: degrada a whole con nota.
- **Borrador del revisor** (`git review walkthrough draft`): el otro lado del
  walkthrough. Cuando el PR no trae uno, el revisor se escribe el suyo en
  `<gitdir>/review-walkthrough/<src>.md` — **fuera del árbol versionado**, así
  que no se commitea, no se stagea y `git status` no cambia en ningún momento.
  Mismo formato que el sidecar y misma validación (`draft --build` reusa el
  cuerpo de `build`, sin duplicar una sola regla). La precedencia se resuelve en
  un único punto, `walk_read`: si hay borrador para el `<src>` del contexto
  —fijado por `walk_use_draft` desde los dos cargadores de metadata, de modo que
  todo verbo con review activa lo herede—, gana sobre el sidecar del tip; si no,
  el sidecar como siempre. Las trece funciones de walk y los verbos que cuelgan
  de ellas no se enteran. **Qué borrador lee una review se persiste**
  (`branch.review/<x>.reviewwalkdraft = <rama del borrador>`, escrita por
  `start`/`compare` sólo cuando abren sobre uno): no siempre es el `reviewsource`
  —un `compare develop origin/feature/x` es la review de `origin/feature/x` y lee
  el borrador de `feature/x`— y sin ese registro cada verbo posterior buscaría
  bajo el nombre de la review, no encontraría nada y se pasaría al orden del autor
  en silencio. Es también lo que le permite a `walk_range_error` distinguir
  «borraste tu borrador» de «commiteaste encima de la review» cuando la secuencia
  cambia bajo el cursor, incluso si el PR trae walkthrough propio y la review cae
  sobre él. Es una clave walk como las demás: la copian `save`/`continue` y la
  cubre el guard de metadata de `finish`.
  Ciclo de vida: `save` lo archiva en `review-saved-walkthrough/` (y `continue` lo
  devuelve) **como último paso, después de la última guarda que puede abortar** —
  un movimiento a mitad de camino dejaba el archivo sin dueño de los dos lados.
  `clean` **no lo toca nunca**: es prosa escrita a mano que sobrevive a la review
  (arrancá la rama de nuevo y tu orden sigue ahí), así que va con los otros dos
  estados persistentes que `clean` deja quietos —los marcadores de `--delta` y las
  reviews guardadas— y se descarta con `git review forget --draft <rama> | --all`
  (`--saved` se lleva el de la review pausada). Su presencia se reporta —nunca se
  infiere— con el registro `draft` de `status --porcelain` y el sufijo `(draft)`
  en `status` y `list`; la viabilidad de armarlo o continuarlo, con las ofertas
  `draft` / `draft-resume` de `config --porcelain`, que se deciden con un test de
  archivo (cero procesos nuevos en un camino caliente: el gitdir del que cuelgan
  todos esos paths se resuelve **una vez por proceso** en `walk_gitdir_init`, y
  desde `walk_use_draft` porque un `$(...)` no puede cachear nada).
- **Refs de ediciones:** `refs/review-edits/<src>/<step>` bancan las ediciones
  de cada commit en `--step` como objetos commit-tree; `git review save` los mueve
  a `refs/review-saved-edits/` para que `git review clean` (que poda
  `refs/review-edits/`) nunca toque un review guardado.
- **Marcadores `--delta`:** las claves de config `reviewworkflow.<src>.reviewed`
  registran el último tip revisado. Una review **completada** (finish con
  `reviewundoouthead`) los conserva a través de `git review clean`; un start
  abandonado (clean/abort sin finish exitoso) los revierte como abort. Para
  borrarlos a mano: `git review forget --delta`.
- **Entradas de config:** `reviewworkflow.base` (dónde se integran los PRs — sin
  default, un review completo falla sin él) y `reviewworkflow.remote` (default
  `origin`). Ambas son claves `git config` por repo, por diseño.

## Convenciones

- **Espejar los idioms de git.** Es el principio rector del proyecto: preferir
  diseños consistentes con git nativo (omitir el arg para la rama actual, `--`
  para terminar el parseo de opciones, riesgo asimétrico en los verbos
  destructivos) antes que inventar comandos nuevos.
- **Hay DOS README y siempre se actualizan los dos.** `README.md` (inglés) y
  `README.es.md` (español) son traducciones espejo. Cualquier cambio de
  comportamiento (flags, superficie de comandos, tabla de verbos, ejemplos)
  tiene que reflejarse en *ambos* en el mismo cambio — nunca tocar solo uno.
- **La landing (`docs/index.html`) es pitch, no documentación.** Es la página de
  GitHub Pages. A propósito **no** documenta flags ni la tabla de verbos: para eso
  linkea a los README, así no hay una tercera superficie de docs que mantener
  sincronizada. Pero sí duplica cuatro cosas puntuales, y solo esas hay que
  revisarlas cuando el cambio las toca:
    1. la **tabla comparativa** (la de la landing es un recorte de 4 filas de la
       de los README);
    2. los **métodos de instalación** (npm / Homebrew / PowerShell / one-liner);
    3. los **comandos que aparecen en los ejemplos** — `start`, `next`, `finish`,
       `walkthrough init|build`, `reviewworkflow.base`;
    4. el **formato del walkthrough** que muestra el demo interactivo (el
       `## Heads-up`, `## N. <path>` + el *why*, y el badge `key`).

  Si tu cambio no toca nada de eso, la landing no se toca.
- **La landing es bilingüe en un solo archivo.** El inglés vive en el HTML (para
  que lo indexen los crawlers) y el español en el diccionario `ES` del `<script>`,
  emparejados por `data-i18n`. Si editás un texto con `data-i18n`, editá las dos
  puntas — igual que con los README. La vista mobile del cuadro comparativo se
  **genera desde la propia `<table>`** en JS, así que agregar una fila o una
  columna a la tabla ya se propaga sola: no la dupliques a mano.
- **Ante una duda genuina, preguntá.** Si hay una decisión de diseño o una
  ambigüedad real que no se resuelve leyendo el código, preguntarle al usuario
  suele ser más certero y económico que explorar a ciegas o adivinar y rehacer.
- **Los documentos de trabajo se escriben en español.** Todo lo que se redacte
  para este repo —specs, planes, checklists, análisis, notas de diseño— va en
  español, con la ortografía completa (acentos, `ñ`, `¿`/`¡`). Cuando se parte de
  una plantilla en inglés (p. ej. las de `.specify/templates/`), la plantilla
  **se deja como está** y sólo se escribe en español lo que uno completa: los
  encabezados y comentarios en inglés se conservan verbatim, porque los comandos
  de Spec Kit localizan las secciones por su nombre y traducirlos los rompe. Esto
  no aplica al *producto*: el código, los mensajes de los comandos, `README.md` y
  los nombres de los `@test` siguen sus propias reglas (ver los dos README y la
  regla de nombres ASCII más abajo).
- **Solo shell POSIX (`sh`)**, con `set -eu` arriba de cada script. Nada de
  bashisms — los comandos deben correr bajo `dash`/Git Bash. El repo también
  trae *instaladores* de PowerShell (`web-install.ps1`) y un paquete npm, pero
  los comandos en sí son POSIX.
- **`sed` multiplataforma:** GNU y BSD difieren en `-i`; hacé las ediciones
  in-place a través de un archivo temporal (ver `sed_i` en `bump-version.sh`).
- **Nada de `A && B || C` como if-then-else.** shellcheck lo marca con SC2015
  (falla en Ubuntu y Windows en CI) porque `C` también corre si `B` falla, no
  solo si `A` es falso. Para guardas de validación usá un `if` explícito con la
  condición invertida: `if [ $# -eq 0 ] || [ -z "$1" ]; then die "..."; fi` en
  vez de `[ $# -gt 0 ] && [ -n "$1" ] || die "..."`. El idiom `A || C` a secas
  (sin `&&`) sí está permitido — no dispara SC2015.
- **Tests con asserts fuertes, sin falsos positivos.** Cada `@test` de bats debe
  fallar de verdad cuando el comportamiento se rompe. En concreto:
    - Afirmá el `status` esperado *además* de la salida (`[ "$status" -eq 0 ]` /
      el código de error que corresponda). Nunca dejes pasar un test solo porque
      el comando no abortó.
    - Para verificar contenido preferí igualdad o aserciones específicas
      (`[ "$output" = "..." ]`) antes que `grep`/globs laxos que matchean de más;
      si usás `[[ "$output" == *"x"* ]]`, que el patrón sea único y significativo.
    - Verificá el **efecto real** sobre el estado de git (ramas/refs/config/working
      tree), no solo el texto impreso.
    - Para los casos de error, afirmá el exit code *y* el mensaje en `stderr`, y
      confirmá que el efecto colateral NO ocurrió.
    - Nada de tests tautológicos (que pasan pase lo que pase) ni asserts comentados.
    - **Nombres de `@test` en ASCII puro.** Nada de em dashes (`—`), acentos ni
      otros caracteres no-ASCII en el texto del nombre. bats convierte cada nombre
      en un nombre de función shell escapando byte por byte, y el bats de Windows
      en CI trastabilla con los bytes UTF-8 → `unknown test name '...\342-80-94...'`
      (pasa en Linux/macOS, rompe en Windows). El cuerpo del test puede tener lo
      que sea; es solo el nombre el que se vuelve nombre de función.
      `tests/test-names.bats` lo verifica sobre toda la suite, así que la regla
      se rompe en cualquier OS en un segundo y no recién en el runner de Windows.

## Clientes del monorepo (VS Code + IntelliJ)

La CLI es la única fuente de verdad. Hay dos UIs de cliente en el monorepo:

- **`vscode-extension/`** — extensión VS Code (TypeScript + esbuild).
- **`intellij-plugin/`** — plugin IntelliJ IDEA (Kotlin + Gradle Platform Plugin).

Ambos leen solo porcelain/argv de la CLI; el canónico anti-drift multi-cliente
vive en **`contracts/client-product-surface.yaml`** (raíz). Incluye la matriz de
27 acciones y el bloque **`panel_layout:`** (disposición del panel por
situación). CI lo verifica con `node scripts/check-client-product-surface.mjs`
(min_cli_version, npm, strings críticos, 27 acciones vs `package.json` de la
extensión, y las seis comprobaciones de layout vs `panelHtml.ts`). Del lado
IntelliJ, `PanelLayoutContractTest` compara `panelLayout(fixture)` contra el
mismo YAML en cada `./gradlew test`.

### Plugin de IntelliJ IDEA

`intellij-plugin/` es un módulo Gradle aparte (JDK 21; pin de platform en
`intellij-plugin/gradle.properties` — **única** fuente de since-build/versión).
Dominio puro en `com.ezevillo.gitreview.domain` (sin `com.intellij`); host/UI
invocan la CLI con `GeneralCommandLine` UTF-8.

```sh
# Desde intellij-plugin/ (el wrapper Gradle vive ahí, no en la raíz del monorepo):
./gradlew test              # unit domain (ubuntu/macos/windows en CI)
./gradlew platformTest      # headless (Linux CI; harness T030a)
./gradlew runIde            # sandbox IDE (equivalente a F5 de la extensión)
./gradlew runPanelPreview   # preview Swing del PanelModel
./gradlew buildPlugin       # zip
./gradlew verifyPlugin
```

Shell: en Git Bash / POSIX usá `./gradlew`; en PowerShell `.\gradlew.bat`
(no mezclar: en MINGW64 `.\gradlew.bat` falla con `command not found`).

**Prueba manual (como la extensión):** `./tests/sandbox.sh` →
`git -C <sandbox>/work review start feature/checkout` → `./gradlew runIde` →
abrir solo `<sandbox>/work` → setting **Tools → git review → Path to
git-review** al `bin/git-review` del checkout si hace falta → tool window
**git review** + menú **Tools → git review**. Detalle en `CONTRIBUTING.md`
(sección *The IntelliJ IDEA plugin*) y `specs/009-plugin-intellij/quickstart.md`.

**UX:** paridad de producto (CLI + matriz de acciones/situaciones + disposición
del panel), no de píxeles. El panel es Swing nativo a propósito (no CEF/HTML del
webview de VS Code): `domain/PanelLayout.kt` proyecta el modelo y
`ui/PanelRenderer.kt` lo dibuja. Comparar lado a lado con
`./gradlew runPanelPreview` vs `npm run preview` en la extensión. La extensión y
la CLI siguen yendo al contenedor Docker en Windows; el plugin se prueba con
Gradle nativo (y `platformTest` en el runner Linux de CI).

## Extensión de VS Code

`vscode-extension/` es un proyecto npm aparte (TypeScript + esbuild), con su
propio job en CI. Nunca deriva estado por su cuenta: todo lo que muestra sale de
reinvocar `git review status --porcelain` / `--why` sobre la CLI del `PATH`, así
que hay que tener este checkout instalado (`./install.sh`) para **correrla** en
un editor de verdad. Los tests no: `runTests.ts` pone el `bin/` del checkout al
frente del PATH que hereda el host, así que el fixture y la extensión bajo test
corren siempre la CLI de este árbol. El diseño completo está en `specs/002-extension-vscode/`
(`contracts/cli-invocation.md` es la lista cerrada de lo que puede invocar). Su
`README.md` es único y va en **inglés** (es producto, no documento de trabajo):
la regla de los dos README es de los README de la raíz, no de éste.

Ese `README.md` y el `CHANGELOG.md` de al lado **viajan dentro del `.vsix`**: son
las pestañas *Details* y *Changelog* del listado del Marketplace, así que están
escritos para quien instala la extensión, no para quien la desarrolla — eso vive
en `vscode-extension/CONTRIBUTING.md` (excluido del paquete por `.vscodeignore`,
junto con `src/`, `test/` y `preview/`). Dos cosas que se rompen fácil ahí: los
**links tienen que ser absolutos**, porque `vsce` reescribe los relativos contra
la raíz del repo ignorando el `repository.directory` del `package.json` (un
`../README.md` termina como `.../blob/HEAD/../README.md`, roto), y la superficie
que el README describe —acciones del panel, settings, versión mínima de la CLI—
tiene que seguir a `contributes` del `package.json`.

```sh
cd vscode-extension
npm install
npm run watch             # esbuild, recompila dist/ al guardar

npm run test:unit         # funciones puras, sin editor, milisegundos

npm run preview           # render del panel en el navegador (ver abajo)
npm run preview:watch

# Integración: en el contenedor, NO con `npm run test:integration`.
cd ..
./vscode-extension/test/run-docker.sh             # los 70 tests
./vscode-extension/test/run-docker.sh open-entry  # las specs que matcheen
MOCHA_GREP='abre el diff' ./vscode-extension/test/run-docker.sh
./vscode-extension/test/run-docker.sh -- sh       # una shell adentro
```

- **Editor de pruebas:** abrir `vscode-extension/` en VS Code y F5 (config *Run
  Extension* de `.vscode/launch.json`) levanta un **Extension Development Host**
  con la extensión cargada desde el checkout; los cambios entran con *Developer:
  Reload Window* en esa ventana, no reiniciándola. El panel sólo tiene algo que
  mostrar dentro de un repo con review activo: armá uno con `./tests/sandbox.sh`,
  arrancá el review (`git -C <sandbox>/work review start feature/checkout` entra
  en walk, porque el sandbox commitea un walkthrough) y abrí `<sandbox>/work` en
  el host. Ojo: el host hereda el `PATH` del VS Code que lo lanzó, no el que
  arma el `env.sh` del sandbox — o instalás el checkout, o apuntás la setting
  `gitReview.path` a `bin/git-review`.
- **La suite de integración va en el contenedor**, misma regla que bats: los 70
  tests tardan 38 s adentro contra 16 minutos nativos en Windows (26×), y pasan
  los mismos 70. El script
  (`vscode-extension/test/run-docker.sh` + `test/Dockerfile` + `entrypoint.sh`)
  monta el repo read-only, lo copia a `/work` porque `npm install` escribe, y
  cachea `node_modules`, el VS Code descargado y el cache de npm en volúmenes
  nombrados (`grv-vscode-*`) — sólo la primera corrida los paga. Tres cosas de
  ahí adentro que no son obvias: corre como el usuario `node` y no como root,
  porque Electron se niega a arrancar como root sin `--no-sandbox` y ese flag
  saldría de `runTests.ts`, o sea del árbol; hace `chmod +x` sobre `bin/`,
  porque el bind mount desde Windows puede aplanar el bit ejecutable y sin él
  todo fixture muere con un `is not a git command` que no dice nada; y la imagen
  fija **`VSCODE_CLI=1`**, sin lo cual VS Code resuelve el entorno de un login
  shell y pisa con él el `PATH` que `runTests.ts` preparó — la extensión no
  encuentra la CLI y los 70 tests fallan con `cli-missing`.
- **`test:integration` corre contra `dist/`** y lo recompila solo
  (`pretest:integration`), así que lo verde siempre es el código actual.
- **Dos specs de integración abren tabs y son flaky en Windows** por el host de
  test, no por la extensión. Correr en el contenedor las saca del medio; si aun
  así ves un `no se abrió ningún tab` en el runner de Windows, medí el baseline
  en un checkout sin tocar antes de buscar la causa en tu cambio.
- **El `--user-data-dir` del host va a un temp corto, no al default de
  test-electron** (`test/integration/helpers/userDataDir.ts`). VS Code arma el
  socket IPC de su main como `<user-data-dir>/<version>-main.sock`, y en POSIX
  ese path no puede pasar de `sun_path` (103 chars en macOS, 107 en Linux): con
  el default `<extensionRoot>/.vscode-test/user-data`, el checkout del runner de
  GitHub —que repite el nombre del repo— se iba a 113 y el editor moría con
  `EINVAL` antes de correr un test. Fallaba sólo en macOS, pero no por margen:
  el mismo path mide 112 en Linux y ubuntu zafa porque VS Code prefiere
  `XDG_RUNTIME_DIR` cuando existe (Windows usa named pipes, sin límite). O sea
  que un contenedor Linux sin esa variable y con el checkout en un path largo
  reproduce el fallo de macOS. Si tocás esos args, el flag tiene que ir como
  `--user-data-dir=<dir>`: con un espacio, `hasArg` de test-electron no lo ve y
  reinyecta el default largo. `test/unit/userDataDir.spec.ts` cubre las dos
  cosas contra `darwin` explícito, así que la regresión cae en cualquier SO.
- **`npm run preview`** genera `out/preview/index.html` (y lo imprime como URL
  `file://`): los dieciocho estados del panel lado a lado, a ancho de sidebar, con
  selector de tema dark/light/alto contraste. El pane es el `panelHtml()` real y
  los estados de `preview/fixtures.ts` son salida `--porcelain` de ejemplo pasada
  por el parser y el modelo reales, así que **sigue al código y no se mantiene
  aparte**. Lo que no puede afirmar: los botones no tienen extensión del otro
  lado; las variables de tema de `preview/build.ts` son una aproximación — si
  el panel empieza a usar una `--vscode-*` que no está en esa lista, agregarla es
  parte del cambio; y el pane `loading` es ese estado congelado — su
  temporización (el umbral antes del esqueleto, el techo de un `--why` lento)
  sólo ocurre navegando. Para comportamiento, F5.

## Landing (GitHub Pages)

`docs/index.html` se publica en GitHub Pages desde la rama `main`, carpeta
`/docs` (Settings → Pages → *Deploy from a branch*). **No hay build ni
workflow**: es un HTML estático autocontenido, así que cada push a `main` que
toque `docs/` lo republica solo en un par de minutos. Para previsualizarlo,
abrilo directo en el navegador — no necesita servidor.

- `docs/.nojekyll` evita que Pages lo pase por Jekyll.
- `docs/og.png` es la preview de los links (copia de `trailer-poster.png`);
  las URLs de `og:image` y `canonical` están hardcodeadas a
  `ezevillo.github.io/git-review-workflow/` — si algún día se le pone dominio
  propio, hay que tocar esas líneas del `<head>` (y agregar un `docs/CNAME`).
- `docs/` **no** está en `files` de `package.json`, así que no viaja en el
  tarball de npm ni infla el paquete.

## Release

La versión está duplicada a propósito: `VERSION`, `bin/git-review` y
`package.json` viajan dentro del tarball (npm publica la versión de
`package.json`); `Formula/git-review-workflow.rb` apunta al tarball.
`./bump-version.sh X.Y.Z` estampa los tres desde un solo argumento (deja a
propósito el `sha256` de la fórmula —desconocido hasta que existe el tarball del
tag; el workflow de release lo fija). Los releases se cortan pusheando un tag
`v*`: el workflow crea el GitHub Release, fija la fórmula y publica a npm vía
Trusted Publishing (OIDC, sin `NPM_TOKEN`: el repo está registrado como trusted
publisher en npmjs.com). Un `tests/version-consistency.bats` protege contra el
drift.
