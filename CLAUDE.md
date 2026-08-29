# CLAUDE.md

## Qué es esto

Una suite de verbos de `git review` (shell POSIX) para revisar un pull request **editándolo y
ejecutándolo**. Todo cuelga del dispatcher `git review <verbo>`, al estilo de `git bisect`/
`git stash`. `git review start` materializa el diff completo del PR como cambios *staged y sin
commitear* sobre una rama `review/<branch>` cuyo `HEAD` queda en el merge-base; editás/ejecutás en
tu working tree y después `git review finish` extrae *tus* ediciones a una rama aparte
`review-fixes/<branch>`. Ver `README.md` para la superficie completa de comandos.

## Dónde está cada cosa

| Documento | Qué contesta |
|---|---|
| `CLAUDE.md` (este) | Las reglas vinculantes y el mapa del estado. Lo mínimo para no romper nada. |
| `CONTRIBUTING.md` (raíz + uno por cliente) | Cómo construir, correr, testear y empaquetar cada pieza. |
| `decisiones.md` | Por qué cada cosa es como es: el bug que la motivó, la alternativa descartada. |
| Comentarios del código | El rationale por función. `bin/git-review-lib.sh` es 50% comentario. |
| `contracts/client-product-surface.yaml` | El canónico anti-drift de los tres clientes. |
| `README.md` / `README.es.md` | El producto, para quien lo usa. |

**Ante una duda genuina, preguntá.** Si hay una decisión de diseño o una ambigüedad real que no se
resuelve leyendo el código, preguntarle al usuario suele ser más certero y económico que explorar a
ciegas o adivinar y rehacer.

## Comandos

**Todo lo que se puede correr en el contenedor se corre en el contenedor.** No es preferencia: en
Windows crear un proceso cuesta ~50 ms contra ~1 ms en Linux y las dos suites son básicamente
procesos, así que la misma spec mide 15,0 s nativa contra 0,69 s adentro (~22×). CI igual corre todo
en runners reales de ubuntu, macos y windows: el contenedor no saltea nada. Ver `decisiones.md` §1.

```sh
./lint-docker.sh                      # shellcheck: los archivos que lintea CI
./lint-docker.sh algun-script.sh      # uno solo, mientras iterás

./tests/run-docker.sh                 # bats: toda la suite
./tests/run-docker.sh review.bats     # un archivo (o cualquier arg/path de bats)

./vscode-extension/test/run-docker.sh             # integración de la extensión
./vscode-extension/test/run-docker.sh open-entry  # las specs que matcheen

./tests/sandbox.sh        # PR de juguete para probar --step y walk a mano
./tests/sandbox-min.sh    # el hermano vacío: sin walkthrough ni reviewworkflow.base,
                          # la única forma de ver la pantalla de setup del panel
```

Los tests del instalador de PowerShell (`*-ps1.bats`) necesitan `pwsh`, que no está en el
contenedor: solo corren de verdad en CI / en Windows local.

Gradle (JetBrains), `dotnet`/`build-vsix.ps1` (Visual Studio) y npm (VS Code) van en el
`CONTRIBUTING.md` de cada cliente.

## Arquitectura

- **`bin/git-review`** — el dispatcher, el **único** ejecutable que va al `PATH` (`git` lo descubre
  como `git review`). Resuelve su ubicación real siguiendo symlinks, exporta
  `GIT_REVIEW_LIBEXEC=<su dir>`, hace `shift` y `exec`utea `git-review-verbs/<verbo>`. `-h`/sin args
  lista los verbos; `--version`/`-V` imprime la versión. Un verbo inexistente da `error:` a stderr
  (exit ≠ 0).
- **`bin/git-review-verbs/*`** — un ejecutable de shell POSIX por verbo (sin extensión; `chmod +x`),
  `prog="git review <verbo>"`. Son **privados**: no van al `PATH` ni se llaman `git-*`, así que
  `git` no los descubre como `git <verbo>`; el único punto de entrada es el dispatcher.
- **`bin/git-review-lib.sh`** — se *sourcea, nunca se ejecuta*, vía
  `"${GIT_REVIEW_LIBEXEC:?}/git-review-lib.sh"`. Solo define funciones, así que sourcearlo no tiene
  efectos secundarios. Es **libexec**: vive junto al dispatcher, nunca en el `PATH`.

### Modelo de estado — dónde vive el estado del review

Las sesiones son stateful y guardan todo en los datos de git del repo, **nunca en archivos del
working tree**. El detalle de cada pieza está en `decisiones.md` §2-§8; esto es el mapa.

**Ramas**

| Ref | Qué es |
|---|---|
| `review/<branch>` | Review activo |
| `review-fixes/<branch>` | Ediciones extraídas por `finish` |
| `review-saved/<branch>` | Review pausado por `save` |

**Config por rama** (`branch.review/<x>.review*`) — se leen **defensivamente** (`|| true`): con
`set -eu` una clave borrada a mano abortaría el script en silencio.

| Clave | Modo | Qué lleva |
|---|---|---|
| `reviewmode`, `reviewsource`, `reviewtip` | todos | Modo y origen de la review |
| `reviewstart`, `reviewcount`, `reviewstep` | `step` | Posición del cursor de commits |
| `reviewwalkstep`, `reviewwalkcount`, `reviewwalkbase` | `walk` | Cursor de lectura (1-based), guard y lower bound |
| `reviewwalkfromdraft` | `walk` | El orden caminado salió del borrador del revisor |
| `reviewdraft` | **todos** | Bajo qué nombre vive el borrador de esta review |

El guard de metadata de `finish` **aborta si hay claves de step sin `reviewmode=step`**, y hay un
guard espejo para las de walk. Por eso las claves de walk son propias y nunca se reusan las de step.
`reviewdraft` es la excepción deliberada al guard: existe en todos los modos.

**Otros refs y claves**

- **Refs de ediciones:** `refs/review-edits/<src>/<step>` bancan las ediciones de cada commit en
  `--step` como objetos commit-tree; `save` los mueve a `refs/review-saved-edits/` para que `clean`
  (que poda `refs/review-edits/`) nunca toque un review guardado.
- **Marcadores `--delta`:** `reviewworkflow.<src>.reviewed` registra el último tip revisado. Una
  review **completada** los conserva a través de `clean`; un start abandonado los revierte. Se
  borran a mano con `git review forget --delta`.
- **Entradas de config:** `reviewworkflow.base` (dónde se integran los PRs — **sin default**, un
  review completo falla sin él), `reviewworkflow.remote` (default `origin`) y
  `reviewworkflow.advice` (default **encendido**; ver *Advice* abajo). Las tres son claves
  `git config` por repo, por diseño.

**Archivos de prosa** — dos son del **autor** y van trackeados al PR; los tres del **revisor** viven
en el gitdir, así que no se commitean, no se stagean, `git status` no cambia en ningún momento y
`finish` no se los puede llevar a `review-fixes/`:

| Archivo | Dónde | Qué es |
|---|---|---|
| `.review/walkthrough.md` | trackeado | El walkthrough del autor |
| `.review/walkthrough-guide.md` | trackeado | La guía de autoría **compartida** |
| `<gitdir>/review-walkthrough/<src>.md` | gitdir | El **borrador del revisor** |
| `<gitdir>/review-saved-walkthrough/<src>.md` | gitdir | El borrador archivado por `save` |
| `<git-common-dir>/review-walkthrough-guide.md` | gitdir | La guía de autoría **propia** |

**Registros porcelain** — `config --porcelain` emite `draft`, `guide` y `walkthrough`;
`status --porcelain` emite `draft` de presencia; `list --porcelain` emite `branch-draft`. Las guías
y el walkthrough se emiten **siempre**, exista o no el archivo: la ausencia se reporta, no se
implica con el silencio. Los `draft` solo cuando hay. Detalle en `decisiones.md` §8.

## Reglas duras

### Shell

- **Solo shell POSIX (`sh`)**, con `set -eu` arriba de cada script. Nada de bashisms — los comandos
  deben correr bajo `dash`/Git Bash. Los instaladores de PowerShell y el paquete npm son la
  excepción; los verbos en sí son POSIX.
- **Nada de `A && B || C` como if-then-else.** shellcheck lo marca con SC2015 (falla en Ubuntu y
  Windows en CI) porque `C` también corre si `B` falla, no solo si `A` es falso. Usá un `if`
  explícito con la condición invertida. El idiom `A || C` a secas sí está permitido.
- **`sed` multiplataforma:** GNU y BSD difieren en `-i`; hacé las ediciones in-place a través de un
  archivo temporal (ver `sed_i` en `bump-version.sh`).
- **Espejar los idioms de git.** Principio rector: preferir diseños consistentes con git nativo
  (omitir el arg para la rama actual, `--` para terminar el parseo, riesgo asimétrico en los verbos
  destructivos) antes que inventar comandos nuevos.

### La copy de los paneles

Detalle y el porqué de cada una en `decisiones.md` §15. Vale para los tres clientes; **no** para la
CLI, cuyo público eligió la terminal y donde el vocabulario de git es el correcto.

- **El próximo paso se dice sólo si está FUERA del panel.** Si es un botón que ya está en pantalla,
  el botón *es* el texto. Nombrar en prosa un comando que un control de al lado corre está
  prohibido: es lo que hacía el banner de cierre con `finish --abort` y `clean --keep-fixes`.
- **Tres capas, y el mecanismo nunca en la primera.** Etiqueta (1-3 palabras) → contexto (una
  oración, sólo si el resultado no es obvio o no tiene vuelta atrás) → detalle técnico (el comando,
  el stderr, la ruta) siempre a un clic. **Un tooltip no es un lugar para un argv:** dice qué le
  pasa al objeto de su fila, en imperativo.
- **Se confirma lo que no se puede deshacer, y nada más.** Un cartel que aparece siempre deja de
  leerse, y entonces tampoco se lee el que importa. `startReview` no confirma a propósito, y vale
  para los DOS caminos que llegan al start: el asistente y *Validate and start*.
  **CUIDADO: hoy esto no tiene gate.** `confirms:` del canónico no gobierna en ninguno de los tres
  —en JetBrains se consulta en un `if` de cuerpo vacío, en Visual Studio en un `default:` no-op, y
  en VS Code no existe la tabla—, así que `ConfirmationContractTest` /
  `ConfirmationContractTests` comparan una constante contra el YAML que nadie lee para decidir. El
  diálogo real vive esparcido en cada acción. Ver `decisiones.md` §15.2.
- **Lo que el panel muestra no se notifica.** Toda mutación refresca el panel antes de hablar, así
  que en el camino feliz el acuse ya está en pantalla y el toast lo repite. No notifican: crear un
  borrador (deja su fila), `walkthrough build` (deja el badge al día y abre el archivo) ni un
  `finish` que quedó `pending` (deja su banner). Sí notifican los que el panel no puede contestar:
  un `update` de borrador (los tres números del registro `merged`), copiar al portapapeles, y el residual de
  `finish` sin banner. **Cuál de los dos es se decide por lo que se pidió, nunca leyendo la salida
  de la CLI** — de ahí el `update` en `DraftFlowState.Create` y el retorno nullable de
  `finishSuccess`.
- **Advice: en verde, un cliente no reenvía las notas que ya tiene.** La CLI las apaga en el origen
  —los tres invocadores exportan `GIT_REVIEW_ADVICE=0`, un lugar por cliente— porque distinguirlas
  del lado del panel sería parsear salida humana. **Advice es una pregunta, no una lista:** ¿quien
  invoca ya tiene esto? Sí de dos formas —ofrece un comando o un flag (tiene el botón), o es estado
  que ya viaja como registro porcelain (tiene la fila)—. Todo lo demás se imprime igual: una entrada
  que el PR ya no cambia, un cursor que se movió, una rama que difiere de la local. La línea es esa,
  **no** cuán larga es la nota. Una nota mixta conserva su estado y pierde su oferta
  (`advice_suffix`). Gate: `tests/advice.bats`, que prueba las dos mitades. Detalle en
  `decisiones.md` §15.2.
- **El `stdout` de un verbo no se reenvía tal cual.** Termina en el comando del paso siguiente
  («…then run `git review walkthrough draft --build`»), que en el panel es un botón. Las notas de
  `stderr` sí, cuando el panel no las cubre.
- **Un solo aviso de estado obsoleto** (`STALE` / `Stale`), sin nombrar el verbo que no corrió: ese
  verbo es el botón que el revisor acaba de apretar. Especializarlo otra vez rompe su test.
- **Los fallbacks de error dicen qué no pasó, no qué comando falló.** Sólo aparecen cuando la CLI
  muere *sin* stderr; con stderr no se toca nada (FR-024).
- **Un nombre por concepto y ninguno prestado de git.** `broken`, `details are gone`, `not covered`,
  `saved edits`, `last review point`; un solo verbo para borrar (`Delete`). *Walkthrough* (el
  archivo del autor) y *reading order* (el del revisor) sí son dos cosas distintas.
- **Todo texto va al `UserCopy` de su cliente**, nunca embebido en un comando: `userCopy.ts`,
  `UserCopy.kt`, `UserCopy.cs`. Lo compartido se declara en `contracts/client-product-surface.yaml`,
  y **todo `tooltip*:` que se declare ahí lo exige CI en los tres paneles**.

### Walk y walkthrough

- **Toda comparación de paths entre el walkthrough y git pasa por dos puntos únicos de
  normalización, y solo por ahí:** `walk_normalize` (bytes del sidecar — CR final y BOM UTF-8) y
  `changed_paths` (lado git — `core.quotePath=false`, más el trim de whitespace en
  `walk_parse`/`walk_body`). Si agregás una superficie nueva donde un path de git se compara contra
  uno escrito a mano, hacela pasar por esas dos: cada byte invisible que se cuela produce el mismo
  síntoma — el mismo archivo a los dos lados del error de drift, o la entrada desapareciendo del
  orden de lectura en silencio.
- **Un walkthrough roto o stale nunca falla una review:** degrada a whole con nota.
- **La precedencia borrador/sidecar se resuelve en un único punto, `walk_read`.** El borrador en
  vigor no se lee nunca de la config: es el que el cargador dejó en `walk_draft_src`.
- **«En vigor» y «el archivo existe» son dos preguntas distintas** y hay una función para cada una:
  `walk_draft_body` (vacío o puro whitespace = ausente) y `walk_has_draft_file` (custodia).
  Mezclarlas hace que `status` mienta o que `forget` se lleve un archivo que nadie listó.
- **Dos prohibiciones duras en el bloque de instrucciones, las dos medidas:** nunca
  `<lower>..<tip>` como un solo argumento (en Windows con cwd profundo `git diff` hace `stat()` del
  argumento y muere con `Filename too long`) y nunca `git log` / `rev-list` / `shortlog` /
  `range-diff` (con un `lower` de tipo tree imprimen la historia entera del repo con exit 0, en
  silencio).
- **Las guías de autoría usan `--git-common-dir`, nunca `--git-dir`:** un worktree enlazado comparte
  la común, y una guía es del repositorio y no del worktree donde estás parado. La guía propia va
  **plana**, fuera de `review-walkthrough/`, o `walk_draft_list` la tomaría como un borrador
  fantasma.
- **La CLI detecta y apunta; no crea contenido, no valida, no interpreta.** `walkthrough guide` crea
  el archivo **vacío** a propósito.

### Tests

Cada `@test` de bats debe fallar de verdad cuando el comportamiento se rompe:

- Afirmá el `status` esperado *además* de la salida. Nunca dejes pasar un test solo porque el
  comando no abortó.
- Preferí igualdad o aserciones específicas antes que `grep`/globs laxos; si usás
  `[[ "$output" == *"x"* ]]`, que el patrón sea único y significativo.
- Verificá el **efecto real** sobre el estado de git (ramas/refs/config/working tree), no solo el
  texto impreso.
- Para los casos de error, afirmá el exit code *y* el mensaje en `stderr`, y confirmá que el efecto
  colateral NO ocurrió.
- Nada de tests tautológicos ni asserts comentados.
- **Nombres de `@test` en ASCII puro.** Nada de em dashes, acentos ni otros caracteres no-ASCII: bats
  convierte cada nombre en un nombre de función shell escapando byte por byte, y el bats de Windows
  en CI trastabilla con los bytes UTF-8. `tests/test-names.bats` lo verifica sobre toda la suite.
- **bats está pinneado a una única versión** (`bats@1.13.0`) en **cuatro lugares**: los tres runners
  de CI, `release.yml` y `tests/Dockerfile`. Si la subís, subila en los cuatro a la vez.

### Documentación

- **Hay DOS README y siempre se actualizan los dos.** `README.md` (inglés) y `README.es.md`
  (español) son traducciones espejo. Cualquier cambio de comportamiento —flags, superficie de
  comandos, tabla de verbos, ejemplos— tiene que reflejarse en *ambos* en el mismo cambio.
- **Los documentos de trabajo se escriben en español**, con ortografía completa (acentos, `ñ`,
  `¿`/`¡`). Cuando se parte de una plantilla en inglés (p. ej. `.specify/templates/`), la plantilla
  **se deja como está** y solo se escribe en español lo que uno completa: los encabezados en inglés
  se conservan verbatim porque Spec Kit localiza las secciones por su nombre. Esto no aplica al
  *producto*: código, mensajes, los README y los nombres de los `@test` siguen sus propias reglas.
- **El README es producto; el desarrollo va en `CONTRIBUTING.md`.** Vale para la raíz y para los tres
  clientes.

## Clientes del monorepo (VS Code + IntelliJ + Visual Studio)

La CLI es la única fuente de verdad. Los tres leen solo porcelain/argv; ninguno deriva estado por su
cuenta.

- **`vscode-extension/`** — proyecto npm aparte (TypeScript + esbuild). Nunca deriva estado: todo
  sale de reinvocar `git review status --porcelain` / `--why`.
  `specs/002-extension-vscode/contracts/cli-invocation.md` es la **lista cerrada** de lo que puede
  invocar.
- **`jetbrains-plugin/`** — módulo Gradle aparte (JDK 21). El pin de platform en
  `jetbrains-plugin/gradle.properties` es la **única** fuente de since-build/versión: mínimo
  **2026.1** / branch **261**, sin techo de `until-build`. La compatibilidad multi-producto sale de
  `plugin.xml` (`platform` + `Git4Idea`, más `incompatible-with`), no de un enum del Marketplace: un
  zip para IDEA, WebStorm, PhpStorm, PyCharm, GoLand, CLion, RubyMine, RustRover y DataGrip; **no**
  Android Studio ni Rider. Dominio puro en `com.ezevillo.gitreview.domain` (**sin `com.intellij`**);
  host/UI invocan la CLI con `GeneralCommandLine` UTF-8.
- **`visualstudio-extension/`** — solución .NET 8 aparte (`GitReview.sln`), mismo split de capas que
  JetBrains: **`GitReview.Domain`** (C# puro, **sin `Microsoft.VisualStudio.*`**),
  **`GitReview.Host`** (invocador, refresh, lock de mutación) y **`GitReview.VS`** (VSIX — WPF
  `PanelView` con el mismo orden y las mismas etiquetas en inglés; solo los colores siguen el tema
  del host).

El canónico anti-drift vive en **`contracts/client-product-surface.yaml`**: la matriz de **27
acciones**, `panel_layout:`, `guide_rows:`, `draft_controls:`, `fixes_rows:`, `icon_vocabulary:`,
`title_actions:` y `listing:`. CI lo verifica con `node scripts/check-client-product-surface.mjs`:
`min_cli_version`, npm, strings críticos, las 27 acciones vs el `package.json` de la extensión, las
seis comprobaciones de layout vs `panelHtml.ts`, y los mismos escalares contra los archivos de
dominio de `visualstudio-extension/`. Del lado IntelliJ lo ata además `PanelLayoutContractTest` en
cada `./gradlew test`, y del lado Visual Studio `PanelLayoutContractTests` en cada `dotnet test`.

**Las reglas que el contrato hace cumplir:**

- **Un control cuyo sujeto es una FILA no es una acción del producto.** Los de `draft_controls:`,
  `guide_rows.controls:` y `fixes_rows.controls:` viven en mapas propios y **no tocan el conteo de
  27**: no van a `contributes.commands`, ni al menú *Tools → git review*, ni al `.vsct`. Colar uno
  como acción falla CI.
- **El icono de un control lo declara el contrato, no cada cliente.** `icon_vocabulary:` fija los
  cinco nombres (`prev`, `next`, `file`, `trash`, `diff`) y son semánticos, no del trazo. Cada
  cliente contesta desde **un solo mapa**. Un control con `emphasis: icon` y sin `icon:` falla.
- **Una divergencia deliberada se declara en el contrato, no en el cliente.** `not_in: [<cliente>]`
  se verifica en las **dos** direcciones. Hoy hay una sola: `openAllChanges` no existe en Visual
  Studio. Reponerla sin tocar el contrato falla CI, que es lo que se quiere.
- **La paridad es una regla del monorepo, no una promesa al usuario.** Ninguna superficie que le
  llegue a quien instala nombra a los otros dos clientes ni dice «paridad con X». Se cuenta en los
  `CONTRIBUTING.md` y acá.
- **De la ficha de cada tienda se comparte la copy corta, no el cuerpo:** el tagline (byte por byte)
  y los keywords (como conjunto normalizado). El cuerpo no se verifica.

**Invariantes del panel, con gate en los tres:**

- **El pie se queda con el 55% del panel y scrollea adentro; nunca lo recorta.** Sin el tope, el pie
  *es* el panel. Gates: `footer:capped` / `footer:scrolls` en el `--verify` de Visual Studio, el test
  del renderer de JetBrains, y un assert estructural del CSS en la extensión.
- **Una review no tiene pie: ninguna `tools_section`.** Todo lo que cuelga de `walkthrough` es de
  quien está parado en **su** PR, y adentro de una review estás parado en el de otro. Los registros
  ni llegan: son de `config --porcelain`, que adentro de una review no se invoca.
- **El resultado del verbo está en stdout, no en stderr.** Los verbos imprimen su resultado por
  stdout y reservan stderr para errores y notas. Un camino que solo lee stderr en verde se queda sin
  la única frase que contesta qué pasó.

**Reglas propias de cada cliente que no avisan si se rompen:**

- **JetBrains — la VFS se toca en un solo lugar, y nunca desde el EDT.** `host/EditorFiles.kt` es la
  única puerta: `refreshAndFindFileBy*` **crea el nodo y dispara el evento**, o sea muta el modelo de
  la plataforma, que pide el write-intent lock que un `ActionListener` de Swing no tiene. Falla solo
  en runtime; el gate es `VfsAccessTest`.
- **Visual Studio — el VSIX es net472 y lo arma MSBuild, no `dotnet build`.** `-p:GitReviewPackVsix=true`
  agrega net472 al lado de net8.0. Lo que el BCL viejo no tiene se rellena en `src/Compat/`;
  `ProcessCompat` es **el único archivo con `#if` del árbol** — si aparece otra incompatibilidad, va
  un shim ahí, no un `#if` en el dominio. El gate es `./build-vsix.ps1`, que corre en CI solo en
  `windows-latest`.
- **Visual Studio — los botones del panel los dibuja `PanelButtons`, no WPF**, y un trigger de
  `Style` **pierde** contra un valor local: los botones `Primary`/`Secondary` no pueden asignar
  `Background`/`Foreground` en la instancia. Lo mismo un nivel más adentro: el glifo va pegado a la
  etiqueta en un solo string, nunca como contenido compuesto con color propio.
- **VS Code — `panelHtml.ts` es un único template literal**: un backtick suelto, aunque sea en un
  comentario, rompe el build con TS1005.
- **VS Code — los links del README empaquetado tienen que ser absolutos**, porque `vsce` reescribe
  los relativos contra la raíz del repo ignorando `repository.directory`.

## Assets del logo

**`assets/logo.svg` es el maestro** — vector puro, `viewBox="0 0 128 128"` y **sin `width`/`height`**.
Todo lo demás sale del mismo generador, `vscode-extension/media/_build_icon.py`, que en una corrida
escribe los PNG y SVG de la extensión, el maestro, `docs/logo.svg`, los cuatro SVG del plugin de
IntelliJ y los de `visualstudio-extension/`. **Ninguno se edita a mano: se cambia el generador y se
regenera** — los comentarios que le pongas a un SVG los borra la próxima corrida.

`npm run check:logo-assets` (`scripts/check-logo-assets.mjs`, en CI junto al check del contrato
multi-cliente) verifica el contrato entero: el maestro sin tamaño fijo ni raster embebido, su
geometría contra `media/icon.svg`, la copia de `docs/` idéntica al maestro, que la landing la use de
favicon, y los 40×40 / 16×16 que exige JetBrains.

## Landing (GitHub Pages)

`docs/index.html` se publica desde `main`, carpeta `/docs`. **No hay build ni workflow**: es un HTML
estático autocontenido, así que cada push que toque `docs/` lo republica solo.

**Es pitch, no documentación.** A propósito no documenta flags ni la tabla de verbos: para eso
linkea a los README. Pero duplica cuatro cosas, y solo esas hay que revisar cuando el cambio las
toca:

1. la **tabla comparativa** (un recorte de 4 filas de la de los README);
2. los **métodos de instalación** (npm / Homebrew / PowerShell / one-liner);
3. los **comandos de los ejemplos** — `start`, `next`, `finish`, `walkthrough init|build`,
   `reviewworkflow.base`;
4. el **formato del walkthrough** que muestra el demo (el `## Heads-up`, `## N. <path>` + el *why*,
   y el badge `key`).

**Es bilingüe en un solo archivo:** el inglés en el HTML (para los crawlers) y el español en el
diccionario `ES` del `<script>`, emparejados por `data-i18n`. Si editás un texto con `data-i18n`,
editá las dos puntas. La vista mobile del cuadro comparativo se **genera desde la propia `<table>`**:
no la dupliques a mano.

`docs/.nojekyll` evita que Pages lo pase por Jekyll. `docs/logo.svg` y `docs/og.png` son generados
(ver *Assets del logo* y `decisiones.md` §13), nunca a mano. `docs/` no está en `files` de
`package.json`, así que no viaja en el tarball de npm.

## Release

La versión de la **CLI** está duplicada a propósito en `VERSION`, `bin/git-review` y `package.json`
(los tres viajan en el tarball; npm publica la de `package.json`);
`Formula/git-review-workflow.rb` apunta al tarball. `./bump-version.sh X.Y.Z` estampa los tres desde
un solo argumento y deja **a propósito** el `sha256` de la fórmula, desconocido hasta que existe el
tarball del tag: lo fija el workflow de release. Los releases se cortan pusheando un tag `v*`, que
crea el GitHub Release, fija la fórmula y publica a npm vía Trusted Publishing (OIDC, sin
`NPM_TOKEN`).

Los clientes versionan **aparte** de la CLI y entre sí, con el mismo patrón:

| Comando | Qué estampa |
|---|---|
| `./vscode-extension/bump-version.sh X.Y.Z` | `package.json` + las entradas propias de `package-lock.json` |
| `./jetbrains-plugin/bump-version.sh X.Y.Z` | `pluginVersion` en `gradle.properties` |
| `./visualstudio-extension/bump-version.sh X.Y.Z` | `GitReview.VS.csproj`, `source.extension.vsixmanifest` y `Directory.Build.props` |

`tests/version-consistency.bats` protege contra el drift de la CLI y de los tres clientes.

**El CHANGELOG del plugin de JetBrains no es solo documentación: es lo que se publica.** La sección
de la versión que se está sacando se renderiza al `<change-notes>` del descriptor, o sea la pestaña
*What's New* del Marketplace. El heading `## [X.Y.Z]` se escribe a mano **antes** de tagear, o el
release publica notas vacías.

**El plugin tiene su propio namespace de tags y su propio workflow:** un `jetbrains-v*` lo publica al
Marketplace, mientras que `v*` sigue siendo solo la CLI. Su Release de GitHub va con
**`--latest=false`** — los dos `web-install` resuelven `releases/latest` para elegir el ref de la
CLI. Detalle en `decisiones.md` §13.
