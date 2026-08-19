# CLAUDE.md

## Qué es esto

Una suite de verbos de `git review` (shell POSIX) para revisar un pull request **editándolo y
ejecutándolo**. Todo cuelga del dispatcher `git review <verbo>`, al estilo de `git bisect`/
`git stash`. `git review start` materializa el diff completo del PR como cambios *staged y sin
commitear* sobre una rama
`review/<branch>` cuyo `HEAD` queda en el merge-base; editás/ejecutás en tu working tree y después
`git review finish` extrae *tus* ediciones a una rama aparte `review-fixes/<branch>`. Ver
`README.md` para la superficie completa de comandos.

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

**Todo lo que se puede correr en el contenedor se corre en el contenedor.** No es preferencia: en
Windows crear un proceso cuesta ~50 ms (CreateProcess + DLLs

+ Defender) contra ~1 ms en Linux, y las dos suites son básicamente procesos — un
  `git review status --porcelain` son 9 procesos `git` más dos de shell, o sea
  ~960 ms en Windows contra ~41 ms en Linux. Un mismo escenario de spec midió 15,0 s nativo contra
  0,69 s en el contenedor (~22×). CI igual corre las dos suites en runners reales de ubuntu, macos y
  windows, así que el contenedor no saltea nada: lo único que evita es esperar de más para aprender
  lo mismo. Cada script construye su imagen en el primer uso.

La imagen de Docker (bats + git, `tests/Dockerfile`) se construye en el primer uso y el repo se
monta read-only; los tests crean sus repos temporales dentro del contenedor. Los tests del
instalador de PowerShell (`*-ps1.bats`) necesitan
`pwsh`, que no está en el contenedor, así que solo corren de verdad en CI / en Windows local. CI
corre shellcheck + bats en runners reales de **ubuntu, macos y windows** en cada push y PR. **bats
está pinneado a una única versión**
(`npm install -g bats@1.13.0`) en los tres runners, en `release.yml` y en
`tests/Dockerfile`: antes cada OS lo instalaba de una fuente distinta (`apt` /
`brew` / `npm`) con versiones distintas, y un flag que andaba en la más nueva abortaba la suite en
la vieja de apt — un fallo que sólo aparecía en CI. Si subís la versión, subila en los cuatro
lugares a la vez. **shellcheck** sigue viniendo de tres fuentes distintas (`apt` / `brew` /
`choco`), así que ahí sí vale apuntar al mínimo común denominador.

## Arquitectura

- **`bin/git-review`** — el dispatcher, el **único** ejecutable que va al `PATH`
  (`git` lo descubre como `git review`). Rutea `git review <verbo> [args]` al ejecutable del verbo:
  resuelve su propia ubicación real (siguiendo symlinks), exporta `GIT_REVIEW_LIBEXEC=<su dir>`,
  hace `shift` y `exec`utea
  `git-review-verbs/<verbo>`. `-h`/sin args lista los verbos; `--version`/`-V`
  imprime la versión. Un verbo inexistente da `error:` a stderr (exit ≠ 0).
- **`bin/git-review-verbs/*`** — un ejecutable de shell POSIX por verbo (sin extensión; `chmod +x`),
  `prog="git review <verbo>"`. Son **privados**: no van al `PATH` ni se llaman `git-*`, así que
  `git` no los descubre como
  `git <verbo>`; el único punto de entrada es el dispatcher. Los que usan helpers compartidos
  sourcean `"${GIT_REVIEW_LIBEXEC:?}/git-review-lib.sh"`.
- **`bin/git-review-lib.sh`** — se *sourcea, nunca se ejecuta*. Tiene los helpers compartidos por
  los verbos de modo `--step` (`show_commit`,
  `load_step_review_meta`, `goto_step`). Los verbos lo sourcean vía
  `"${GIT_REVIEW_LIBEXEC:?}/git-review-lib.sh"` (el dispatcher exporta esa var con su dir real
  resuelto). Como solo define funciones, sourcearlo no tiene efectos secundarios. Es **libexec**:
  vive junto al dispatcher y los verbos, nunca en el
  `PATH` (symlink/copia según el instalador; ver `install.sh` / Homebrew /
  `web-install`).

### Modelo de estado — dónde vive el estado del review

Las sesiones de review son stateful y guardan todo en los datos de git del repo, no en archivos del
working tree:

- **Ramas:** `review/<branch>` (review activo), `review-fixes/<branch>`
  (ediciones extraídas), `review-saved/<branch>` (review pausado).
- **Config por rama** (`branch.review/<x>.review*`): `reviewmode`,
  `reviewsource`, `reviewtip`, `reviewstart`, `reviewcount`, `reviewstep` — llevan el modo y la
  posición en `--step`. Se leen defensivamente (`|| true`)
  porque con `set -eu` una clave borrada a mano abortaría el script en silencio.
- **Modo walk** (`reviewmode = walk`): un walkthrough (sidecar
  `.review/walkthrough.md`, committeado al PR por el autor con `git review
  walkthrough init/build`) convierte el `start` en un cursor de lectura sobre la review completa. El
  formato tiene tres piezas: el **preámbulo** (`## Heads-up`, todo lo previo a la primera entrada —
  `build` lo preserva verbatim menos los comentarios HTML, y `start`/`compare` lo imprimen una vez
  al entrar), las **entradas** (`## N. <path>` + el why) y el marcador reservado **`> key`** (línea
  suelta al tope del body: presencia = entrada esencial, ausencia = default; se filtra del why y se
  muestra como `(key)`). Los marcadores reservados van todos como líneas `> ...` al inicio del
  body — ver también el `> at: ` de v2. El cursor vive en claves **propias** — `reviewwalkstep`
  (1-based), `reviewwalkcount` (guard) y `reviewwalkbase` (el lower bound al que
  `start`/`compare` clavaron `HEAD`) — nunca en `reviewstart/reviewcount/
  reviewstep`: el guard de metadata de `finish` aborta si esas claves de step existen sin
  `reviewmode=step` (y hay un guard espejo para claves walk sin
  `reviewmode=walk`). `reviewwalkbase` es lo que permite **preguntarle a git** si
  `HEAD` se movió (`walk_at_base`) en vez de inferirlo de que la secuencia se achicó: con el
  borrador del revisor esa inferencia tiene dos causas y elegía la equivocada. Sin la clave (reviews
  viejas) se cae a la inferencia de antes. La secuencia de entradas NO se persiste: se re-deriva en
  cada verbo parseando el walkthrough del tip y filtrando por intersección de paths con el rango
  real, igual que step re-deriva `commits` con `rev-list`. En walk `HEAD` queda clavado en el lower
  bound, así que la derivación es estable aunque el usuario edite. Walk no banca refs (las ediciones
  viven en el working tree, como whole); el cursor muere con la rama. **Toda comparación de paths
  entre el walkthrough y git pasa por dos puntos únicos de normalización, y solo por ahí:**
  `walk_normalize` (bytes del sidecar — CR final y BOM UTF-8) y
  `changed_paths` (lado git — `core.quotePath=false`, más el trim de whitespace en
  `walk_parse`/`walk_body`). Si agregás una superficie nueva donde un path de git se compara contra
  uno escrito a mano, hacela pasar por esas dos: cada byte invisible que se cuela produce el mismo
  síntoma — el mismo archivo listado a los dos lados del error de drift, o la entrada desapareciendo
  del orden de lectura en silencio. Un walkthrough roto/stale nunca falla una review: degrada a
  whole con nota.
- **Borrador del revisor** (`git review walkthrough draft`): el otro lado del walkthrough. Cuando el
  PR no trae uno, el revisor se escribe el suyo en
  `<gitdir>/review-walkthrough/<src>.md` — **fuera del árbol versionado**, así que no se commitea,
  no se stagea y `git status` no cambia en ningún momento. Mismo formato que el sidecar y misma
  validación (`draft --build` reusa el cuerpo de `build`, sin duplicar una sola regla). La
  precedencia se resuelve en un único punto, `walk_read`: si hay borrador **en vigor** para el
  `<src>` del contexto —fijado por `walk_use_draft` desde los dos cargadores de metadata, de modo
  que todo verbo con review activa lo herede—, gana sobre el sidecar del tip; si no, el sidecar como
  siempre. Las trece funciones de walk y los verbos que cuelgan de ellas no se enteran. **«En vigor»
  y «el archivo existe» son dos preguntas distintas y hay una función para cada una:**
  `walk_draft_body` (la regla, un único lugar) responde la primera —un borrador vacío o de puro
  whitespace no es un orden de lectura y se comporta como ausente, si no tapaba el walkthrough del
  autor en silencio— y la usa `walk_is_draft`, que es el `(draft)`
  de `status`; `walk_has_draft_file` responde la segunda, que es custodia, y la usan `list`, las
  ofertas de `config --porcelain` y los mensajes de `start` sobre un borrador propio vacío. Si
  mezclás las dos, o `status` dice `walk (draft)`
  sobre la prosa del autor, o `forget --saved` se lleva un archivo que nadie listó. **Bajo qué
  nombre vive el borrador de una review se decide una sola vez y se persiste**
  (`branch.review/<x>.reviewdraft`, escrita por `start`/`compare`
  al crear la review, en **todos los modos** y exista o no un borrador todavía). No siempre es el
  `reviewsource` —un `compare develop origin/feature/x` es la review de `origin/feature/x` y el
  borrador es de `feature/x`, porque el borrador es de la *rama*, no del ref con el que la
  nombraste—: la única derivación de ese nombre está en `compare` y de ahí sale a la clave. **Nadie
  lo vuelve a derivar**, todos lo leen con `walk_review_draft_src` (los dos cargadores, `list`,
  `save`, `continue`, `forget`, `walkthrough draft`); cuando el escritor y el lector lo derivaban
  por su cuenta, discrepaban en silencio: el borrador escrito desde adentro del compare se guardaba
  bajo `origin/feature/x`
  y el `start` siguiente leía el orden del autor sin decir nada. Que además se escriba siempre —y no
  sólo cuando hay borrador— es lo que hace que el escrito **a mitad de review** caiga donde se lo va
  a buscar, y lo que le da nombre al archivo en modo `whole`/`step`, donde no hay orden de lectura
  pero sí custodia. Aparte va **un flag**, `reviewwalkfromdraft = 1`, que dice que el orden que se
  está caminando salió de ese borrador: es la única cosa que no se puede recalcular una vez que el
  archivo no está, y es lo que le permite a
  `walk_range_error` distinguir «borraste tu borrador» de «commiteaste encima de la review» incluso
  si el PR trae walkthrough propio y la review cae sobre él. Ese sí es una clave walk como las demás
  (la copian `save`/`continue` y la cubre el guard de metadata de `finish`); `reviewdraft` **no**,
  justamente porque existe en todos los modos. Y el borrador en vigor no se lee nunca de la config:
  es el que el cargador dejó en `walk_draft_src`, de donde lo toman también
  `walk_recover_cursor` y `walk_range_error` —volver a `git config` en esas dos las dejaba ciegas
  justo en el caso que existen para cubrir, el borrador escrito a mitad de review, y el revisor
  recibía «corrupt metadata» con `git review
  abort` como única salida—. `walk_range_error` adopta ese fallback sólo si
  `walk_is_draft` confirma que hay borrador en vigor: sin esa condición, toda review sin borrador
  parecería una a la que se le borró el suyo, y un commit encima de la review contestaría «tu
  borrador desapareció» en vez del mensaje de HEAD. Ciclo de vida: `save` lo archiva en
  `review-saved-walkthrough/` (y `continue` lo devuelve) **como último paso, después de la última
  guarda que puede abortar** — un movimiento a mitad de camino dejaba el archivo sin dueño de los
  dos lados—, y
  `continue` **nunca pisa** un borrador vivo: si escribiste uno con la review pausada, se niega con
  las dos salidas (`forget --draft` o `forget --saved`) en vez de elegir por vos cuál de las dos
  prosas escritas a mano sobrevive. `save`
  hace lo mismo del otro lado, con la guarda temprano y el `mv` último: dos reviews pueden querer el
  mismo archivo (un `start feature/x` y un `compare
  develop origin/feature/x` archivan los dos bajo `feature/x`), así que si el destino ya está
  ocupado se niega cuando una review pausada lo reclama y avisa cuando reemplaza uno que nadie puede
  reclamar. La guarda cuelga de que **esta**
  review tenga un borrador que archivar, con el mismo test de archivo que hace el
  `mv`: sin archivo no hay `mv` y no hay nada que proteger, y negarse igual dejaba la rama sin poder
  pausarse por prosa ajena que el `save` no iba a tocar — justo el caso ordinario, porque el
  archivado suele estar ahí *porque* una review anterior de esa misma rama se guardó con su
  borrador. **Quién reclama un archivado se le pregunta a las reviews pausadas (
  `walk_saved_draft_claims`), nunca al nombre del archivo:** `review-saved/<archivo>` no existe
  justamente para las reviews que necesitan la pregunta —el archivado de
  `review-saved/origin/feature/x` se llama `feature/x`—, y las tres superficies que decidían por el
  nombre mentían o borraban prosa viva: `forget --draft --all` barría el borrador de una review
  pausada anunciando que no quedaba review que lo reclamara, `save` lo pisaba callado, y
  `walkthrough draft` anunciaba una review pausada inexistente sobre un archivado huérfano, mandando
  a un `continue` que no se podía correr. **Y una review que no archivó nada no reclama nada**
  (`walk_saved_draft_filed`, sobre
  `branch.<saved>.reviewdraftfiled`, que `save` escribe en los dos sentidos —la ausencia de la clave
  significa «pausada antes de que existiera», y sin el `0`
  toda review sin borrador volvía a ese bucket): dos reviews pausadas de una misma rama comparten el
  nombre del archivado y sólo la segunda lo escribió, así que
  `continue` sobre la primera se llevaba prosa ajena —dejando a la que sí la había escrito negándose
  a retomar sobre «un borrador escrito con la review pausada» que era el suyo, movido—,
  `forget --saved` la borraba y `list` le ponía `(draft)`
  a una fila que no iba a volver con ninguno. El borrador viaja con la review **en cualquier modo**,
  no sólo en walk, así que las filas de `list` llevan `(draft)` también en `step` y `whole`: si sólo
  lo marcara en walk, un `forget --saved` se llevaría prosa que ninguna superficie llegó a mostrar.
  `clean` **no lo toca nunca**: es prosa escrita a mano que sobrevive a la review (arrancá la rama
  de nuevo y tu orden sigue ahí), así que va con los otros dos estados persistentes que `clean` deja
  quietos —los marcadores de `--delta` y las reviews guardadas— y se descarta con
  `git review forget --draft <rama> | --all`
  (`--saved` se lleva el de la review pausada; `--all` barre además los archivados que ya no tiene
  quién reclamar —su `review-saved/<rama>` se borró a mano—, que si no quedan fuera del alcance de
  todos los comandos: `--saved`
  exige el ref, `--draft` sólo deletrea nombres del namespace activo y `clean` es hands-off en los
  dos). Su presencia se reporta —nunca se infiere— con el registro `draft` de `status --porcelain` y
  el sufijo `(draft)`
  en `status` y `list`; la viabilidad de armarlo o continuarlo, con las ofertas
  `draft` / `draft-resume` de `config --porcelain`. Las superficies de custodia se deciden con un
  test de archivo y cero procesos nuevos; el gitdir del que cuelgan todos esos paths se resuelve
  **una vez por proceso** en `walk_gitdir_init`, llamado desde `walk_use_draft` (todo verbo con
  review activa) y a mano por los cuatro que arman un path sin fijar contexto — `list`, `save`,
  `continue` y
  `forget` —, porque un `$(...)` no puede cachear nada.
- **Bloque de instrucciones** (`<!-- git-review-range: … -->`): la pieza que hace que el borrador se
  pueda completar sin mirar el PR. La escribe el generador de esqueleto —el mismo para `init` y para
  `draft`, `walk_emit_prompt_block`— justo debajo de `# Walkthrough`, y nombra el rango en **objetos
  resueltos** (SHA del tip; OID del lower bound con su tipo, `commit` o `tree`), la situación del
  árbol de trabajo, los flags con los que se generó y cuatro comandos para ver el contenido real. Se
  **regenera** en cada reescritura, con el rango que esa corrida acaba de validar (`walk_prompt_block`
  se come el entrante para que no se duplique ni se cuele al preámbulo): un bloque arrastrado
  sobrevive al cambio del rango y la deriva no lo ve si el conjunto de paths no cambió. Se filtra al
  leer sin código nuevo —`walk_preamble` ya descarta todo comentario— y es **neutro** para las ocho
  reglas de validación, así que borrarlo a mano es legal. **Dos prohibiciones duras en su contenido,
  las dos medidas**: nunca `<lower>..<tip>` como un solo argumento (en Windows con cwd profundo `git
  diff` hace `stat()` del argumento y muere con `Filename too long`, con extremos de cualquier tipo)
  y nunca `git log` / `rev-list` / `shortlog` / `range-diff` (con un `lower` de tipo tree imprimen la
  historia entera del repo con exit 0, en silencio). La línea `Generated with:` es la **única casa**
  de los flags de origen y rango: de ahí los lee el registro `draft` de `config --porcelain` y con
  ellos el panel replica el `--build` y el `start` — con los defaults, cualquier borrador hecho con
  `--delta`, `--local` u `--offline` fallaría **siempre** por deriva.
- **El circuito con un agente** (`--stdout` / `--build --from`): las dos puntas que dejan que algo
  que no es el revisor complete el orden de lectura **sin escribir en el gitdir**. `--stdout` emite
  el esqueleto por la salida estándar y no toca nada —ni `mkdir`, ni temporal, ni traps, ni `mv`—,
  manda todas las notas a stderr, y conmuta la línea de cierre del andamiaje para que nombre
  `--build --from <file>`: sin esa conmutación el esqueleto le indica al agente un comando que, si
  esa rama ya tenía borrador, **valida y reescribe ese otro archivo** con exit 0 y mensaje de éxito.
  `--build --from <file>|-` lee el contenido de afuera (por `walk_normalize`, que un agente en
  PowerShell produce CRLF y BOM), lo valida con las **mismas ocho reglas** y lo instala. El orden de
  las guardas es normativo: la existencia del borrador previo se decide **antes** de leer la fuente,
  porque negarse después de consumir stdin deja al llamador sin forma de reintentar; y la única
  escritura sigue siendo el `mv` final, así que todo rechazo deja el borrador anterior byte por byte.
- **Los tres registros porcelain del borrador:** `config --porcelain` emite un `draft<TAB><src><TAB>
  <path><TAB><annotated><TAB><total><TAB><source><TAB><range>` por cada borrador del namespace
  **activo**, con y sin argumento de rama (un borrador es un hecho del working tree, no de la rama
  consultada); `status --porcelain` le suma la ruta absoluta a su registro `draft` de presencia; y
  `list --porcelain` gana `branch-draft<TAB><branch>` detrás de cada fila `branch` que carga uno, con
  la misma condición de custodia que el `(draft)` legible y por un único helper para que las dos no
  puedan divergir. El progreso lo cuenta `walk_draft_progress` con **un solo `awk`** sobre todos los
  archivos a la vez; con cero borradores `emit_draft_records` corta **antes** de invocarlo, porque
  `awk` sin argumentos de archivo lee la entrada estándar y se cuelga — y este verbo corre en cada
  refresco del panel.
- **Refs de ediciones:** `refs/review-edits/<src>/<step>` bancan las ediciones de cada commit en
  `--step` como objetos commit-tree; `git review save` los mueve a `refs/review-saved-edits/` para
  que `git review clean` (que poda
  `refs/review-edits/`) nunca toque un review guardado.
- **Marcadores `--delta`:** las claves de config `reviewworkflow.<src>.reviewed`
  registran el último tip revisado. Una review **completada** (finish con
  `reviewundoouthead`) los conserva a través de `git review clean`; un start abandonado (clean/abort
  sin finish exitoso) los revierte como abort. Para borrarlos a mano: `git review forget --delta`.
- **Entradas de config:** `reviewworkflow.base` (dónde se integran los PRs — sin default, un review
  completo falla sin él) y `reviewworkflow.remote` (default
  `origin`). Ambas son claves `git config` por repo, por diseño.

## Convenciones

- **Espejar los idioms de git.** Es el principio rector del proyecto: preferir diseños consistentes
  con git nativo (omitir el arg para la rama actual, `--`
  para terminar el parseo de opciones, riesgo asimétrico en los verbos destructivos) antes que
  inventar comandos nuevos.
- **Hay DOS README y siempre se actualizan los dos.** `README.md` (inglés) y
  `README.es.md` (español) son traducciones espejo. Cualquier cambio de comportamiento (flags,
  superficie de comandos, tabla de verbos, ejemplos)
  tiene que reflejarse en *ambos* en el mismo cambio — nunca tocar solo uno.
- **La landing (`docs/index.html`) es pitch, no documentación.** Es la página de GitHub Pages. A
  propósito **no** documenta flags ni la tabla de verbos: para eso linkea a los README, así no hay
  una tercera superficie de docs que mantener sincronizada. Pero sí duplica cuatro cosas puntuales,
  y solo esas hay que revisarlas cuando el cambio las toca:
    1. la **tabla comparativa** (la de la landing es un recorte de 4 filas de la de los README);
    2. los **métodos de instalación** (npm / Homebrew / PowerShell / one-liner);
    3. los **comandos que aparecen en los ejemplos** — `start`, `next`, `finish`,
       `walkthrough init|build`, `reviewworkflow.base`;
    4. el **formato del walkthrough** que muestra el demo interactivo (el
       `## Heads-up`, `## N. <path>` + el *why*, y el badge `key`).

  Si tu cambio no toca nada de eso, la landing no se toca.
- **La landing es bilingüe en un solo archivo.** El inglés vive en el HTML (para que lo indexen los
  crawlers) y el español en el diccionario `ES` del `<script>`, emparejados por `data-i18n`. Si
  editás un texto con `data-i18n`, editá las dos puntas — igual que con los README. La vista mobile
  del cuadro comparativo se **genera desde la propia `<table>`** en JS, así que agregar una fila o
  una columna a la tabla ya se propaga sola: no la dupliques a mano.
- **Ante una duda genuina, preguntá.** Si hay una decisión de diseño o una ambigüedad real que no se
  resuelve leyendo el código, preguntarle al usuario suele ser más certero y económico que explorar
  a ciegas o adivinar y rehacer.
- **Los documentos de trabajo se escriben en español.** Todo lo que se redacte para este repo
  —specs, planes, checklists, análisis, notas de diseño— va en español, con la ortografía completa
  (acentos, `ñ`, `¿`/`¡`). Cuando se parte de una plantilla en inglés (p. ej. las de
  `.specify/templates/`), la plantilla **se deja como está** y sólo se escribe en español lo que uno
  completa: los encabezados y comentarios en inglés se conservan verbatim, porque los comandos de
  Spec Kit localizan las secciones por su nombre y traducirlos los rompe. Esto no aplica al
  *producto*: el código, los mensajes de los comandos, `README.md` y los nombres de los `@test`
  siguen sus propias reglas (ver los dos README y la regla de nombres ASCII más abajo).
- **Solo shell POSIX (`sh`)**, con `set -eu` arriba de cada script. Nada de bashisms — los comandos
  deben correr bajo `dash`/Git Bash. El repo también trae *instaladores* de PowerShell
  (`web-install.ps1`) y un paquete npm, pero los comandos en sí son POSIX.
- **`sed` multiplataforma:** GNU y BSD difieren en `-i`; hacé las ediciones in-place a través de un
  archivo temporal (ver `sed_i` en `bump-version.sh`).
- **Nada de `A && B || C` como if-then-else.** shellcheck lo marca con SC2015 (falla en Ubuntu y
  Windows en CI) porque `C` también corre si `B` falla, no solo si `A` es falso. Para guardas de
  validación usá un `if` explícito con la condición invertida:
  `if [ $# -eq 0 ] || [ -z "$1" ]; then die "..."; fi` en vez de
  `[ $# -gt 0 ] && [ -n "$1" ] || die "..."`. El idiom `A || C` a secas (sin `&&`) sí está
  permitido — no dispara SC2015.
- **Tests con asserts fuertes, sin falsos positivos.** Cada `@test` de bats debe fallar de verdad
  cuando el comportamiento se rompe. En concreto:
    - Afirmá el `status` esperado *además* de la salida (`[ "$status" -eq 0 ]` / el código de error
      que corresponda). Nunca dejes pasar un test solo porque el comando no abortó.
    - Para verificar contenido preferí igualdad o aserciones específicas (`[ "$output" = "..." ]`)
      antes que `grep`/globs laxos que matchean de más; si usás `[[ "$output" == *"x"* ]]`, que el
      patrón sea único y significativo.
    - Verificá el **efecto real** sobre el estado de git (ramas/refs/config/working tree), no solo
      el texto impreso.
    - Para los casos de error, afirmá el exit code *y* el mensaje en `stderr`, y confirmá que el
      efecto colateral NO ocurrió.
    - Nada de tests tautológicos (que pasan pase lo que pase) ni asserts comentados.
    - **Nombres de `@test` en ASCII puro.** Nada de em dashes (`—`), acentos ni otros caracteres
      no-ASCII en el texto del nombre. bats convierte cada nombre en un nombre de función shell
      escapando byte por byte, y el bats de Windows en CI trastabilla con los bytes UTF-8 →
      `unknown test name '...\342-80-94...'`
      (pasa en Linux/macOS, rompe en Windows). El cuerpo del test puede tener lo que sea; es solo el
      nombre el que se vuelve nombre de función.
      `tests/test-names.bats` lo verifica sobre toda la suite, así que la regla se rompe en
      cualquier OS en un segundo y no recién en el runner de Windows.

## Clientes del monorepo (VS Code + IntelliJ + Visual Studio)

La CLI es la única fuente de verdad. Hay tres UIs de cliente en el monorepo:

- **`vscode-extension/`** — extensión VS Code (TypeScript + esbuild).
- **`jetbrains-plugin/`** — plugin JetBrains IDE / IntelliJ Platform (Kotlin + Gradle Platform
  Plugin). Un zip para IDEA, WebStorm, PhpStorm, PyCharm, GoLand, CLion, RubyMine, RustRover,
  DataGrip, etc.; **no** Android Studio ni Rider (`<incompatible-with>` en `plugin.xml`).
- **`visualstudio-extension/`** — extensión Visual Studio (C# / .NET 8, VSIX).

Los tres leen solo porcelain/argv de la CLI; el canónico anti-drift multi-cliente vive en **
`contracts/client-product-surface.yaml`** (raíz). Incluye la matriz de 27 acciones, el bloque **
`panel_layout:`** (disposición del panel por situación) y el bloque **`listing:`**
(la copy de las tres tiendas). CI lo verifica con
`node scripts/check-client-product-surface.mjs`
(min_cli_version, npm, strings críticos, 27 acciones vs `package.json` de la extensión, las seis
comprobaciones de layout vs `panelHtml.ts`, y los mismos escalares contra los archivos de dominio de
`visualstudio-extension/`).

**Una divergencia deliberada se declara en el contrato, no en el cliente.** `not_in:
[<cliente>]` en una acción dice que ese cliente no la ofrece, y el check lo verifica en las **dos**
direcciones: el cliente listado no puede declararla en ninguna de sus superficies (panel, menú,
`ActionArgv`) y los demás la siguen teniendo. Hoy hay una sola: **`openAllChanges` no existe en
Visual Studio.** Ese host difiere con `IVsDifferenceService`, que abre una ventana de comparación
por *par de archivos* y no tiene equivalente del multi-diff de VS Code (`vscode.changes`) ni de la
`DiffRequestChain` de IntelliJ, así que el mismo botón abría una ventana por archivo cambiado — y
un tope sobre eso sigue siendo una avalancha. El inventario de archivos del panel abre cada diff de
a uno, que es el mismo rango en la única forma que ese host puede darlo bien. Reponer la acción sin
tocar el contrato falla CI, que es exactamente lo que se quiere: la ausencia no se lee como drift,
y volver atrás obliga a discutir el motivo primero.

**De la ficha de cada tienda se comparte la copy corta, no el cuerpo.** El
`listing:` del contrato fija dos cosas y CI las verifica en las tres puntas: el **tagline** (la
línea que va bajo el nombre en los resultados de búsqueda — byte por byte igual en
`package.json` de VS Code, la primera oración del `<description>` de `plugin.xml` y la del
`<Description>` del vsixmanifest más `marketplace/overview.md`) y los **keywords**, que se comparan
como conjunto normalizado porque cada tienda los escribe distinto (`pull-request` en npm,
`pull request` en el vsixmanifest). El **cuerpo** de la ficha no se comparte y no se verifica: cada
tienda toma un artefacto distinto —VS Code renderiza el `README.md` empaquetado, JetBrains el
`<description>` del descriptor, Visual Studio el `overview.md` que se pega a mano en el portal—, así
que decir lo mismo ahí es trabajo de revisión, no de check. Del lado JetBrains hay además un guard
concreto: `build.gradle.kts` **no** debe setear `pluginConfiguration.description`, porque pisa el
`plugin.xml` al empaquetar con una copia que ningún test mira — así fue como la ficha publicada
siguió diciendo «paridad con la extensión de VS Code» después de que existiera el cliente de Visual
Studio. Del lado IntelliJ, `PanelLayoutContractTest` compara
`panelLayout(fixture)` contra el mismo YAML en cada `./gradlew test`; del lado Visual Studio,
`PanelLayoutContractTests` (xUnit) hace lo mismo en cada `dotnet test`.

### Plugin de JetBrains IDE (IntelliJ Platform)

`jetbrains-plugin/` es un módulo Gradle aparte (JDK 21; pin de platform en
`jetbrains-plugin/gradle.properties` — **única** fuente de since-build/versión; mínimo **2026.1** /
branch **261**, sin techo de `until-build`). La compatibilidad multi-producto sale de `plugin.xml`
(`platform` + `Git4Idea`, más `incompatible-with` para Android Studio y Rider), no de un enum de
productos en el Marketplace. Dominio puro en
`com.ezevillo.gitreview.domain` (sin `com.intellij`); host/UI invocan la CLI con
`GeneralCommandLine` UTF-8.

```sh
# Desde jetbrains-plugin/ (el wrapper Gradle vive ahí, no en la raíz del monorepo):
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
`git -C <sandbox>/work review start feature/checkout` → `./gradlew runIde` → abrir solo
`<sandbox>/work` → setting **Tools → git review → Path to git-review** al `bin/git-review` del
checkout si hace falta → tool window **git review** + menú **Tools → git review**. Detalle en
`CONTRIBUTING.md`
(sección *The JetBrains IDE plugin*) y `specs/009-plugin-intellij/quickstart.md`.

**UX:** paridad de producto (CLI + matriz de acciones/situaciones + disposición del panel), no de
píxeles. El panel es Swing nativo a propósito (no CEF/HTML del webview de VS Code):
`domain/PanelLayout.kt` proyecta el modelo y
`ui/PanelRenderer.kt` lo dibuja. Comparar lado a lado con
`./gradlew runPanelPreview` vs `npm run preview` en la extensión. La extensión y la CLI siguen yendo
al contenedor Docker en Windows; el plugin se prueba con Gradle nativo (y `platformTest` en el
runner Linux de CI).

**El icono sí es compartido** — es la identidad del producto, no píxeles del panel. Los cuatro SVG
del plugin (`META-INF/pluginIcon.svg` + `_dark`,
`icons/gitReviewToolWindow.svg` + `_dark`) **no se editan a mano: los genera
`_build_icon.py`** con la misma geometría que los de la extensión (ver *Assets del logo*). Lo único
propio de IntelliJ son los tamaños que exige —40×40 el del Marketplace, 16×16 el de la stripe— y
**el color** del mono: el `#C5C5C5` de la extensión es el gris de tema oscuro de VS Code, y IntelliJ
parchea de claro a oscuro pero nunca al revés, así que sin cambiarlo se lava en tema claro. La
plataforma deriva sola el hermano `_dark`, y **si falta no falla nada: dibuja un placeholder**; por
eso `ToolWindowIconTest` ata las tres puntas: lo que pide el
`plugin.xml`, lo que hay en `resources/`, y la geometría contra el archivo de la extensión forma por
forma.

### Extensión de Visual Studio (C# / .NET)

`visualstudio-extension/` es una solución .NET 8 aparte (`GitReview.sln`), mismo split de capas que
JetBrains: **`GitReview.Domain`** (C# puro, sin referencias a `Microsoft.VisualStudio.*`, port
mecánico del `domain/` de JetBrains), **`GitReview.Host`** (invocador de la CLI, refresh de estado,
lock de mutación) y **`GitReview.VS`** (VSIX — WPF `PanelView` renderiza
`PanelLayout` con el mismo orden y las mismas etiquetas en inglés que JetBrains/VS Code; solo los
colores siguen el tema del host).

```powershell
cd visualstudio-extension
dotnet build GitReview.sln
dotnet test tests/GitReview.Domain.Tests
dotnet run --project src/GitReview.VS -- --verify    # smoke de layout/constantes
dotnet run --project src/GitReview.VS -- --preview   # todas las situaciones, navegable

./build-vsix.ps1                          # arma el .vsix (Release, net472)
./build-vsix.ps1 -Install -Experimental   # lo instala en la hive Exp
devenv /rootsuffix Exp                    # y lo levanta ahí
```

**El VSIX es net472 y lo arma MSBuild, no `dotnet build`.** `devenv.exe.config` declara
`supportedRuntime sku=".NETFramework,Version=v4.7.2"`: Visual Studio es un proceso .NET Framework y
una extensión que carga in-proc —y todo assembly que esa extensión arrastre— tiene que serlo
también. Por eso `-p:GitReviewPackVsix=true` **agrega** net472 al lado de net8.0 en Domain, Host y
GitReview.VS; sin el flag los tres quedan single-target y `dotnet build`/`test`/`run` no necesitan
`-f`. Las tareas del VSSDK son tareas de .NET Framework, así que el build del VSIX va por el
MSBuild de la instalación de Visual Studio (`build-vsix.ps1` lo encuentra con `vswhere`); el SDK en
sí sale de NuGet, no hace falta el workload. Lo que el BCL viejo no tiene se rellena en
`src/Compat/` (`IsExternalInit`, `Index`/`Range`) y en un `StringCompat`/`DictionaryCompat` por
assembly, declarados en el namespace que los usa para que ningún llamador necesite un `using`
nuevo; las APIs de proceso que sólo existen en .NET Core pasan por `ProcessCompat`, **el único
archivo con `#if` del árbol** — si aparece otra incompatibilidad, va un shim ahí, no un `#if` en el
dominio. Y como net472 está apagado por defecto, lo que sólo rompe ahí no rompe `dotnet build`:
`./build-vsix.ps1` es el gate, y lo corre el job `visualstudio-extension` de CI — en
`windows-latest` y sólo ahí, porque es el único runner con el MSBuild de Visual Studio; los otros
tres pasos del job son `dotnet build` / `dotnet test` / `--verify`. La **instancia experimental**
(`/rootsuffix Exp`, una hive de registro aparte) es el equivalente del Extension Development Host
de VS Code y del `runIde` de Gradle; sin `-Experimental` se instala en la real, que es el mismo
camino que hace un usuario con un `.vsix` de disco.

**Las cinco acciones de la barra de título no las dibuja el panel: las dibuja el shell.**
En VS Code son `menus/view/title` y en IntelliJ `setTitleActions`; el equivalente de
Visual Studio es una **`ToolWindowToolbar`**, o sea que viven en el `.vsct` y no en
WPF, y eso las reparte en tres archivos que tienen que coincidir: el `.vsct` declara
los botones (con `IconIsMoniker` y un moniker del Image Catalog, para que el icono
siga el tema y el escalado del host), `GitReviewPackage` mapea cada command id al
`ControlId` y contesta el `QueryStatus`, y `GitReviewToolWindow` nombra la toolbar en
`ToolBar` **desde el constructor** (el shell la lee al crear el frame, igual que
`Content`). Cuál de las cinco se ve en cada momento no se decide ahí: los botones son
`DefaultInvisible` + `DynamicVisibility` y el `QueryStatus` lee
`PanelLayout.TitleActions`, la misma proyección del dominio que arma el cuerpo del
panel — reimplementar las condiciones en el host sería la segunda copia de la matriz.
Dos cosas que no avisan si faltan: `PanelView.ShowTitleActions = false` (si no, los
mismos cinco botones aparecen dos veces, arriba como iconos y adentro como texto), y
el `IVsUIShell.UpdateCommandUI` que dispara `TitleActionsChanged` — una command bar
sólo se re-consulta cuando alguien se lo pide, así que sin eso la toolbar se queda con
los botones de la situación anterior. Las tres puntas las ata
`scripts/check-client-product-surface.mjs` contra el `title_actions:` del contrato: un
botón que perdió el `<Icon>` dibuja un hueco y un id que dejó de coincidir con su
`IDSymbol` es un botón que no hace nada, y ninguna de las dos rompe el build.

**Los botones del panel los dibuja `PanelButtons`, no WPF.** El `ControlTemplate` de fábrica pinta
hover, pressed y disabled desde triggers que viven **adentro** del template y apuntan a su propio
`Border`, así que le ganan a cualquier `Background` que el panel le asigne al botón: un *Continue*
deshabilitado salía con el relleno de Windows (`#F4F4F4`) y una etiqueta `#838383` encima —o sea un
bloque blanco ilegible sobre el tema oscuro— y un file row en hover destellaba el celeste del
sistema en lugar del `RowHover` del chrome. Por eso el template es propio (un `Border` pintado desde
el `Background` del botón) y los cuatro estados salen de `PanelChrome`. La regla que hace que eso
funcione: un trigger de `Style` **pierde** contra un valor local, así que los botones `Primary` /
`Secondary` no pueden asignar `Background`/`Foreground` en la instancia — los traen los setters del
`Style`. `Bare` es el caso opuesto a propósito (file rows y toggles se pintan solos). El gate es
`--verify`, que renderiza el panel de verdad y compara el fill y el texto de los botones
deshabilitados contra el chrome; una asignación local vuelve a fallar `buttons:disabled-fill`.

**Instalar el `.vsix` son tres pasos, no uno, y los tres los da el script.** `VSIXInstaller` deja la
hive en un estado que parece bien y no lo está, de dos maneras que no avisan: instalar una versión
que ya está es un **no-op silencioso** (sale 0 y no toca nada — y en desarrollo la versión es la
misma en cada build, así que la hive sigue sirviendo el assembly anterior y el panel muestra código
viejo sin una sola señal), y cada reinstalación **desempaqueta en una carpeta nueva** mientras la
configuración mergeada de la hive sigue apuntando a la anterior — que el uninstall acaba de
borrar — con lo que Visual Studio ya no falla en silencio sino que **no carga el paquete**
(diálogo *GitReviewPackage no se cargó correctamente*, `FileNotFoundException` en
`ActivityLog.xml`). Por eso `-Install` desinstala primero, corre
`devenv /updateconfiguration` después, y al final **verifica contra el disco** que todo
`GitReview.VS.dll` de la hive sea el recién compilado. F5 desde la IDE no tiene nada de esto: es el
loop corto.

`bin/`/`obj/` de los cuatro proyectos van al `.gitignore` raíz (`visualstudio-extension/**/bin/`,
`**/obj/`) — nunca se commitean. Versión propia, independiente de la CLI y de los otros clientes:
`./visualstudio-extension/bump-version.sh X.Y.Z` estampa
`GitReview.VS.csproj`, `source.extension.vsixmanifest` y
`Directory.Build.props` a la vez (cubierto por `tests/version-consistency.bats`).

## Extensión de VS Code

`vscode-extension/` es un proyecto npm aparte (TypeScript + esbuild), con su propio job en CI. Nunca
deriva estado por su cuenta: todo lo que muestra sale de reinvocar `git review status --porcelain` /
`--why` sobre la CLI del `PATH`, así que hay que tener este checkout instalado (`./install.sh`) para
**correrla** en un editor de verdad. Los tests no: `runTests.ts` pone el `bin/` del checkout al
frente del PATH que hereda el host, así que el fixture y la extensión bajo test corren siempre la
CLI de este árbol. El diseño completo está en `specs/002-extension-vscode/`
(`contracts/cli-invocation.md` es la lista cerrada de lo que puede invocar). Su
`README.md` es único y va en **inglés** (es producto, no documento de trabajo):
la regla de los dos README es de los README de la raíz, no de éste.

Ese `README.md` y el `CHANGELOG.md` de al lado **viajan dentro del `.vsix`**: son las pestañas
*Details* y *Changelog* del listado del Marketplace, así que están escritos para quien instala la
extensión, no para quien la desarrolla — eso vive en `vscode-extension/CONTRIBUTING.md` (excluido
del paquete por `.vscodeignore`, junto con `src/`, `test/` y `preview/`). Dos cosas que se rompen
fácil ahí: los **links tienen que ser absolutos**, porque `vsce` reescribe los relativos contra la
raíz del repo ignorando el `repository.directory` del `package.json` (un
`../README.md` termina como `.../blob/HEAD/../README.md`, roto), y la superficie que el README
describe —acciones del panel, settings, versión mínima de la CLI— tiene que seguir a `contributes`
del `package.json`.

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

- **Editor de pruebas:** abrir `vscode-extension/` en VS Code y F5 (config *Run Extension* de
  `.vscode/launch.json`) levanta un **Extension Development Host**
  con la extensión cargada desde el checkout; los cambios entran con *Developer:
  Reload Window* en esa ventana, no reiniciándola. El panel sólo tiene algo que mostrar dentro de un
  repo con review activo: armá uno con `./tests/sandbox.sh`, arrancá el review
  (`git -C <sandbox>/work review start feature/checkout` entra en walk, porque el sandbox commitea
  un walkthrough) y abrí `<sandbox>/work` en el host. Ojo: el host hereda el `PATH` del VS Code que
  lo lanzó, no el que arma el `env.sh` del sandbox — o instalás el checkout, o apuntás la setting
  `gitReview.path` a `bin/git-review`.
- **La suite de integración va en el contenedor**, misma regla que bats: los 70 tests tardan 38 s
  adentro contra 16 minutos nativos en Windows (26×), y pasan los mismos 70. El script
  (`vscode-extension/test/run-docker.sh` + `test/Dockerfile` + `entrypoint.sh`)
  monta el repo read-only, lo copia a `/work` porque `npm install` escribe, y cachea `node_modules`,
  el VS Code descargado y el cache de npm en volúmenes nombrados (`grv-vscode-*`) — sólo la primera
  corrida los paga. Tres cosas de ahí adentro que no son obvias: corre como el usuario `node` y no
  como root, porque Electron se niega a arrancar como root sin `--no-sandbox` y ese flag saldría de
  `runTests.ts`, o sea del árbol; hace `chmod +x` sobre `bin/`, porque el bind mount desde Windows
  puede aplanar el bit ejecutable y sin él todo fixture muere con un `is not a git command` que no
  dice nada; y la imagen fija **`VSCODE_CLI=1`**, sin lo cual VS Code resuelve el entorno de un
  login shell y pisa con él el `PATH` que `runTests.ts` preparó — la extensión no encuentra la CLI y
  los 70 tests fallan con `cli-missing`.
- **`test:integration` corre contra `dist/`** y lo recompila solo (`pretest:integration`), así que
  lo verde siempre es el código actual.
- **Dos specs de integración abren tabs y son flaky en Windows** por el host de test, no por la
  extensión. Correr en el contenedor las saca del medio; si aun así ves un `no se abrió ningún tab`
  en el runner de Windows, medí el baseline en un checkout sin tocar antes de buscar la causa en tu
  cambio.
- **El `--user-data-dir` del host va a un temp corto, no al default de test-electron**
  (`test/integration/helpers/userDataDir.ts`). VS Code arma el socket IPC de su main como
  `<user-data-dir>/<version>-main.sock`, y en POSIX ese path no puede pasar de `sun_path` (103 chars
  en macOS, 107 en Linux): con el default `<extensionRoot>/.vscode-test/user-data`, el checkout del
  runner de GitHub —que repite el nombre del repo— se iba a 113 y el editor moría con
  `EINVAL` antes de correr un test. Fallaba sólo en macOS, pero no por margen:
  el mismo path mide 112 en Linux y ubuntu zafa porque VS Code prefiere
  `XDG_RUNTIME_DIR` cuando existe (Windows usa named pipes, sin límite). O sea que un contenedor
  Linux sin esa variable y con el checkout en un path largo reproduce el fallo de macOS. Si tocás
  esos args, el flag tiene que ir como
  `--user-data-dir=<dir>`: con un espacio, `hasArg` de test-electron no lo ve y reinyecta el default
  largo. `test/unit/userDataDir.spec.ts` cubre las dos cosas contra `darwin` explícito, así que la
  regresión cae en cualquier SO.
- **`npm run preview`** genera `out/preview/index.html` (y lo imprime como URL
  `file://`): los dieciocho estados del panel lado a lado, a ancho de sidebar, con selector de tema
  dark/light/alto contraste. El pane es el `panelHtml()` real y los estados de `preview/fixtures.ts`
  son salida `--porcelain` de ejemplo pasada por el parser y el modelo reales, así que **sigue al
  código y no se mantiene aparte**. Lo que no puede afirmar: los botones no tienen extensión del
  otro lado; las variables de tema de `preview/build.ts` son una aproximación — si el panel empieza
  a usar una `--vscode-*` que no está en esa lista, agregarla es parte del cambio; y el pane
  `loading` es ese estado congelado — su temporización (el umbral antes del esqueleto, el techo de
  un `--why` lento)
  sólo ocurre navegando. Para comportamiento, F5.

## Assets del logo

**`assets/logo.svg` es el maestro** — vector puro, `viewBox="0 0 128 128"` y **sin `width`/
`height`**, para que escale a cualquier tamaño. Todo lo demás sale del mismo generador,
`vscode-extension/media/_build_icon.py`, que en una corrida escribe los PNG y SVG de la extensión,
el maestro, `docs/logo.svg` (el favicon de la landing), los cuatro SVG del plugin de IntelliJ y los
PNG/SVG de
`visualstudio-extension/media/` + `src/GitReview.VS/Resources/` (VSIX, tamaños 90/128/256).
**Ninguno se edita a mano:
se cambia el generador y se regenera** (`python
vscode-extension/media/_build_icon.py`) — los comentarios que le pongas a un SVG los borra la
próxima corrida, y los `_preview-*.png` que deja al lado son hojas de control, están gitignoreadas.

`docs/logo.svg` es byte por byte igual al maestro y existe sólo porque Pages publica **únicamente
`/docs`**: la landing no puede referenciar `../assets/`.
`npm run check:logo-assets` (`scripts/check-logo-assets.mjs`, en CI junto al check del contrato
multi-cliente) verifica el contrato entero: el maestro sin tamaño fijo y sin raster embebido, su
geometría contra `media/icon.svg`, la copia de `docs/` idéntica al maestro, que la landing la use de
favicon, y los 40×40 / 16×16 que exige JetBrains.

## Landing (GitHub Pages)

`docs/index.html` se publica en GitHub Pages desde la rama `main`, carpeta
`/docs` (Settings → Pages → *Deploy from a branch*). **No hay build ni workflow**: es un HTML
estático autocontenido, así que cada push a `main` que toque `docs/` lo republica solo en un par de
minutos. Para previsualizarlo, abrilo directo en el navegador — no necesita servidor.

- `docs/.nojekyll` evita que Pages lo pase por Jekyll.
- `docs/logo.svg` es el favicon: copia generada del maestro (ver *Assets del logo*), nunca a mano.
- `docs/og.png` es la preview de los links (copia de `demo-poster.png`); las URLs de `og:image` y
  `canonical` están hardcodeadas a
  `ezevillo.github.io/git-review-workflow/` — si algún día se le pone dominio propio, hay que tocar
  esas líneas del `<head>` (y agregar un `docs/CNAME`).
- `docs/` **no** está en `files` de `package.json`, así que no viaja en el tarball de npm ni infla
  el paquete.

## Release

La versión de la **CLI** está duplicada a propósito: `VERSION`, `bin/git-review` y
`package.json` viajan dentro del tarball (npm publica la versión de
`package.json`); `Formula/git-review-workflow.rb` apunta al tarball.
`./bump-version.sh X.Y.Z` estampa los tres desde un solo argumento (deja a propósito el `sha256` de
la fórmula —desconocido hasta que existe el tarball del tag; el workflow de release lo fija). Los
releases se cortan pusheando un tag
`v*`: el workflow crea el GitHub Release, fija la fórmula y publica a npm vía Trusted Publishing
(OIDC, sin `NPM_TOKEN`: el repo está registrado como trusted publisher en npmjs.com).

Los clientes versionan **aparte** de la CLI y entre sí, con el mismo patrón de un comando que
estampa todos los sitios que deben coincidir:

- `./vscode-extension/bump-version.sh X.Y.Z` — `package.json` + las entradas propias del paquete en
  `package-lock.json`
- `./jetbrains-plugin/bump-version.sh X.Y.Z` — `pluginVersion` en
  `gradle.properties` (Gradle parchea `plugin.xml` al build)
- `./visualstudio-extension/bump-version.sh X.Y.Z` — `<Version>` en
  `GitReview.VS.csproj`, `Identity Version=` en `source.extension.vsixmanifest`
  y `GitReviewClientVersion` en `Directory.Build.props`

Los headings del CHANGELOG de cada cliente se escriben a mano. Un
`tests/version-consistency.bats` protege contra el drift de la CLI y de los tres clientes.

**El CHANGELOG del plugin de JetBrains no es sólo documentación: es lo que se publica.** La sección
de la versión que se está sacando se renderiza a HTML y va al `<change-notes>` del descriptor
(plugin `org.jetbrains.changelog` + `changeNotes` en `build.gradle.kts`), que es la pestaña *What's
New* del Marketplace y el diálogo que el IDE muestra antes de actualizar — la misma sección que
`release-jetbrains.yml` ya usaba para el cuerpo del GitHub Release. Es decir: el heading
`## [X.Y.Z]` se escribe a mano **antes** de tagear, o el release publica notas vacías (cae a un link
al CHANGELOG, que es un piso, no la intención). El check del contrato falla si `changeNotes`
desaparece del `build.gradle.kts`.

**El plugin de JetBrains tiene su propio namespace de tags y su propio workflow**
(`release-jetbrains.yml`): un `jetbrains-v*` lo publica al Marketplace (`publishPlugin`, con el
secret `JETBRAINS_MARKETPLACE_TOKEN`), mientras que `v*` sigue siendo sólo la CLI. El trigger es un
tag y no un push con `paths:` porque el Marketplace rechaza una versión que ya tiene: «cambió el
plugin» sólo es publicable cuando cambió `pluginVersion`, y el tag lo dice explícito (el workflow
aborta si los dos no coinciden). Dos cosas de ahí que no son obvias: el Release de GitHub que crea
va con **`--latest=false`** — los dos
`web-install` resuelven `releases/latest` para elegir el ref de la CLI, así que un release del
plugin marcado latest le haría instalar un `jetbrains-v*` — y las notas salen del CHANGELOG del
plugin y no de `--generate-notes`, que listaría todos los commits de la CLI desde el tag anterior de
la historia compartida. El
`cache: gradle` del job `jetbrains-plugin` de `ci.yml` no está ahí para ese job:
los caches de Actions tienen scope por rama y un tag no es la default branch, así que lo único que
el release puede restaurar es lo que ese job escribió en el último push a `main` — sin eso cada
release rebaja un IDE por producto verificado.
