# Tasks: Cliente TUI de terminal, cuarto cliente del monorepo

**Input**: Design documents from `/specs/015-cliente-tui/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: sí, y no son opcionales. La spec los pide por requisito (FR-057 a FR-060, FR-070 a FR-075)
y `CLAUDE.md` los pide por regla. Cada tarea que agrega una tabla, una clave del canónico, una lista
o un archivo de referencia **trae el chequeo que la hace fallar cuando driftea**: en este proyecto
una tabla sin gate nace decorativa. Los `@test` de bats van en **ASCII puro**.

**Organization**: las fases son las **capas de entrega** de [research.md](./research.md) § Decisión
20, no una fase por historia. El `[USn]` de cada tarea dice a qué historia sirve, y una capa puede
empujar dos: la capa de lectura, por ejemplo, cierra la mitad de US3 y la mitad de US2 al mismo
tiempo. Cada capa deja la TUI usable en un subconjunto de historias y ninguna se mergea sin sus
tests.

**La Phase 1 va primera y sola, y eso es una restricción, no una preferencia.** Es el único paso que
toca a los **tres clientes ya publicados** —sus dos entradas en el canónico— y las dos migraciones
son *value-preserving*: cambia la forma, no los valores, y ningún archivo de esos tres clientes
cambia un byte. Mezclarla con código nuevo del cuarto cliente haría imposible revisar si un cliente
publicado cambió de comportamiento.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: paralelizable (archivos distintos, sin dependencias pendientes)
- **[Story]**: [US1]…[US8] según [spec.md](./spec.md); las fases de setup, foundational y polish no
  llevan etiqueta
- Rutas absolutas desde la raíz del repo; el árbol del cliente cuelga de `tui/`

## Path Conventions

- Cliente: `tui/` — módulo Go propio (`tui/go.mod`), con `cmd/git-review-ui/`,
  `internal/domain/`, `internal/host/`, `internal/ui/` y `testdata/`
- Verbo: `bin/git-review-verbs/ui` (privado, libexec) — el ejecutable `git-review-ui` va al `PATH`
  porque **no es un verbo**: es un programa aparte que git expone por la convención `git-*` de
  terceros (FR-006)
- Canónico: `contracts/client-product-surface.yaml` + `scripts/check-client-product-surface.mjs`
- Suite de la CLI: `tests/*.bats` (bats `1.13.0`, **los cuatro pines quedan intactos**: el job nuevo
  es Go)

**Nota de alcance**: la TUI **no se publica en ningún registro de paquetes** (FR-049, FR-053). No hay
tareas de npm, ni de altas de publicación, ni de organizaciones en un registro, ni de paquetes por
plataforma. Los únicos artefactos publicados son los **siete binarios** adjuntos al GitHub Release y
la **fórmula de Homebrew** que los apunta.

---

## Phase 1: Setup — la migración del canónico (capa 1)

**Purpose**: darle al canónico la forma que un cuarto cliente necesita, **sin mover un solo valor**.
Es la única fase que toca a los tres clientes publicados, y los toca sólo en su declaración.

**Las ocho tareas entran en UN solo commit.** La forma y su lector viven en el mismo repo y el
verificador lee el YAML de disco en la misma corrida: partirlas es exactamente lo que pone CI roja
en el medio. El diff resultante es YAML + verificador y nada más — si un cliente publicado hubiera
cambiado de comportamiento, se vería.

**No existe todavía ningún archivo bajo `tui/`.** Las entradas del cuarto cliente entran con el
andamio `existsSync(archivo) && …` que ya usaron IntelliJ y Visual Studio, **y cada guarda se borra
en la tarea de fases posteriores que crea el archivo que protege** (T037 instala el chequeo de
cierre que convierte el andamio en error apenas el cliente es real).

- [X] T001 Migrar `min_cli_version` de escalar a **valor por cliente** en
  `contracts/client-product-surface.yaml`: mapa con `vscode`, `intellij`, `visualstudio` y `tui`,
  los cuatro sembrados en `"0.8.0"` (el valor de hoy), con el comentario que declara que **que los
  cuatro difieran no es drift sino el estado esperado** y que ningún gate, presente ni futuro, puede
  exigir que sean iguales (FR-028). En `scripts/check-client-product-surface.mjs`: reemplazar
  `const min = scalar("min_cli_version")` (línea 39) por un helper `minFor(client)` y cablearlo en
  los tres puntos de comparación (líneas ~94 `version.ts`, ~109 `Version.kt`, ~943 `Version.cs`).
  **Gate**: `minFor` falla si el cliente pedido no está declarado —nada de default heredado— y **no
  queda ningún `min` global en scope**, que es lo que hace imposible escribir por accidente una
  comparación entre dos clientes. `vscode-extension/src/cli/version.ts`,
  `jetbrains-plugin/.../domain/Version.kt` y
  `visualstudio-extension/src/GitReview.Domain/Version.cs` **no se tocan**.
- [X] T002 Sacar `multi_root_error` de `strings:` y declararlo como
  `per_client_strings.no_single_root` con los **tres textos actuales copiados verbatim** más la
  entrada `tui` en placeholder, en `contracts/client-product-surface.yaml` (FR-076). En el
  verificador: borrar el literal de JS `const multi = "multi-root is not supported"` (línea 118) y
  reemplazar los tres `includes(multi)` (líneas ~120, ~124, ~957) por `perClientString(name, client)`
  **leído del YAML**, comparando la **oración entera** plegada con el helper `squash` que ya existe.
  **Gate**: el chequeo sube de calidad al migrar —hoy verifica cinco palabras contra un literal de
  JS; después verifica el valor declarado— y una clave `per_client_strings` sin uno de los cuatro
  clientes es `fail`. `state.ts` y los dos `ReviewStateManager` **no se tocan**: FR-076 exige que la
  copy se **declare** por cliente, no que se reescriba.
- [X] T003 Sacar `reload_or_wait` de `strings:` (línea 36) y declararlo como
  `per_client_strings.after_install` con los tres valores de hoy verbatim y `tui` en placeholder, en
  `contracts/client-product-surface.yaml`. El motivo va escrito al lado: el texto promete que el
  panel vuelve a chequear cada pocos segundos, que es **un poll** —FR-032 lo prohíbe hacer y FR-069
  prohíbe **decir**—, y en una terminal no hay ventana que recargar. **Gate**: mismo
  `perClientString` de T002; las dos referencias de `panel_layout:` (líneas 220 y 229) siguen
  apuntando a la clave y ahora se resuelven por cliente. **`strings:` conserva su único
  significado**: copy compartida byte por byte, sin excepciones anotadas adentro.
- [X] T004 Convertir `reveals:` de lista plana a **mapa por cliente** en
  `contracts/client-product-surface.yaml` (líneas 484-497): los tres publicados con sus cuatro ids
  de hoy (`startReview`, `startFromDraft`, `continueReview`, `finishReview`) y **`tui: []`, vacía y
  declarada, con su motivo** —un pane lo abriste vos y ya está a la vista; robarle el foco a alguien
  en un multiplexor es agresión— (FR-025). Adaptar el gate existente de VS Code (líneas ~1630-1690:
  `REVEALING_IDS`, los call sites de `revealPanel`, "ningún archivo revela el panel por su cuenta")
  a leer la lista del cliente. **Gate**: que `reveals.tui` **falte** es `fail`, igual que un cliente
  ausente de `min_cli_version`; la mitad simétrica —el barrido del árbol de la TUI— llega en T093,
  cuando hay árbol que barrer.
- [X] T005 [P] Agregar `listing.applies_to: [vscode, intellij, visualstudio]` en
  `contracts/client-product-surface.yaml` (bloque de la línea 19) y hacer que el verificador
  **itere `applies_to`** en vez de tener los tres clientes escritos a mano (líneas ~1164-1206:
  `tagline`, `keywords`, `package.json`, `vsixmanifest`). **Gate**: sale gratis y es real —agregar
  `tui` a esa lista manda al verificador a buscar un artefacto de tienda en `tui/`, no lo encuentra
  y falla—, y `applies_to` sin `tui` es la declaración explícita que FR-029 pide en vez del hueco.
- [X] T006 [P] Agregar `tui` a `not_in:` de `openAllChanges` en
  `contracts/client-product-surface.yaml` (queda `not_in: [visualstudio, tui]`) con el motivo al
  lado: abrir N diffs de golpe no existe como gesto en un multiplexor —no hay superficie que sostenga
  N ventanas, y N invocaciones seguidas del difftool del usuario es una avalancha, no una acción—
  (FR-019). `actionsNotIn(client)` (líneas 58-74) ya parte por coma: **no se toca**. **Gate**: la
  verificación en las **dos direcciones** del lado TUI llega con `actions.go` en T030.
- [X] T007 Agregar el bloque `keymap:` a `contracts/client-product-surface.yaml` con
  `only_in: [tui]` y las cuatro secciones (`movement`, `cursor`, `actions`, `overlays`, `toggles`)
  según [contracts/client-product-surface.md](./contracts/client-product-surface.md) § 5, con el
  comentario que declara que **la barra de teclas se dibuja de este mismo mapa**, así que una tecla
  que existe y no se muestra es imposible por construcción (FR-041). **Gates en el verificador**:
  (a) todo id de `keymap.actions` existe en `actions:`; (b) ninguna tecla se declara dos veces en el
  mismo contexto; (c) **`n` y `p` no aparecen fuera de `cursor:`**; (d) el mapa del cliente
  (`tui/internal/domain/keymap.go`) declara exactamente estos pares —con andamio `existsSync` hasta
  T029—; (e) toda acción de `panel_excluded:` está alcanzable desde `overlays.action_list` y **no**
  tiene tecla propia. Los gates (a), (b), (c) y (e) son internos al YAML y corren en verde desde este
  commit.
- [X] T008 Crear `specs/015-cliente-tui/contracts/fixtures/divergent-min.yaml` —cuatro
  `min_cli_version` maximalmente distintos— y agregar la opción `--yaml <path>` a
  `scripts/check-client-product-surface.mjs`, más el test que lo corre contra esa fixture afirmando
  **exit 0**. **Gate**: es la segunda capa del "ningún gate exige que sean iguales". La primera es
  gratis —desde que la TUI publica, los cuatro valores difieren en `main`, así que un chequeo de
  igualdad estaría rojo en `main` y no en un caso hipotético—, pero deja de probar algo el día que
  los cuatro converjan por casualidad; esta fixture no puede volverse tautológica. Es la **única**
  fixture del contrato y existe para esto.

**Checkpoint**: `node scripts/check-client-product-surface.mjs` verde con los tres clientes de
siempre; `git diff --stat` muestra **exactamente dos archivos** más la fixture nueva; ningún archivo
de `vscode-extension/`, `jetbrains-plugin/` ni `visualstudio-extension/` cambió un byte.

---

## Phase 2: El verbo `ui` (capa 2) — [US2]

**Purpose**: la mitad de la User Story 2 que funciona **antes** de que exista un binario. El verbo
aparece en `git review -h` desde el día uno, así que la TUI es descubrible antes de existir en la
máquina.

**Independent Test**: máquina con la CLI y sin la TUI — `git review -h` la lista y `git review ui`
se **niega** con un hint que instala; con la TUI presente, la reemplaza en el mismo proceso.

- [X] T009 [US2] **Verificar la separación de las dos variables** (la colisión ya está resuelta en
  los artefactos). El verbo lee `${GIT_REVIEW_UI:-}` como **ruta al ejecutable** —conserva ese
  nombre porque es una ruta a un programa, igual que `GIT_EDITOR` o `GIT_PAGER`, y porque está en la
  spec a nivel de requisito—, y el flag opt-in del instalador es **`GIT_REVIEW_WITH_UI=1`**. Antes
  eran la misma variable con dos significados: quien exportara el flag documentado y lo dejara
  exportado hacía que `git review ui` intentara `exec 1` y muriera con un error de shell en vez de
  con el hint de instalación. **Gate**: un `@test` en `tests/ui.bats` que exporta
  `GIT_REVIEW_WITH_UI=1` y afirma que `git review ui` **igual imprime el hint** y sale ≠ 0, y otro
  que exporta `GIT_REVIEW_UI=<ruta>` y afirma que **sí** gana sobre el `PATH`. Los dos juntos son lo
  que impide que alguien vuelva a unificar los nombres «por prolijidad».
- [X] T010 [US2] Crear `bin/git-review-verbs/ui`: shell POSIX puro, `set -eu`,
  `prog="git review ui"`, resolución en orden variable dedicada → `command -v git-review-ui`, y
  `exec` en los dos casos —es lo que hace que señales y exit code lleguen a la shell sin
  intermediarios—. `-h` imprime usage y sale 0; el resto de los argumentos pasa tal cual.
  **Sin `A && B || C`**: el `if` invertido es obligatorio, porque `command -v x && exec x || die`
  corre `die` también cuando el `exec` falla (shellcheck SC2015 falla en Ubuntu y en Windows en CI).
  El archivo se agrega con **modo 100755** —un archivo creado desde Windows llega 100644 y lo
  afirman el job `lint` de CI y `tests/packaging.bats`—. **Gate**: `./lint-docker.sh
  bin/git-review-verbs/ui` limpio; `find bin -type f` del job `lint` ya lo alcanza sin tocar la
  lista.
- [X] T011 [US2] Escribir el **hint por plataforma** dentro de `bin/git-review-verbs/ui` (FR-081):
  macOS → `brew install` desde el tap del proyecto; Linux con `brew` en el `PATH` → lo mismo; Linux
  sin `brew` → `web-install.sh` con su flag; Windows → `web-install.ps1 -WithUi`; cualquier otro caso
  → la página del Release. Se decide con `uname` y con si `brew` está en el `PATH`, **sin salir a la
  red**: un verbo que se niega no debería necesitar red para explicar por qué. La forma es un `case`
  sobre `uname` con un `if` invertido para la prueba de `brew`. **El hint no menciona npm** (FR-049);
  el de la CLI lo sigue mencionando porque la CLI sí está ahí. **Gate**: `@test` por rama en
  `tests/ui.bats` con `uname` y `command -v brew` stubbeados en el `PATH` de prueba, afirmando el
  texto exacto y el exit ≠ 0.
- [X] T012 [P] [US2] Agregar la línea del verbo a `Commands:` en `bin/git-review` (bloque de la
  línea 20) y su fila en la tabla de verbos (FR-005). **Gate**: `tests/usage.bats` compara la ayuda;
  sin esta línea el verbo existe y `git review -h` no lo lista, que es justamente lo que lo vuelve
  indescubrible.
- [X] T013 [P] [US2] Agregar `ui` a las **tres** completions:
  `completions/git-review-workflow.bash`, `.zsh` y `.fish` (FR-005). Son tres archivos y FR-005 pide
  los tres. **Gate**: el `@test` de completions afirma que la lista de verbos de cada archivo
  coincide con la del dispatcher.
- [X] T014 [US2] Agregar `ui` a la lista `VERBS=` **hardcodeada en `tests/dispatcher-only.bats`
  línea 12**. Sin esto, los cuatro `@test` que recorren `$VERBS` quedan **tautológicos para el verbo
  nuevo**: nadie afirmaría que `ui` no se filtró al `PATH` como ejecutable suelto. **Y el allowlist
  de `$PREFIX/*` (`git-review | git-review-lib.sh | git-review-verbs`, líneas ~71 y ~129) NO gana
  `git-review-ui`**: ese allowlist protege el camino **sin** el flag del instalador, que por FR-079
  tiene que seguir dejando exactamente lo que deja hoy. El camino con flag se prueba aparte (T112).
- [X] T015 [US2] Crear `tests/ui.bats` con nombres de `@test` en **ASCII puro** (lo verifica
  `tests/test-names.bats` sobre toda la suite): ejecutable ausente → exit ≠ 0 **y** el mensaje en
  `stderr` **y** que no se invocó nada; la variable dedicada gana sobre el `PATH`; con un
  `git-review-ui` de mentira en el `PATH`, el verbo **lo reemplaza** y el exit code que ve la shell
  es el del falso ejecutable (SC-011); `-h` sale 0 sin resolver nada. Afirmar el **status además de
  la salida** y el **efecto colateral que NO ocurrió** — nada de tests tautológicos.
- [X] T016 [US2] Correr la suite entera en el contenedor (`./tests/run-docker.sh`) y el lint
  (`./lint-docker.sh`) para confirmar que el verbo nuevo no rompió `dispatcher.bats`,
  `dispatcher-only.bats`, `usage.bats` ni `packaging.bats`. **El pin de `bats@1.13.0` no se toca en
  ninguno de sus cuatro lugares**: `tests/ui.bats` corre con el que ya está.

**Checkpoint**: `git review ui` se niega con un hint accionable en las cinco ramas de plataforma, y
la mitad de la User Story 2 está entregada sin que exista una línea de Go.

---

## Phase 3: Foundational — el módulo Go y el dominio puro (capa 3)

**Purpose**: bloquea todas las historias. El dominio es lo que los golden, los tests de contrato y
el verificador del canónico leen; sin él no hay forma de afirmar nada.

**⚠️ CRITICAL**: nada de bubbletea, lipgloss, bubbles, fsnotify ni `os/exec` bajo
`tui/internal/domain/` (FR-045). Todo lo de esta fase es unit, sin terminal y sin procesos.

**Cada tarea que crea un archivo declarado en
[contracts/client-product-surface.md](./contracts/client-product-surface.md) § 9 borra su guarda
`existsSync` en el verificador, en la misma tarea.** Un archivo ausente que pasa en silencio es
exactamente cómo un cuarto cliente entra al canónico y no se verifica nunca.

- [X] T017 Crear `tui/go.mod` y `tui/go.sum` con las **cuatro** dependencias directas y ninguna más
  (`github.com/charmbracelet/bubbletea`, `.../lipgloss`, `.../bubbles`, `github.com/fsnotify/fsnotify`),
  más el árbol vacío `cmd/git-review-ui/`, `internal/{domain,host,ui}/`, `testdata/{porcelain,golden}/`.
  **Verificar primero la línea estable de Go del día** —el plan la fija en 1.25 *al planear*— y
  estampar ese número en `tui/go.mod`, que es la **única** fuente del pin: plan, quickstart y CI lo
  citan, no lo fijan.
- [X] T018 Agregar el job `tui` a `.github/workflows/ci.yml`: `gofmt -l .` (tiene que salir vacío),
  `go vet ./...` y `go test ./...` en **ubuntu, macos y windows**, con
  `go-version-file: tui/go.mod` en vez de repetir el número. **Gate**: la suite corre con el
  apagado total de la vigilancia por default (T054), así que FR-063 y SC-016 quedan probados por
  construcción en cada corrida de este job. **El pin de bats no se toca**: este job es Go.
- [X] T019 [P] Implementar `tui/internal/domain/pathref.go` —el par `Raw` / `Display`, `struct` de
  dos strings comparable— con sus tests: des-entrecomillado, paths con espacio, no-ASCII y bytes
  hostiles. **Gate**: un test que afirma que **ningún camino manda `Display` a la CLI ni `Raw` a la
  pantalla**; acá muerde más que en los otros tres porque el mismo string pasa por un terminal.
- [X] T020 [P] Implementar `tui/internal/domain/porcelain.go` (status, list y config) con la
  **tolerancia en las tres formas** de FR-015: campo libre al final del registro
  (`strings.SplitN(line, "\t", n)` con `n` = campos conocidos), sin asumir cantidad de campos, y un
  `switch` con `default:` vacío que ignora registros desconocidos sin error y sin nota. Fixtures en
  `tui/testdata/porcelain/` **copiadas de los casos de `tests/porcelain-bytes.bats`**, que es donde
  el emisor ya está gateado contra bytes hostiles. **Gate**: los tres tests de tolerancia fallan si
  el parser se vuelve estricto en cualquiera de las tres formas.
- [X] T021 [P] Implementar `tui/internal/domain/situation.go` con la derivación de
  [data-model.md](./data-model.md) § Situation y las mismas reglas de prioridad del canónico, más el
  valor inicial `waiting`. **Gate**: un test por situación desde fixtures, y **uno específico para
  que un timeout NO sea `cli-missing`** (edge case de la spec, escenario 5 de US2); y otro para que
  `cli-missing`, `cli-outdated` y `error` **no se repinten de memoria**.
- [X] T022 Implementar `tui/internal/domain/panelmodel.go`: la proyección plana, **comparable por
  valor** —sin mapas, sin slices, sin punteros; las listas viajan como strings ya proyectados o
  arreglos de tamaño fijo con su largo—. **Gate**: un test que afirma la comparabilidad con `==` y
  falla en compilación si alguien agrega un campo no comparable. De esa propiedad depende SC-004:
  un modelo igual al anterior no produce frame, así que "exactamente un repintado" se afirma sin
  cronometrar nada.
- [X] T023 [P] Implementar `tui/internal/domain/layout.go` —los bloques por situación, espejo de
  `panel_layout:`— cubriendo **las once claves** del canónico (`cli-missing`, `cli-outdated`,
  `no-review-setup`, `no-review`, `review-walk`, `review-step`, `review-whole`, `finish-pending`,
  `finish-conflict`, `out-of-range`, `error`) y **los cinco mapas de controles de fila**:
  `inventory_controls:`, `draft_controls:`, `guide_rows.controls:`, `walkthrough_row.controls:` y
  `fixes_rows.controls:`. **Gate**: el test de contrato de layout de T024. Nota: `inventory_controls:`
  no figura en la tabla de [contracts/tui-surface.md](./contracts/tui-surface.md) § 7 y es un mapa
  real del canónico — se cubre igual (ver § Huecos al final de este documento).
- [X] T024 Escribir el **test de contrato de layout** del cliente (FR-047),
  `tui/internal/domain/layout_contract_test.go`, equivalente de `PanelLayoutContractTest` de
  JetBrains y `PanelLayoutContractTests` de Visual Studio: lee
  `contracts/client-product-surface.yaml` y afirma la **secuencia** de controles por situación, el
  `row_shape:` (badge cerrando la línea, iconos antes, botonera abajo), el **tope del 55%** del pie
  y **una sola barra de scroll** (asserts estructurales sobre el layout, nunca sobre píxeles).
  **Gate**: corre en `go test ./...`, o sea en el job `tui` de los tres SO.
- [X] T025 [P] Implementar `tui/internal/domain/usercopy.go` con **toda** la copy del cliente
  (FR-030): las cadenas compartidas de `strings:` que la TUI alcanza —y las alcanza todas—, su
  `per_client_strings.no_single_root` propia, su `per_client_strings.after_install` propia, el
  `waiting_text`, los textos de cada clave `tooltip*:` del canónico (FR-027) y las URLs de soporte.
  **Borrar la guarda `existsSync` de esta ruta** en `scripts/check-client-product-surface.mjs` y
  cablear `requireUserCopy` con la cuarta punta. **Gate**: el barrido de `tooltip*:` que hoy exige
  esas claves en tres paneles ahora las exige en cuatro; y el `perClientString` de T002/T003 compara
  la oración entera con `squash` —que ya normaliza backticks y `+`, o sea que cubre los raw strings
  de Go **sin tocarlo**—.
- [X] T026 Implementar `tui/internal/domain/confirms.go`: la tabla de confirmaciones y
  **`ConfirmMutation(id, …)`**, la **única** puerta del cliente, cuarto equivalente de
  `confirmMutation` / `UiMessages.confirm` / `GitReviewDialogs.Confirm`. **Gate 1 de los tres**:
  `collectConfirmingIds(yaml)` (línea 1528 del verificador) contra la tabla del cliente **en las dos
  direcciones**. La excepción declarada sigue siendo una sola: `walkthroughInit`, que elige entre
  dos cursos en vez de confirmar, y **el comentario que la exime lo lee CI — reformularlo rompe el
  check**. Los gates 2 y 3 llegan en T067 y T068, cuando hay call sites y overlay.
- [X] T027 [P] Implementar `tui/internal/domain/icons.go`: **un solo mapa** que contesta los cinco
  nombres de `icon_vocabulary:` (`prev`, `next`, `file`, `trash`, `diff`), cada entrada con **dos**
  glifos, Unicode y ASCII. **Gates, y ninguno es una lista de codepoints escrita a mano**: (1) cada
  glifo Unicode mide **exactamente una celda** —East Asian Width `Narrow` o `Neutral`, nunca `Wide`
  ni `Ambiguous`—, pasado por la **misma** tabla de ancho que usa el renderer; (2) cada glifo ASCII
  está en `U+0020..U+007E`. La selección de codepoints se hace **con el test corriendo**: prohibir
  emoji no alcanza, porque `≡`, `▶` y media Geometric Shapes son `Ambiguous` sin ser emoji, y ése es
  el modo de falla real —una celda en un terminal, dos en otro, y las columnas de todas las filas se
  desalinean—.
- [X] T028 [P] Implementar `tui/internal/domain/version.go` (`Version` + `MinCLIVersion`) y
  `tui/internal/domain/installhint.go` (los comandos npm de **la CLI**, que son lo que dibuja el
  panel `cli-missing`/`cli-outdated` — la TUI no se instala por npm, la CLI sí). Cablear
  `minFor("tui")` contra `version.go` en el verificador y **borrar las dos guardas `existsSync`**.
  **Gate**: la comparación de versión es un **piso estricto**, sin techo, así que una CLI más nueva
  que el mínimo nunca se reporta desactualizada; un test lo afirma con una versión mayor.
- [X] T029 [P] Implementar `tui/internal/domain/keymap.go` —el par tecla → acción o movimiento— como
  espejo exacto del bloque `keymap:` del canónico, y **borrar su guarda `existsSync`**, activando el
  gate (d) de T007. **Gate propio**: un test del cliente que afirma que **la barra de teclas se
  dibuja de este mismo mapa** (una tecla que existe y no se muestra es imposible por construcción) y
  que `n`/`p` están reservadas para el cursor de la review y no aparecen en el movimiento de la
  lista.
- [X] T030 Implementar `tui/internal/domain/actions.go`: las **26** acciones que la TUI ofrece, con
  su verbo y su argv exacto según [contracts/cli-invocation.md](./contracts/cli-invocation.md)
  § Mutaciones —incluido el orden fijo de flags de `start`, el `--` antes de la rama, el
  `--onto-source` **sólo** si el porcelain lo reporta, y el `discardAllFixes` que corre
  `--fixes-only` **siempre sin rama**—. `openAllChanges` **no está**. **Gates**: (1) una tabla
  `(acción, parámetros) → argv` en `actions_test.go`, la verificación automatizada de la lista
  cerrada de FR-014; (2) en el verificador, el mismo par de bucles que ya tiene Visual Studio
  (líneas ~964-977) para las 26 en las dos direcciones, más el lado TUI de `not_in:` de T006 —la TUI
  no declara `openAllChanges` en **ninguna** de sus superficies—; (3) la clasificación 22 nativas /
  4 delegadas / 1 `not_in` cubre las 27 sin huecos ni sobrantes (SC-006).
- [X] T031 [P] Implementar `tui/internal/domain/intent.go`: `ReviewIntent` → argv del asistente, en
  el orden fijo `[flags de layout] [--delta] [--local|--offline] -- <branch>` (walk sin flag, keys
  `--keys`, step `--step`, whole `--no-walk`). **Gate**: tabla de casos que falla si el orden cambia
  o si el `--` se pierde.
- [X] T032 [P] Implementar `tui/internal/domain/watchrules.go`: las raíces, la allowlist de prefijos
  de `refs/` (`heads/`, `remotes/`, `review-edits/`, `review-saved-edits/`), las profundidades por
  raíz y el presupuesto (`max_dirs`, valor inicial 512) como **datos puros**, sin filesystem.
  **Gate**: tests sobre los prefijos deliberadamente excluidos (`refs/tags/`, `refs/notes/`,
  `refs/stash`, `refs/bisect/`, `refs/rewritten/`) — `tags/` en un repo grande es la mitad del
  presupuesto.
- [X] T033 [P] Implementar `tui/internal/domain/` — `StateToken` (huella `{branch?, tip?, situation}`)
  e `InvocationClass` (las cuatro clases con sus timeouts: `Read` 15 s, `LocalMutation` 120 s,
  `Network` 300 s, `SupportGit` 30 s; verbo desconocido → `Read`, la misma regla que `invoke.ts`).
  **Gate**: un test que afirma que `config base|remote` cae en `Read` —es una escritura de config, no
  un movimiento de refs— igual que en los otros tres.
- [X] T034 Escribir `tui/internal/domain/purity_test.go`: **ningún** import de bubbletea, lipgloss,
  bubbles, fsnotify ni `os/exec` bajo `internal/domain/` (FR-045). Es el equivalente de la regla que
  en JetBrains impide `com.intellij` en el dominio.
- [X] T035 Escribir `tui/module_boundary_test.go`: `tui/go.mod` declara **exactamente** las cuatro
  dependencias previstas y ninguna más, y **ningún import del árbol nombra otro cliente del
  monorepo** (FR-075, SC-014). La frontera de lenguaje es el punto de haber elegido Go: se descartó
  Node/Ink precisamente porque compartir el parser con `vscode-extension/` estaría a un `import` de
  distancia. Un firewall que depende de disciplina no es un firewall.
- [X] T036 [P] Escribir `tui/internal/host/fsnotify_boundary_test.go`: **`fsnotify` se importa en un
  solo archivo**, `internal/host/watch_fsnotify.go` (que todavía no existe; el test afirma "cero o
  uno, y si hay uno es ése"). **Gate**: es lo que impide que la vigilancia se filtre a otra capa
  cuando llegue T056.
- [X] T037 Agregar el **chequeo de cierre del andamio** a
  `scripts/check-client-product-surface.mjs`: *si `tui/go.mod` existe, todas las rutas declaradas de
  la TUI tienen que existir*. Convierte el `existsSync` —que hace que un cliente sin archivos pase
  en silencio— en un error apenas el cliente es real. **Gate**: borrar un archivo del dominio pone CI
  en rojo en vez de volver el chequeo mudo.

**Checkpoint**: `cd tui && gofmt -l . && go vet ./... && go test ./...` verde en los tres SO;
`node scripts/check-client-product-surface.mjs` verifica al cuarto cliente de verdad, sin andamios
en las rutas ya creadas.

---

## Phase 4: Host de lectura y dibujo read-only (capa 4) — [US3] [US2]

**Goal**: la TUI ya es útil. Lee estado, dibuja las once claves de layout y responde a los
disparadores **1, 3 y 4** (acción propia, focus-in y la tecla `r`). **Sin vigilancia**: FR-063 queda
probado *antes* de que exista el watcher, que es el orden que hace que la vigilancia sea un
acelerador y no un cimiento.

**Independent Test**: sandbox con review walk, step y whole; contrastar **cada campo** del panel
contra `git review status --porcelain` en otro pane, y recorrer la secuencia entera sólo con teclado.

- [X] T038 [US3] Implementar `tui/internal/host/invoke.go`: **siempre `git review <verbo> …`**, argv
  como arreglo y sin shell, `cwd` = el del proceso, `stdout`/`stderr` decodificados como **UTF-8
  explícito** en los tres SO, timeouts por clase con kill del árbol best-effort
  (`timedOut=true`, `exitCode=nil`), y `GIT_REVIEW_ADVICE=0` exportado **en este archivo y en
  ningún otro** (FR-009). **Nunca** resolver ni ejecutar el dispatcher por cuenta propia y **sin**
  ajuste de ruta configurable (FR-007, FR-008). **Gate**: un test que barre el árbol y falla si
  `GIT_REVIEW_ADVICE` aparece fuera de este archivo; otro que afirma que el único `command` es `git`.
- [X] T039 [US3] Agregar el **registro de invocaciones** en memoria a
  `tui/internal/host/invoke.go`: comando, cwd, duración, exit, `timedOut` y `stderr` por cada
  start/end. Vive en memoria y muere con el proceso (FR-078: **cero archivos propios en disco**).
  **Gate**: es lo que hace medible SC-002 y lo que dibuja `showCliLog`; un test afirma que no se
  escribe ningún archivo.
- [X] T040 [P] [US3] Implementar `tui/internal/host/gitdata.go`: **una sola** invocación
  `git rev-parse --git-dir --git-common-dir --show-toplevel`, con los relativos resueltos contra el
  `cwd`. **Sin `--path-format=absolute`**, que es de git 2.31 y el proyecto declara 2.23+. **Gate**:
  un test en un worktree enlazado que afirma que los dos directorios se distinguen — vigilar el
  equivocado deja media pantalla muerta.
- [X] T041 [P] [US2] Implementar `tui/internal/host/askpass.go` y el **centinela** en
  `tui/cmd/git-review-ui/main.go`: para la clase red, el entorno lleva `GIT_TERMINAL_PROMPT=0` y
  `GIT_ASKPASS`/`SSH_ASKPASS` apuntando **al propio ejecutable** (`os.Executable()`) con la variable
  centinela puesta; `main` la detecta **como lo primero que hace, antes de tocar el terminal**, y
  sale ≠ 0 sin imprimir nada. Cero archivos nuevos y una ruta que existe en las siete plataformas.
  **Gate**: un test que invoca el binario con la centinela y afirma exit ≠ 0, salida vacía y —lo que
  importa— **que no se abrió alt-screen**: un askpass que inicializa el terminal le arruina la
  pantalla al `git` que lo llamó.
- [X] T042 [US2] Implementar el **probe de versión** en `tui/internal/host/`: `--version`, `stdout`
  trim, comparación contra `min_cli_version.tui`. Error de spawn o exit ≠ 0 → `cli-missing`; no
  parsea o < mínimo → `cli-outdated`; ok → seguir a `status`. **Gate**: un test que afirma que un
  **timeout no es una CLI ausente** —se dice que tardó y dónde mirar— y otro que afirma el piso
  estricto sin techo.
- [X] T043 [US3] Implementar el ciclo de lectura de estado: `status --porcelain` primero; si exit 2,
  `list --porcelain` y `config --porcelain`, y **que fallen no cambia la situación**; `status --why
  <raw>` con el path **crudo** de la entrada. **Nunca** parsear el `stdout` humano de una mutación
  para decidir la situación (FR-013), y **nunca** derivar situación leyendo refs, config de review o
  el working tree (FR-012). **Gate**: un test que afirma que `list`/`config` sólo se invocan en
  `no-review`/`finish-pending` — adentro de una review no se invoca `config --porcelain`, que es la
  razón por la que los registros del pie ni llegan.
- [X] T044 [US3] Implementar `tui/cmd/git-review-ui/main.go` como **composition root**: elección de
  watcher (T054 la usa), lectura de las claves `reviewui.*` con `git config` leídas
  **defensivamente** —error ignorado, como el `|| true` del lado sh— con `--global` como preferencia
  y local como override (FR-061), y arranque del programa. **La CLI no lee ninguna clave
  `reviewui.*` y la TUI no escribe ninguna `reviewworkflow.*` que no sea a través de un verbo**
  (FR-077). **Gate**: un `@test` en `tests/ui.bats` o un grep en CI que afirma que ningún verbo de
  `bin/` menciona `reviewui`.
- [X] T045 [US3] Implementar `tui/internal/ui/program.go`: `Model`, `Update` y `View` con las seis
  clases de mensaje (`KeyMsg`/`MouseMsg` → intent tipado, `WindowSizeMsg` → `Viewport`,
  `FocusMsg`/`BlurMsg`, `watchMsg{}`, `readDoneMsg`, `mutationDoneMsg`). Las invocaciones salen como
  `tea.Cmd`, **nunca en línea**: un `Update` que bloquea es un pane congelado. **Gate**: un test que
  afirma que ningún `Update` llama al invocador de forma síncrona.
- [X] T046 [US3] Dibujar `waiting_text` en el **primer frame**, antes de la primera invocación
  (superficie de espera). **Gate**: un test que afirma que el frame inicial no anuncia una CLI
  ausente antes de que nadie haya mirado — que es exactamente el bug que el `waiting_text` existe
  para evitar en los otros tres.
- [X] T047 [US3] Implementar `tui/internal/ui/render.go`: `View(PanelModel, Viewport) -> (frame,
  HitMap)`, **pura**. Cada control dibujado deja su rectángulo en la `HitMap`. **Gate**: sin
  `HitMap` no hay forma honesta de escribir el test "sólo con el mouse" de SC-015 —habría que
  adivinar coordenadas—, así que el test de T091 depende de esta estructura.
- [X] T048 [US3] Implementar `tui/internal/ui/keys.go`: `KeyMsg`/`MouseMsg` → **intent tipado**,
  nunca una acción directa, resuelto desde el mapa de `keymap.go`. Dibujar la **barra de teclas** del
  mismo mapa. **Gate**: en `finish-conflict` las teclas del cursor **no están disponibles y la barra
  no las ofrece** (US3, escenario 4): un test por situación afirma que la barra refleja la situación
  y no un set fijo.
- [X] T049 [US3] Cablear los **disparadores 3 y 4**: focus-in pedido con `tea.WithReportFocus()`
  —si el terminal o el multiplexor no lo entregan **no llega ningún mensaje**, la degradación es
  silencio y no hay nada que detectar (FR-037)— y la tecla `r`, **disponible en las ocho
  situaciones** (FR-038). **La TUI no le dice al usuario que encienda `focus-events`**: sería copy
  nombrando un mecanismo, y la regla de copy lo prohíbe. **Gate**: un test por disparador que falla
  si ese disparador deja de funcionar (SC-003).
- [X] T050 [US3] Construir el juego de **golden files** en `tui/testdata/golden/`: las **once claves
  de `panel_layout:`** × **2 tamaños** (80×24 y 120×40) × **3 modos** (default, `NO_COLOR`, ASCII
  forzado) = **66 archivos**, más el frame de espera a los dos tamaños. Se rinden desde una
  `PanelModel` fija construida en `tui/testdata/porcelain/`, **no desde un repo real**: un golden que
  depende de un sandbox es un golden que cambia solo. **Gate**: SC-009 y SC-017 — cambiar un byte del
  dibujo de cualquier situación, a cualquier tamaño, pone en rojo un archivo de referencia.
- [X] T051 [US3] Implementar la bandera `-update` de los golden **bajo el build tag
  `goldenupdate`**, no bajo un `if` (FR-070). En el binario que CI construye la bandera **no
  existe**, así que pasarla es un error de flag desconocido y no un no-op silencioso. Se regeneran a
  mano con `go test -tags goldenupdate ./internal/ui -update` y **se revisan como diff**. **Gate**: un
  guard por `os.Getenv("CI")` se descartó a propósito —depende de que el ejecutor setee `CI` y hay
  runners que no; un guard que se puede olvidar no es un guard—.
- [X] T052 [US2] Dibujar `cli-missing` y `cli-outdated` como **dos situaciones de panel completas**,
  con los mismos seis bloques que en los otros tres clientes, incluido el bloque `code_command` con
  el control `copyCliInstall`. **`reload_or_wait` no se dibuja**: el panel usa su
  `per_client_strings.after_install` propia, que nombra el próximo paso que sí existe en un pane
  (FR-069). El copiado en sí llega en T092. **Gate**: los golden de esas dos claves.
- [X] T053 [US3] Escribir el test de **alcanzabilidad sólo con teclado** (FR-073, SC-015) en
  `tui/internal/ui/reachability_keyboard_test.go`: recorrer las ocho situaciones con `KeyMsg`
  sintéticos y afirmar que **cada control declarado se alcanza y se activa**, sin excepción. **Nunca hay un control que sólo responda al mouse** — es lo
  que hace que agregar mouse no le saque nada a nadie.

**Checkpoint**: la TUI arranca en un pane, dibuja las once claves de layout, refresca con `r` y al
volver el foco, y no lanza un solo proceso en reposo. FR-063 está probado antes de existir el
watcher.

---

## Phase 5: La vigilancia (capa 5) — [US1]

**Goal**: el disparador 2, agregado a algo que ya andaba sin él. Es lo único genuinamente nuevo de
este cliente: los paneles de IDE se enteran porque el host les avisa y **la TUI no tiene host**.

**Independent Test**: sandbox con review activa; con la TUI abierta y **sin tocarla**, mutar el repo
desde otro pane (`git review next`, escribir el borrador, `git pack-refs`, `git review config base`,
`git checkout`) y verificar que el panel refleja cada cambio; medir que en reposo no se lanza ningún
proceso.

- [ ] T054 [US1] Implementar `tui/internal/host/watch.go`: la **interface** `Watcher`
  (`Start`/`Rebuild`/`Stop`) y `nopWatcher`, con la elección hecha **una sola vez** en
  `tui/cmd/git-review-ui/main.go` desde la variable de entorno de soporte. **La suite corre con
  `nopWatcher` por default**, así que FR-063 y SC-016 se prueban **por construcción en todos los
  tests**: si algún camino necesitara que el watcher disparara, la suite entera estaría roja, no un
  test. **Gate**: un flag chequeado en veinte lugares deja veinte formas de que la corrección dependa
  del watcher; una interface con un no-op deja cero — y hay un test que afirma que la elección se
  hace en un solo archivo. **No es una clave `reviewui.*`**: apagar el motor no es una preferencia
  del revisor sino una palanca de suite y de soporte; se documenta en `tui/CONTRIBUTING.md`.
- [ ] T055 [US1] Implementar `tui/internal/host/watchset.go`: `BuildWatchSet(gitDir, gitCommonDir,
  draftPaths) -> WatchSet` con las **seis raíces** de
  [contracts/refresh.md](./contracts/refresh.md) —`<git-common-dir>/` filtrada a `{config,
  packed-refs}`, `refs/`, `reftable/` si existe, los dos directorios de borradores filtrados a
  `*.md`, y `<git-dir>/` filtrada a `{HEAD}`—, el **dedup indexado por directorio con unión de
  filtros**, el cierre sobre directorios con su profundidad y su allowlist, y el presupuesto.
  Devuelve un conjunto **ordenado y comparable**, para que "¿cambió?" sea una comparación y no un
  recorrido. Las rutas de los borradores salen de **lo que la CLI ya reportó** (FR-036), nunca
  rearmadas del layout del gitdir. Una raíz que no existe **se ignora en silencio** y no impide el
  arranque (FR-064). **Gate**: el test del dedup —fuera de un worktree enlazado, `<git-dir>` aparece
  **una sola vez** con el filtro unido `{config, packed-refs, HEAD}`—, que es barato y protege una
  propiedad fácil de romper sin que nada se note.
- [ ] T056 [US1] Implementar `tui/internal/host/watch_fsnotify.go` —**el único archivo del árbol que
  importa `fsnotify`**, activando el gate de T036— con **debounce trailing de 200 ms y techo de 1 s**
  y **coalescencia total**: N eventos de cualquier ruta producen **un** `watchMsg{}` **sin payload**
  (FR-062). El techo no es adorno: un debounce trailing puro se muere de hambre bajo un flujo
  continuo de escrituras, que es exactamente lo que hace un agente llenando el borrador. **Gate**: un
  test que afirma que el mensaje no lleva payload y que la vigilancia **nunca lee** el contenido de
  una ruta vigilada —no parsea un ref, no abre `config`, no lee un `.md`—.
- [ ] T057 [US1] Implementar el orden `Rebuild` **antes** de emitir en el disparo del debounce, e
  incremental (agrega los watches nuevos, saca los que ya no están, **nunca tira el watcher entero**).
  Rehacer antes de pedir la lectura hace que la carrera sea inofensiva: un evento perdido durante el
  `Rebuild` está, por construcción, **antes** de la lectura que viene inmediatamente después, y esa
  lectura re-lee todo desde porcelain. Un evento perdido durante un rebuild puede duplicar trabajo;
  **no puede perder estado**. **Gate**: un test que crea un directorio dentro de una ruta vigilada y
  afirma que el conjunto se rehizo y que llegó **un** mensaje.
- [ ] T058 [US1] Escribir `tui/internal/host/watch_fsnotify_test.go` con los **cuatro agujeros** de
  FR-058, cada uno con su test: (1) **rename atómico** —escribir `reviewworkflow.base` con
  `git config` y afirmar el evento, **dos veces**, porque el segundo prueba que el watch sobrevivió
  al primer rename—; (2) **refs empaquetados** —crear una review, `git pack-refs --all`, afirmar
  evento, después `git update-ref -d` de un ref empaquetado—; (3) **anidamiento** —escribir un
  borrador para la rama `feature/foo` con la TUI ya arrancada y afirmar **un** evento, ídem crear una
  review de `feature/foo` en modo step y avanzar un paso—; (4) **backend `reftable`** —`git init
  --ref-format=reftable`, arrancar, afirmar que no hubo error de arranque y que una mutación
  dispara—. **Es el único paquete que instancia el watcher real** y corre con la vigilancia
  explícitamente encendida.
- [ ] T059 [US1] Agregar a `tui/internal/host/watch_fsnotify_test.go` los dos tests de la **sexta
  raíz** y el del **worktree enlazado**: dos `git checkout` seguidos disparan los dos (el segundo
  prueba que el watch sobrevivió al rename de `HEAD`, que git escribe con `HEAD.lock` igual que
  `config`); y en un `git worktree add`, los eventos del **directorio común** llegan, los del
  borrador salen del gitdir **del worktree**, y un `checkout` en **ese** worktree dispara mientras
  que uno en el principal **no** — que es lo que prueba que la raíz va sobre `<git-dir>` y no sobre
  el común.
- [ ] T060 [US1] Implementar el **piso de poll opt-in** (FR-039): `reviewui.pollseconds`, clave
  `git config` bajo el namespace del cliente, **sin default** (ausente = apagado), leída
  defensivamente. Es un **piso**, no un poll: programa una lectura sólo si no hubo ninguna en los
  últimos N segundos y se re-arma en cada lectura venga de donde venga, así que con la vigilancia
  funcionando **no agrega ni una invocación**. **No se presenta como el mecanismo**: no está en la
  barra de teclas, no tiene control en el panel y no aparece en ninguna copy. Existe para el agujero
  5 —inotify que no dispara en un bind mount Windows→WSL o en varios NFS/SMB—, que falla en silencio.
  **Gate**: un test que afirma cero invocaciones extra con la vigilancia viva.
- [ ] T061 [US1] Escribir el test de **SC-002** en `tui/internal/host/idle_test.go`: con la TUI
  abierta y sin tocarla, **cero invocaciones nuevas en el registro** durante una ventana de reposo. Es un número medido, no
  cualitativo, y hoy **ningún contrato le declara un gate** (ver § Huecos): éste lo instala.
- [ ] T062 [US1] Documentar y afirmar la regla que la elección de `nopWatcher` por default le impone
  a la suite: **ningún test puede esperar un evento de archivo como forma de sincronizarse**. Los
  tests de comportamiento disparan el refresco con el mensaje, no con el filesystem. **Gate**: FR-074
  y SC-016 — la suite entera pasa con la vigilancia apagada, que es la condición por default.

**Checkpoint**: los cuatro disparadores tienen su test, los cuatro agujeros tienen el suyo, y la
suite sigue verde con la vigilancia apagada.

---

## Phase 6: Mutaciones y el ciclo de riesgo (capa 6) — [US5] [US3]

**Goal**: el ciclo que ya es producto en los otros tres, con **una sola puerta**. Lo que no se puede
deshacer pregunta; lo demás no.

**Independent Test**: sandbox sin review; configurar la base, arrancar con el asistente en cada forma
de lectura, guardar, continuar, cerrar, deshacer y abortar; contrastar **cada argv** contra
[contracts/cli-invocation.md](./contracts/cli-invocation.md) usando el registro de invocaciones.

- [ ] T063 [US5] Implementar `tui/internal/host/lock.go`: `MutationLock` de **profundidad 1** —una
  segunda mutación mientras hay una en curso **se descarta con aviso, no se encola**— más la
  **ventana de silencio**: mientras corre el verbo los `watchMsg{}` se descartan y se recuerda que
  hubo; al terminar, **una** lectura inmediata y una ventana de 600 ms; si hubo disparos
  descartados, **una** lectura más al cerrarse. **Gate**: la segunda lectura no rompe SC-004 porque
  devuelve el mismo estado y `PanelModel` es comparable por valor —un modelo igual al anterior no
  produce frame—, así que SC-004 se afirma sobre el **repintado**, no sobre el número de lecturas.
  Es el único lugar del diseño donde se gasta un proceso a propósito, y compra que la corrección no
  dependa de adivinar cuánto tarda inotify en callarse.
- [ ] T064 [US5] Escribir el test de **SC-004** en `tui/internal/ui/repaint_test.go`: una mutación
  que escribe config y refs varias veces produce **exactamente un** repintado. Se afirma contando
  frames, no lecturas.
- [ ] T065 [US5] Revalidar el `StateToken` **adentro del lock, antes del spawn**: es lo que impide
  mutar sobre datos viejos cuando el estado cambió entre el gesto y el "sí". En una TUI con
  vigilancia esa ventana es más real que en un IDE, porque el panel puede haberse repintado mientras
  el overlay estaba abierto. **Gate**: un test que cambia el estado con el overlay abierto y afirma
  que la mutación **no** corre.
- [ ] T066 [US5] Implementar `tui/internal/ui/confirm.go`: **el único overlay modal del cliente**,
  alimentado por `ConfirmMutation` de T026. En una TUI un modal es un overlay; que haya **uno solo**.
- [ ] T067 [US5] Instalar el **gate 2 de `confirms:`** en
  `scripts/check-client-product-surface.mjs`: una regex sobre el **primer argumento** de
  `ConfirmMutation(...)` en todo `tui/`. **No un `includes` del nombre**: un id aparece como nombre
  de función, de constante y de campo, así que un `includes` da verde con el call site cambiado —
  está probado que daba verde, y es lo que dejó a `confirms:` sin gobernar durante meses. **Gate**:
  se prueba **rompiéndolo** (SC-007): cambiar el id que un call site pasa tiene que poner CI en rojo.
- [ ] T068 [US5] Instalar el **gate 3 de `confirms:`**: sólo `tui/internal/ui/confirm.go` construye
  el tipo de overlay que bloquea input, y **ningún otro archivo lo asigna**. Es el equivalente del
  barrido de `showWarningMessage` sueltos que destapó el agujero original. **Gate**: se prueba
  rompiéndolo — agregar un modal fuera de la puerta pone CI en rojo (SC-007, SC-018).
- [ ] T069 [US5] Implementar el **asistente de inicio**: los tres sondeos de `config --porcelain`
  (siempre clase `Read`, nunca red), y ofrecer **sólo** las formas de lectura que la CLI reporta como
  viables (registro `offer`). Al terminar la última pregunta la review **arranca sin cartel de
  confirmación**, y vale para los **dos** caminos que llegan al start: el asistente y
  `startFromDraft` (US5, escenario 2). El origen preseleccionado sale de `reviewui.startsource`
  cuando está (FR-061). **Gate**: un test que afirma que `startReview` **no** pasa por
  `ConfirmMutation` — un cartel que aparece siempre deja de leerse, y entonces tampoco se lee el que
  importa.
- [ ] T070 [US5] Implementar `finishReview`, `undoFinish` (con `--force` **nunca como primera
  opción**, sólo tras el stderr que lo pide) y `resumeFinish` (con `--onto-source` **sólo si el
  porcelain de la review lo reporta**, US5 escenario 5), más sus banners de `finish-pending` y
  `finish-conflict`. **Gate**: la tabla de argv de T030 cubre las tres; un test afirma que el banner
  de cierre pendiente **no** trae ningún aviso en prosa que repita lo que sus dos controles ya
  dicen — es lo que hacía el banner viejo nombrando `finish --abort` y `clean --keep-fixes`.
- [ ] T071 [US5] Implementar `abortReview`, `saveReview` y `continueReview`, cada uno con su fila de
  la tabla de confirmaciones. **Gate**: se confirma lo que no se puede deshacer, **y nada más**.
- [ ] T072 [P] [US5] Implementar `setBase` y `setRemote` (`config base|remote -- <name>`), dibujados
  en `no-review` como el paso de setup cuando no hay base. **Gate**: un repo sin base muestra
  **sólo** ese paso, sin un *Start* engañoso (US5, escenario 1); sin candidatas leídas degrada con
  el `no_base_candidates` del canónico.
- [ ] T073 [P] [US3] Implementar `next` y `prev` cableados a las teclas **`n`/`p` reservadas**, con
  la regla de situación: sólo con `situation == review`, y deshabilitados en los extremos
  (`atFirst`/`atLast`) y en `finish-conflict`. **Gate**: un test que afirma que `j`/`k` mueven la
  fila enfocada y **no** el cursor de la review, y otro que afirma lo simétrico — confundir los dos
  conceptos es el error que la reserva de `n`/`p` existe para impedir.
- [ ] T074 [US5] Implementar la **línea de estado** del panel en `tui/internal/ui/render.go` (con su
  campo en `tui/internal/domain/panelmodel.go`) para lo que en los otros tres se
  notifica —el `update` de borrador con los tres números del registro `merged`, el copiado, y el
  residual de un `finish` sin banner—: en un pane no hay toasts, el panel **es** la superficie.
  **Cuál de los dos casos es se decide por lo que se pidió, nunca leyendo la salida de la CLI**. Y
  cuando la TUI muestre el resultado de un verbo en verde, lo lee de **`stdout`**, que es donde los
  verbos lo escriben: un camino que sólo lee `stderr` en verde se queda sin la única frase que
  contesta qué pasó. **Gate**: un test que afirma que el resultado sale de `stdout` y que un
  `stdout` de verbo **no se reenvía tal cual** —termina en el comando del paso siguiente, que acá es
  una tecla—.

**Checkpoint**: SC-001 —arrancar, leer, mover el cursor y cerrar sin salir del pane y sin escribir un
comando— y los tres gates de `confirms:` probados rompiéndolos.

---

## Phase 7: El pie y los cinco mapas de fila (capa 7) — [US6]

**Goal**: la mitad del panel que no es la lectura, y la que hace que el revisor no tenga que
deletrear rutas en una terminal. **Adentro de una review el pie no existe.**

**Independent Test**: sandbox sin review, con borrador fresco, borrador gastado, guías en los tres
estados y al menos una rama de ediciones; recorrer cada fila y cada control; después entrar en una
review y verificar que **ninguna** sección del pie se dibuja.

- [ ] T075 [US6] Completar el parseo de `config --porcelain` en
  `tui/internal/domain/porcelain.go` para los registros del pie: `draft` (**sólo cuando hay**, con
  path, par annotated/total y estado), `guide` (**siempre las dos filas**, exista o no el archivo),
  `walkthrough` (**siempre**, con rama, estado y par de progreso) y `fixes` (una por rama
  `review-fixes/*`, con su badge). **Gate**: un test afirma que las dos guías y el walkthrough se
  emiten aunque el archivo no exista —**la ausencia se reporta, no se implica con el silencio**— y
  que `draft` sólo aparece cuando hay.
- [ ] T076 [US6] Dibujar la **fila del walkthrough** con `walkthrough_row.controls:` completo:
  nombrada por su rama, con su badge de estado y sus dos verbos. **Gate**: el test de contrato de
  layout de T024.
- [ ] T077 [US6] Dibujar las **dos filas de guías** con `guide_rows.controls:` completo
  (`openGuide`, `createGuide`, `discardGuide`), con badges distintos y el control correcto habilitado
  en cada una. `discardGuide` es **sólo para la propia**: la compartida es un archivo trackeado y la
  CLI niega `--delete --team`. **Gate**: lo que cambia con el estado es el `enabled`, **nunca la
  presencia** — dos filas que arman botoneras distintas no se alinean una con la otra.
- [ ] T078 [US6] Dibujar el bloque de **borradores** con los cuatro `draft_controls:` en su orden y
  en sus dos lugares de la fila —los dos con etiqueta en la botonera, los dos de icono pegados al
  par annotated/total de la cabecera—, con la regla de que los dos con etiqueta se dibujan **sólo en
  una fila fresca** y una fila gastada los pierde. **Gate**: un borrador a medio llenar muestra el
  par de progreso y `startFromDraft` **apagado con el motivo a mano** —apagado no adivina los flags
  más que ausente, y encima dice por qué, que un control que no está no puede decir—.
- [ ] T079 [US6] Dibujar la sección de **ramas de ediciones** con `fixes_rows.controls:`
  (`discardFixes` por fila, `discardAllFixes` en la sección). **Gate**: la rama en la que estás
  **no ofrece borrarse** (`disabled_when: current`), y `discardAllFixes` corre `--fixes-only`
  **siempre sin rama**, incluso con la sesión cerrada: el argv no puede depender de un dato que se
  relee en cada refresco, o un `clean <x>` que llegue tarde se llevaría puesta una review viva desde
  un control que promete borrar una rama de ediciones.
- [ ] T080 [US6] Dibujar el bloque de **inventario** con `inventory_controls:` (`continueReview`,
  `discardInventory` con sus dos etiquetas) y las secciones de **configuración** y **soporte**.
  **Gate**: `inventory_controls:` es el mapa que la tabla de
  [contracts/tui-surface.md](./contracts/tui-surface.md) § 7 no enumera (ver § Huecos): esta tarea
  lo cubre y el test de contrato de layout lo ata.
- [ ] T081 [US6] Implementar `walkthroughInit` (con sus **dos cursos**, "Update" / "Start over": es
  la **única excepción declarada** de la puerta única, y sigue siendo `confirms: true` porque hay un
  modal entre el gesto y la mutación), `walkthroughBuild`, `createGuide` y `discardGuide`. **Gate**:
  el comentario que exime a `walkthroughInit` **lo lee CI**; reformularlo rompe el check.
- [ ] T082 [US6] Implementar `cleanReview` (una, keep-fixes, todas), `forgetReview` (saved, delta
  —incluida `--stale`, que es **clase red**—, draft) y `discardFixes`/`discardAllFixes`, cada uno con
  su fila de confirmaciones. **Gate**: la tabla de argv de T030.
- [ ] T083 [US6] Afirmar en el **proyector** que dentro de una review el `PanelModel` **no proyecta**
  ninguna `tools_section` (FR-023) — no es que no se dibuje: no se proyecta —, y el **tope del 55%**
  del pie con **una sola barra de scroll**: cada sección abierta pide el alto de su contenido y
  ninguna scrollea por dentro. **Gate**: el test de contrato de layout y los golden del pie. Sin el
  tope, el pie *es* el panel; repartir el alto entre las abiertas da una barra por sección, ninguna
  capaz de mostrar la suya entera.

**Checkpoint**: US6 completa; entrar en una review deja el panel sin una sola sección de pie.

---

## Phase 8: Overlay de acciones, picker, delegadas, mouse y portapapeles (capa 8) — [US7] [US4] [US3] [US2] [US1]

**Goal**: cerrar la superficie. Las cuatro acciones de `panel_excluded:` dejan de estar sin ninguna
superficie, las cuatro delegadas van a las herramientas que el revisor ya eligió, y el mouse hace
exactamente lo que hace su tecla.

**Independent Test**: para cada situación, abrir la lista y comprobar que enumera **exactamente** las
acciones que esa situación habilita; y recorrer la secuencia de US3 una segunda vez **sólo con el
mouse**.

- [ ] T084 [US7] Implementar `tui/internal/ui/palette.go`: el **overlay de lista filtrable**
  (`bubbles/list` + `textinput`) que enumera las acciones que la situación actual habilita, con su
  tecla al lado donde la tenga. Es el equivalente de `surface: action` de los otros tres —paleta de
  comandos, menú *Tools*, `.vsct`— y las cuatro de `panel_excluded: [goToEntry, forgetReview,
  previewEditsStat, showCliLog]` viven **sólo** ahí (FR-021). **No es un segundo modal**: FR-024
  prohíbe otro modal hablando de **confirmaciones**, y esta lista no confirma, elige. **Gate**: el
  gate (e) de `keymap:` —toda acción de `panel_excluded:` alcanzable desde acá y **sin** tecla
  propia— más un test por situación.
- [ ] T085 [US7] Cablear el despacho del overlay a **la misma** `ConfirmMutation` que el cuerpo: una
  acción destructiva elegida desde la lista pasa por la misma puerta que si se hubiera activado en el
  cuerpo (US7, escenario 3). **Gate**: el gate 2 de T067 lo verifica solo, porque el call site está
  en el mismo despachador — es lo que hace que la puerta única sea única de verdad.
- [ ] T086 [US7] Implementar `goToEntry` como **picker aparte**, no la misma lista: enumera
  **entradas**, no acciones, y abre la elegida **sin mover el cursor de la CLI** (US3, escenario 5).
  O sea: abre y punto, **no** invoca `next`/`prev` N veces. **Gate**: un test que afirma que el
  cursor de la CLI no se movió.
- [ ] T087 [US7] Implementar `showCliLog` (overlay o `$PAGER`) sobre el registro de invocaciones de
  T039: comando, directorio, duración y error. **Gate**: es la **tercera capa** de la regla de copy
  —etiqueta → contexto → detalle técnico siempre a un gesto— y un test afirma que el argv **nunca**
  aparece en la primera capa; un tooltip dice qué le pasa al objeto de su fila, en imperativo, y no
  es lugar para un argv.
- [ ] T088 [US7] Implementar `previewEditsStat` (`preview --stat`): es texto, o sea nativa —a
  diferencia de `previewEdits` sin `--stat`, que es un diff y ahí sí gana el difftool del usuario—.
- [ ] T089 [US4] Implementar `tui/internal/host/open.go` con las **cuatro delegadas**:
  `openEntry`/`openChange` → `$EDITOR` con el path **mostrable**;
  `previewEdits`/`compareReview` → `git difftool` → `$PAGER` → `less`, con el color de git. Se lanzan
  con `tea.ExecProcess`, que suspende el programa, le entrega el TTY al hijo y lo recupera al volver,
  **y al volver dispara un refresco** —el revisor pudo haber editado y guardado adentro—: es el
  equivalente en la TUI del `watched: on_save` que el canónico declara para el walkthrough y las
  guías. Un `$EDITOR` con argumentos (`"code -w"`, `"nvim -R"`) se parte con **reglas de shell
  POSIX**, no con un split por espacios: sin eso, `EDITOR="code -w"` busca un ejecutable llamado
  `code -w`. **Gate**: tests con paths con espacio y no-ASCII; un archivo eliminado en el rango **no
  es fatal** y el resultado es informativo; `$EDITOR` ausente o inexistente dice **qué no pasó**, no
  qué comando falló, y esos fallbacks aparecen **sólo** cuando la herramienta muere sin stderr.
- [ ] T090 [US3] Implementar el **mouse**: reporte encendido por default, `MouseMsg` resuelto contra
  la `HitMap` de T047, el control bajo el cursor distinguido del resto, y **una tecla que lo apaga**
  y devuelve la selección nativa por arrastre, con su estado visible en el panel (`mouseEnabled` del
  `PanelModel`, el único campo que no sale de porcelain, FR-067). **Gate**: un clic hace
  **exactamente lo mismo** que su tecla; y en un terminal que no entrega eventos de mouse la TUI
  dibuja los mismos controles **sin mensaje de error ni degradación visible** (US8, escenario 7).
- [ ] T091 [US3] Escribir el test **sólo con el mouse** (SC-015) en
  `tui/internal/ui/reachability_mouse_test.go`: recorrer las situaciones con
  `MouseMsg` sintéticos contra la `HitMap` y afirmar que cada control que la situación **dibuja** se
  activa. **Gate**: sin la `HitMap` habría que adivinar coordenadas; con ella el test es honesto.
- [ ] T092 [US2] Implementar `tui/internal/host/clipboard.go`: **OSC 52**, sin shellear a `pbcopy`,
  `xclip`, `wl-copy` ni `clip.exe` —por SSH y dentro de un multiplexor esas herramientas copian al
  portapapeles de la máquina equivocada o no existen, que es el escenario que la spec pone primero—.
  OSC 52 **no tiene acuse**, así que la degradación no se detecta, se **elige**: el control **nunca
  afirma haber copiado**, su acuse dice lo que sí es verdad, y la línea con el comando queda dibujada
  limpia y seleccionable al lado, junto con el estado del mouse. **El control de copiar y el toggle
  de mouse son la misma conversación**: con el reporte activo el terminal no hace selección nativa
  por arrastre, así que la tecla que apaga el mouse es la que habilita esa línea. **Gate**: un test
  que afirma que ninguna copy dice "Copied" (FR-068). **Cubrir los dos sujetos que se copian**: el
  comando de instalación de la CLI y el `draft_agent_prompt` de `copyDraftPrompt` (ver § Huecos).
- [ ] T093 [US1] Instalar la **mitad simétrica del gate de `reveals: []`** (T004) en
  `scripts/check-client-product-surface.mjs`: `tui/` **no emite** ninguna de las secuencias con las
  que un programa de terminal se trae al frente —BEL (`\a`), OSC 9 y OSC 777, `ESC [5t`— ni shellea a
  `tmux`, `wezterm` o `kitty`. Es una lista corta y nombrable, que es lo que la hace gateable.
  **Gate**: SC-008 en las dos direcciones — agregar un id a `reveals.tui` pide un call site que no
  existe (rojo), y darle al cliente una puerta de revelado dispara el barrido (rojo). Un pane lo
  abriste vos; robarle el foco a alguien en un multiplexor es agresión, no un acuse.
- [ ] T094 [US4] Implementar `showWhy` en `tui/internal/ui/render.go` con el path **crudo** de la entrada y sus estados
  (loading / present / absent / failed), y la nota de un walkthrough **degradado a whole** —un
  walkthrough roto o stale nunca falla una review: degrada con nota y la review sigue usable—.

**Checkpoint**: SC-006 (las 27 clasificadas), SC-015 (teclado y mouse) y SC-008 (`reveals:`) verdes.

---

## Phase 9: El pane real — tamaños, colores y terminales (capa 8b) — [US8]

**Goal**: la misma TUI se comporta bien en un pane de 80×24 y en uno de 120×40, con y sin color, con
y sin dibujo de cajas, en Windows Terminal, conhost con VT, macOS Terminal, iTerm2, tmux, screen y
los terminales de Linux.

**Independent Test**: renderizar el mismo estado a los dos tamaños fijos y comparar contra los
archivos de referencia; repetir con el color apagado y con el fallback ASCII forzado.

- [ ] T095 [US8] Implementar el respeto de **`NO_COLOR`**: sin secuencias de color, y todo legible
  sin ellas. **Gate**: el juego de golden `-nocolor` de T050.
- [ ] T096 [US8] Implementar en `tui/cmd/git-review-ui/main.go` (con el `Viewport` de
  `tui/internal/ui/`) la **decisión de arranque** del juego de glifos: el fallback ASCII lo
  dispara el locale/codepage —`LC_ALL`/`LC_CTYPE`/`LANG` sin UTF-8, o un codepage de consola de
  Windows distinto de 65001—, **no `NO_COLOR`**, que es color y no dibujo. Con un override de
  soporte para forzarlo, que es lo que hace posible el juego de golden `-ascii`. **Gate**: el juego
  `-ascii` de T050 y el test de que **ninguna fila se pierde** al caer al ASCII.
- [ ] T097 [US8] Implementar el **resize en vivo**: `tea.WindowSizeMsg` rehace el layout sin
  corromperlo, y un pane más chico que el mínimo dibujable **degrada a algo legible** en vez de
  romper el layout. **Gate**: tests a los dos tamaños de referencia más uno por debajo del mínimo,
  afirmando que ninguna línea se desborda ni se corta a mitad de columna en 80 columnas.
- [ ] T098 [US8] Afirmar el **terminal restaurado ante un fallo inesperado** (FR-044): sin alt-screen
  colgada ni cursor escondido. Bubble Tea lo hace en su `recover`; el **gate es un test que provoca
  un panic en `Update`** y afirma que el programa salió con el terminal restaurado — no alcanza con
  confiar en la librería.
- [ ] T099 [US8] Afirmar la **alineación de columnas** con iconos: cada fila con icono cae en la
  misma columna, a los dos tamaños y en los dos juegos de glifos. **Gate**: los tests de ancho de
  celda de T027 más los golden — `Ambiguous` no lo detecta ningún ojo humano en la máquina donde se
  escribió.
- [ ] T100 [US8] Implementar la situación de **`cwd` fuera de un repositorio**: error accionable con
  la copy propia de `per_client_strings.no_single_root`, **no una pantalla en blanco**. Es la causa
  alcanzable desde una terminal —donde no hay multi-root— y es por lo que esa copy se declara por
  cliente: el próximo paso está fuera del panel y es distinto (en un IDE, abrir un workspace de una
  sola carpeta; en una terminal, pararse dentro de un repositorio).
- [ ] T101 [US8] Escribir la **matriz smoke multi-SO** en `tui/CONTRIBUTING.md` y en
  [quickstart.md](./quickstart.md) § Matriz smoke, con los ocho casos: CLI vieja → `cli-outdated` y
  no `cli-missing`; path acentuado y con espacio; `start --offline`; un verbo de red con credenciales
  que pedirían prompt → **falla con diagnóstico, no cuelga el pane**; worktree enlazado; Windows con
  la TUI instalada por el one-liner; repo con backend `reftable`; `cwd` fuera de un repositorio.

**Checkpoint**: SC-009, SC-010 y SC-017 verdes; los 66 golden más el frame de espera son la red de
seguridad del layout.

---

## Phase 10: Polish — empaquetado, release y documentación (capa 9)

**Purpose**: publicar. **Sin ningún registro de paquetes de por medio**, así que no hay altas
previas que hacer, ni organizaciones que crear, ni órdenes de publicación que puedan fallar en
silencio (FR-053). Los únicos artefactos son los siete binarios del Release y la fórmula que los
apunta.

- [ ] T102 Crear `tui/bump-version.sh` (POSIX, `set -eu`, `sed_i` por archivo temporal porque GNU y
  BSD difieren en `-i`, sin bashisms y **sin `A && B || C`**), que estampa **dos archivos**:
  `tui/internal/domain/version.go` y la `version` de `Formula/git-review-ui.rb`. Los siete `sha256`
  quedan **a propósito** —desconocidos hasta que existe el asset—, igual que hace `./bump-version.sh`
  con el de la CLI. **Es la simplificación que compra no publicar en ningún registro**: no hay
  `package.json` que mantener alineado ni pines por plataforma que queden atrás de a uno.
- [ ] T103 Agregar `tui/bump-version.sh` a las **dos** listas de `shellcheck`:
  `.github/workflows/ci.yml` (línea 45) y `.github/workflows/release.yml` (línea 40). `find bin -type
  f` cubre el verbo solo; **este archivo no está cubierto por nada** hasta que se lo agrega a las
  dos. **Gate**: `./lint-docker.sh tui/bump-version.sh` limpio.
- [ ] T104 [P] Crear `Formula/git-review-ui.rb`: `on_macos`/`on_linux` × `on_arm`/`on_intel`, cada
  rama con su `url` y su `sha256` apuntando al asset del Release de `tui-v*`; instala el binario en
  `bin` y nada más. **`depends_on "git"` y nada más**: no declara `depends_on
  "git-review-workflow"` aunque la TUI la necesite, porque la CLI llega por cuatro vías y Homebrew
  sólo ve una, y una dependencia dura le instalaría una segunda copia a quien ya la tiene por npm o
  por un one-liner. `cli-missing` no es un error: es una situación de panel completa diseñada para
  este momento exacto. **`Formula/git-review-workflow.rb` no se toca** (FR-050).
- [ ] T105 Crear `.github/workflows/release-tui.yml`, disparado por `tui-v*` —namespace propio: `v*`
  sigue siendo **sólo** la CLI y `jetbrains-v*` sólo el plugin—, con **tres jobs, no cuatro** (no hay
  job de publicación: el Release *es* la publicación): `verify` en los tres SO (`gofmt -l` vacío,
  `go vet`, `go test`, `node scripts/check-client-product-surface.mjs`, **contra el commit
  tageado**); `build` en **un solo runner ubuntu** con los siete targets
  (`CGO_ENABLED=0 -trimpath -ldflags "-s -w"`) empaquetados y su `SHA256SUMS`; y `release` con
  `gh release create "$GITHUB_REF_NAME" --latest=false --generate-notes`, los assets y el fijado de
  los `sha256` de la fórmula en la rama por default con el mismo `sed_i` del workflow de la CLI.
  **`CGO_ENABLED=0` es obligatorio, no una optimización**: es lo que hace que un binario de
  `linux/amd64` funcione en glibc y en musl, y lo que permite compilar los siete desde un runner. La
  versión **no** se inyecta por `-ldflags`: vive en `version.go` para que `version-consistency.bats`
  la pueda leer.
- [ ] T106 Agregar al job `release` de `.github/workflows/release-tui.yml` los **dos asserts previos
  a subir**, que **fallan el release y no lo avisan**: (1) los **siete** archivos existen y no están
  vacíos; (2) el `SHA256SUMS` cubre los siete y cada suma coincide con su archivo. **Gate**: no hay
  orden de publicación que pueda fallar en silencio —el riesgo estructural de la vía descartada—
  porque hay un solo artefacto y un solo paso que lo sube.
- [ ] T107 Verificar `--latest=false` con un test de **SC-013**: un release de la TUI **no altera qué
  ref instalan `web-install.sh` y `web-install.ps1`**, resolviendo `releases/latest` después del tag.
  No es cosmético: los dos instaladores resuelven ese endpoint para elegir el ref **de la CLI**, y un
  release de cliente marcado *latest* haría que el instalador de la CLI se pare en un tag ajeno. Es
  la misma razón exacta por la que `release-jetbrains.yml` lo lleva (líneas 133-134 y 166).
- [ ] T108 [P] Agregar el flag **apagado** a `web-install.sh` —la misma forma que ya tienen `PREFIX`
  y `REF`— y a `web-install.ps1` (`-WithUi`; **`-SkipUi` no existe: no hay nada que saltear**).
  Sin el flag **no se descarga ni se escribe nada** de la TUI: ni una petición a la API, ni un
  archivo, ni una línea de salida distinta de la de hoy (FR-079). **Y no se prompt-ea por él**: el
  proyecto se niega con un hint, no pregunta, y eso vale también para un instalador. El paso de la
  TUI va **después** del de la CLI y **nunca** puede hacer fallar la instalación de la CLI: su fallo
  es una nota, no un `exit`. `web-install.sh` pasa por el mismo `shellcheck` de CI, así que valen las
  reglas de siempre.
- [ ] T109 Implementar en el camino del flag las **tres cosas que el diseño del release impone**:
  (1) **no** resolver `releases/latest` —ese endpoint es de la CLI—, sino listar
  `releases?per_page=100` y quedarse con el primer tag que empieza con `tui-v`; (2) **verificar el
  `sha256`** del asset contra el `SHA256SUMS` publicado en el mismo Release, y **si no coincide, no
  instalar** —un instalador que baja un binario y no lo verifica es peor que no tener esa vía—;
  (3) sin asset para la plataforma, **saltear el paso con una nota** y dejar la CLI instalada igual,
  porque una plataforma fuera de la matriz es una vía degradada, no un usuario bloqueado (FR-081).
- [ ] T110 [P] Hacer que `web-uninstall.sh` y `web-uninstall.ps1` **borren la TUI si está**. Un
  desinstalador que deja mitad de las cosas es otro problema, y ahí no hay sorpresa que evitar.
  **Gate**: `@test` en `tests/web-uninstall.bats` y `tests/web-uninstall-ps1.bats`, en ASCII puro.
- [ ] T111 Escribir el **gate de FR-079** en `tests/web-install.bats`: correr el instalador **sin**
  el flag y afirmar que no quedó ningún archivo de la TUI en el `PREFIX` **y que no se pidió ninguna
  URL de la TUI**. Es la mitad que se rompe en silencio — agregar el paso «por comodidad» no falla
  nada por sí solo. **Y el allowlist de `tests/dispatcher-only.bats` no se relaja** (ver T014).
- [ ] T112 Escribir el test del camino **con** el flag, en un `@test` propio y con su propio
  allowlist: el instalador deja `git-review-ui` en el `PREFIX` **además** de la tríada del
  dispatcher, y `git review-ui` funciona. **No reusar el allowlist de `dispatcher-only.bats`**:
  agregarle `git-review-ui` debilitaría en silencio el guard del camino sin flag.
- [ ] T113 Agregar el bloque de la TUI a `tests/version-consistency.bats`, con `@test` en **ASCII
  puro** y cada uno afirmando **igualdad** y nombrando el archivo que quedó atrás: (1) el `version.go`
  de la TUI es semver pelado; (2) `Formula/git-review-ui.rb` coincide con `version.go`; (3) **no
  existe ningún `package.json` bajo `tui/`** — el gate que impide que la vía descartada vuelva por la
  ventana sin que nadie lo note (FR-049).
- [ ] T114 Subir `min_cli_version.tui` en `contracts/client-product-surface.yaml` a **la versión de
  la CLI que introduce el verbo `ui`**, y llenar `per_client_strings.no_single_root.tui` y
  `per_client_strings.after_install.tui` con la copy propia de T025, en **commits separados e
  independientes** de la Phase 1. **Requiere que esa versión de la CLI exista**: el verbo llega en la
  Phase 2 pero el release `v*` que lo publica es un corte aparte que hoy nadie agenda (ver § Huecos).
  **Gate**: desde este commit los cuatro `min_cli_version` difieren en `main`, que es la primera capa
  del gate de FR-028 — cualquier chequeo que exigiera igualdad estaría rojo en `main`.
- [ ] T115 Actualizar **los DOS README** en el mismo cambio (FR-054): `README.md` y `README.es.md`
  son traducciones espejo, así que el verbo `ui` en la tabla de verbos, el sinónimo `git review-ui`
  en **una línea** —sin pedir disculpas y sin convertirlo en una segunda forma documentada— y las
  vías de instalación de la TUI van en **ambos**. Más la línea sobre montajes de red que menciona el
  piso de poll. **Ninguna de las dos superficies nombra a los otros tres clientes ni dice «paridad
  con X»** (FR-031).
- [ ] T116 Actualizar `docs/index.html` en sus **dos puntas** (FR-055): una caja más en
  `install-grid` (línea ~1183) con su texto en el HTML **en inglés** y su clave en el diccionario
  `ES` del `<script>`, emparejados por `data-i18n` —el patrón que ya usan `nonode` y `thenonce`—. La
  landing es **pitch, no documentación**: no documenta flags ni la tabla de verbos. `docs/.nojekyll`,
  `docs/logo.svg` y `docs/og.png` **no se tocan**: son generados.
- [ ] T117 [P] Escribir `tui/CONTRIBUTING.md` (FR-056): build, test, cómo se regeneran y se revisan
  los golden, la palanca de apagado de la vigilancia, las claves `reviewui.*`, la matriz smoke de
  T101 y el runbook de release. **El README es producto; el desarrollo va acá**, para la raíz y para
  los cuatro clientes.
- [ ] T118 Actualizar `CLAUDE.md`: el cuarto cliente en § Clientes del monorepo, el árbol `tui/`, los
  comandos (`gofmt`/`vet`/`go test`, los golden, el apagado de la vigilancia), la nota de que **la
  paridad es una regla del monorepo y no una promesa al usuario**, y las dos migraciones del
  canónico. Anotar también en § Release el namespace `tui-v*` y el `--latest=false`.
- [ ] T119 Pasar [quickstart.md](./quickstart.md) de punta a punta contra `./tests/sandbox.sh` y
  `./tests/sandbox-min.sh`, en un multiplexor, y marcar SC-001…SC-018 con evidencia. Recorrer la
  **Checklist de pre-release** de
  [contracts/packaging-release.md](./contracts/packaging-release.md): fórmula en la rama por default
  con la `version` estampada y los `sha256` en placeholder; `version-consistency.bats` verde con el
  bloque de la TUI; `tui/bump-version.sh` en las dos listas de `shellcheck`; los dos README y las dos
  puntas de la landing; `tui/CONTRIBUTING.md` escrito.

---

## Dependencies

```text
Phase1 Canónico (capa 1) — primera y SOLA, un commit, value-preserving
  → Phase2 Verbo `ui` (capa 2) [US2 mitad]      ← independiente de todo lo Go
  → Phase3 Foundational: módulo Go + dominio (capa 3)
      → Phase4 Host de lectura + dibujo (capa 4) [US3 lectura, US2 entorno]
          → Phase5 Vigilancia (capa 5) [US1]
          → Phase6 Mutaciones + ciclo de riesgo (capa 6) [US5, US3 cursor]
              → Phase7 El pie y los cinco mapas de fila (capa 7) [US6]
              → Phase8 Overlay, picker, delegadas, mouse, portapapeles (capa 8) [US7, US4, US3, US2, US1]
                  → Phase9 El pane real (capa 8b) [US8]
  → Phase10 Empaquetado, release y documentación (capa 9)
```

- **Phase 2 no depende de Phase 3**: el verbo se niega igual sin que exista un binario, y ésa es la
  mitad de US2 que se entrega primero. Puede ir en paralelo a toda la parte Go.
- **Phase 5 depende de Phase 4, no al revés.** El orden es deliberado: FR-063 —la TUI es
  completamente correcta con la vigilancia apagada— queda probado **antes** de que exista el watcher.
- **Phase 6 depende de Phase 5** sólo por la ventana de silencio del lock (T063), que necesita algo
  que suprimir.
- **T114 depende de un release `v*` de la CLI** que publique el verbo `ui`. Es la única dependencia
  externa a esta feature.

### Parallel opportunities

- **Phase 1**: T005 y T006 son bloques distintos del YAML; el resto toca `min_cli_version`,
  `strings:`/`per_client_strings:` y `reveals:`, que se pisan menos de lo que parece pero entran en
  un solo commit igual.
- **Phase 2**: T012 y T013 en paralelo tras T010.
- **Phase 3**: T019–T021, T023, T025, T027, T028, T029, T031, T032, T033 y T036 son archivos
  distintos y se pueden hacer en paralelo tras T017. T022, T024, T026, T030, T034, T035 y T037 son
  los que atan y van después.
- **Phase 4**: T040 y T041 en paralelo a T038/T039.
- **Phase 6**: T072 y T073 en paralelo tras T063.
- **Phase 10**: T104, T108, T110 y T117 son archivos distintos.

---

## Implementation strategy

1. **El canónico primero y solo.** Un commit, dos archivos, cero valores movidos. Si el diff toca un
   archivo de `vscode-extension/`, `jetbrains-plugin/` o `visualstudio-extension/`, está mal.
2. **El verbo segundo.** Entrega media User Story 2 sin una línea de Go y hace la TUI descubrible
   antes de existir.
3. **Dominio antes que dibujo.** Es lo que los golden, el test de contrato y el verificador leen.
4. **Lectura antes que vigilancia**, para que la vigilancia sea un acelerador y no un cimiento.
5. **MVP interno usable**: Phase 1 + Phase 2 + Phase 3 + Phase 4 (T001–T053). Ahí ya hay un panel que
   vive en un pane, lee las once claves de layout y refresca por foco y por tecla.
6. **Release de paridad**: todas las tareas. No se tagea `tui-v*` hasta que SC-001…SC-018 y los
   gates de CI estén verdes.

---

## Task count

| Phase | Tasks | Capa | Story |
|-------|-------|------|-------|
| 1 — Canónico | T001–T008 | 1 | — |
| 2 — Verbo `ui` | T009–T016 | 2 | US2 |
| 3 — Foundational (Go + dominio) | T017–T037 | 3 | — |
| 4 — Host de lectura y dibujo | T038–T053 | 4 | US3, US2 |
| 5 — Vigilancia | T054–T062 | 5 | US1 |
| 6 — Mutaciones y ciclo de riesgo | T063–T074 | 6 | US5, US3 |
| 7 — El pie y los cinco mapas de fila | T075–T083 | 7 | US6 |
| 8 — Overlay, picker, delegadas, mouse | T084–T094 | 8 | US7, US4, US3, US2, US1 |
| 9 — El pane real | T095–T101 | 8b | US8 |
| 10 — Empaquetado, release y docs | T102–T119 | 9 | — |
| **Total** | **119** | | |

---

## Notes

- **Lo que NO se toca, y hay que decirlo en voz alta**: el pin de `bats@1.13.0` en sus **cuatro**
  lugares (los tres runners de CI, `release.yml` y `tests/Dockerfile`) — el job nuevo es Go y
  `tests/ui.bats` corre con el bats que ya está; `Formula/git-review-workflow.rb`;
  `.github/workflows/release.yml` (`v*` sigue siendo sólo la CLI); el `package.json` de la CLI, que
  conserva **cero dependencias** y **no gana ninguna mención de la TUI**; lo que instalar la CLI deja
  en la máquina; y `docs/.nojekyll`, `docs/logo.svg`, `docs/og.png`, que son generados.
- **Ninguna tarea de npm, de altas de publicación, de organizaciones en un registro ni de paquetes
  por plataforma.** Esa vía fue descartada entera y el motivo está en [research.md](./research.md)
  § Decisión 14: `bin` en un `package.json` mapea a **un** archivo, así que un paquete con varios
  binarios necesita un shim JavaScript — o sea **Node para correr un binario estático de Go**, la
  dependencia de runtime que motivó elegir el lenguaje.
- Los `@test` de bats van en **ASCII puro**: bats convierte cada nombre en un nombre de función shell
  escapando byte por byte y el bats de Windows en CI trastabilla con los bytes UTF-8.
  `tests/test-names.bats` lo verifica sobre toda la suite.
- El verbo y `tui/bump-version.sh` son **shell POSIX puro** con `set -eu`, sin bashisms y **sin
  `A && B || C`** (SC2015 falla en Ubuntu y en Windows en CI): el `if` invertido es la forma.
- Todo lo que se puede correr en el contenedor se corre en el contenedor: `./lint-docker.sh` y
  `./tests/run-docker.sh`. El job `tui` es la excepción — Go corre nativo.

---

## Huecos entre la spec y el plan, detectados al desglosar

Ninguno bloquea el desglose; los cinco están cubiertos por una tarea, pero conviene decidirlos antes
de empezar la fase donde muerden.

1. ~~**`GIT_REVIEW_UI` significaba dos cosas**~~ — **resuelto en los artefactos** (T009). Era el
   único hueco con modo de falla observable: el verbo la lee como ruta al ejecutable y el instalador
   la usaba como flag opt-in `=1`, así que dejar el flag exportado hacía que `git review ui`
   intentara `exec 1`. El flag del instalador pasó a llamarse **`GIT_REVIEW_WITH_UI=1`**; la ruta
   conserva `GIT_REVIEW_UI` porque es una ruta a un programa —la convención de `GIT_EDITOR` y
   `GIT_PAGER`— y porque está en la spec a nivel de requisito. T009 quedó como los dos `@test` que
   impiden que los nombres se vuelvan a unificar.
2. **Nadie agenda el release `v*` de la CLI que publica el verbo `ui`** (T114). El paso final del
   canónico sube `min_cli_version.tui` a "la versión que introduce el verbo", y esa versión tiene que
   existir: hace falta un corte de CLI entre la Phase 2 y el primer `tui-v*`.
3. **`inventory_controls:` no está en la tabla de
   [contracts/tui-surface.md](./contracts/tui-surface.md) § 7** (T080), que enumera cuatro mapas de
   fila (`draft_controls`, `guide_rows`, `fixes_rows`, `walkthrough_row`) y se saltea el quinto, que
   sí existe en el canónico con `continueReview` y `discardInventory`. FR-020 dice "tres mapas"; el
   canónico tiene cinco.
4. **SC-002 no tiene gate declarado en ningún contrato** (T061). El registro de invocaciones lo hace
   *medible*, pero ninguno de los cinco contratos nombra un test que lo afirme — y "cero procesos por
   minuto en reposo" es el número que separa este cliente de un `watch`.
5. **La degradación del portapapeles está diseñada para un solo sujeto** (T092). Los contratos
   resuelven OSC 52 para el comando de instalación, pero `copyDraftPrompt` también copia —el
   `draft_agent_prompt` del canónico— y tmux le pone tope de tamaño al payload de OSC 52. La regla de
   "nunca afirma haber copiado" aplica igual, pero el segundo sujeto no está escrito en ningún lado.
