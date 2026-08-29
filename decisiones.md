# Decisiones de diseño

Por qué cada cosa de este repo es como es: el bug que la motivó, la alternativa que se descartó y
lo que cuesta. Nada de acá hace falta para trabajar en el proyecto — las reglas vinculantes están
en `CLAUDE.md`, los comandos en los `CONTRIBUTING.md` y el rationale por función en los comentarios
del propio código, que es donde se lee justo cuando lo vas a romper.

Esto es el otro archivo: la memoria de las decisiones que ningún comentario alcanza a contar
porque cruzan varios archivos, o porque lo que explican es una ausencia. Se lee bajo demanda,
cuando estás por cambiar algo de acá y querés saber qué se rompió la última vez.

---

## 1. Por qué todo corre en el contenedor

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

---

## 2. Modo walk: el cursor de lectura

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

---

## 3. El borrador del revisor

La pieza más grande del modelo de estado, y la que más veces se rompió en silencio. Casi todo lo
que sigue existe porque una superficie decidió por su cuenta algo que otra ya había decidido.

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
  `git review forget --draft <rama> | --all | --reviewed`
  (`--saved` se lleva el de la review pausada; `--all` barre además los archivados que ya no tiene
  quién reclamar —su `review-saved/<rama>` se borró a mano—, que si no quedan fuera del alcance de
  todos los comandos: `--saved`
  exige el ref, `--draft` sólo deletrea nombres del namespace activo y `clean` es hands-off en los
  dos). Su presencia se reporta —nunca se infiere— con el registro `draft` de `status --porcelain` y
  el sufijo `(draft)`
  en `status` y `list`; la viabilidad de armarlo, continuarlo o ponerlo al día, con las ofertas
  `draft` / `draft-resume` / `draft-update` de `config --porcelain`. Las superficies de custodia se
  deciden con un
  **`draft` actualiza en vez de negarse**, en los mismos términos que `init` y con el mismo
  código: cada entrada cuyo archivo sigue en rango conserva número, why y `> key`, los que
  entraron llegan como `## ?.` y los que salieron se descartan nombrados. El motivo es otro que
  el de `init` —un borrador no se puede desfasar *durante* una review, porque `start` congela el
  tip, pero sobrevive a esa review y la siguiente es sobre un rango que se movió—, y hay dos
  asimetrías deliberadas: **`superseded` es sólo de `init`** (empezar de cero por decisión propia
  destruye prosa, y del lado del autor eso es un `git checkout` porque el archivo está trackeado;
  del lado del revisor no hay vuelta atrás — y no llega a pasar, porque una rama ya mergeada en la
  base no tiene rango y `annotatable_files` muere antes), y **el aviso de las entradas
  descartadas no nombra una salida** en el lado del revisor, por lo mismo: ahí la nota que lista
  los paths es todo lo que hay.

  **Y lo que se descarta lo decide el PR, no el rango en vigor.** Son dos preguntas distintas y
  el update las hace por separado: el rango en vigor (`lower`) dice qué entradas tienen que
  estar —lo que este `draft` está escribiendo— y el rango del PR (`pr_lower`, el merge-base con
  la base) dice cuáles puede haber. Difieren en un solo caso, `--delta`, y ahí conflatearlas era
  destructivo: la entrada de un archivo que el PR cambia en un commit que ya leíste caía fuera
  del rango y se descartaba, o sea que un flag que se lee como una lente —«mostrame sólo lo
  nuevo»— borraba prosa escrita a mano sobre código que sigue en el PR, y como el borrador vive
  fuera de git no hay `git checkout` que la traiga. Con las dos preguntas separadas, `--delta`
  angosta lo que la review **lee** (`walk_sequence` ya filtraba por intersección de paths, así
  que un borrador del PR entero se lee en una review delta sin tocar el archivo) y nunca lo que
  el borrador puede **contener**. La misma asimetría del otro lado: `missing` se mide contra el
  rango en vigor y `extra` contra el PR, si no un borrador completo se volvía imposible de
  buildear apenas le apuntabas `--delta`. Y el aviso de stderr recupera su verdad —«the PR no
  longer changes these files» sólo sale cuando eso es cierto—, que era lo otro que estaba mal:
  la única señal antes de perder el texto afirmaba algo falso. Cuesta **un `merge-base` de más y
  sólo bajo `--delta`**; con los dos bounds iguales no se computa nada.

  **Que su review ya haya terminado no lo borra: lo baja de bloque.** El registro `draft` de
  `config --porcelain` cierra con un `<state>` —`fresh` o `reviewed`— que compara el tip del
  **propio borrador** (el `tip <sha>` de su bloque de instrucciones) contra el marcador de la
  última review completa de esa rama, en el sabor que corresponda (`reviewworkflow` para uno
  remoto, `reviewworkflowlocal` para uno `--local`/`--offline`; cruzarlos reportaba un borrador
  como leído porque se revisó la *otra* copia). El tip del **borrador** y no el de la rama hoy,
  porque lo que se pregunta es si *ese orden de lectura* ya se leyó: uno regenerado después de la
  review cubre un rango que nadie leyó y vuelve a `fresh`, y uno cuya rama avanzó sigue
  describiendo lo que sí se leyó, así que sigue `reviewed` —que además esté derivado es otra
  pregunta, y la contesta `build`—. Cuesta **un `git config --get-regexp` para
  todos** —los marcadores se leen una vez y cada fila se contesta con un `case` builtin—, y a
  propósito **no** consulta las reviews vivas: `start` escribe el marcador antes de correr la
  review, así que un borrador que una review está leyendo reporta `reviewed`, y contestarlo bien
  costaría un `for-each-ref` más un `git config` por review en cada refresco. La pregunta sí se
  hace donde es gratis: `forget --draft --reviewed` —la escoba de los que no podés nombrar, porque
  un borrador se deletrea por su rama— **saltea** el que una review walk está leyendo y lo dice.
  Del lado del panel, un `reviewed` sale de *Reading orders you started* y baja a una sección
  plegada del pie con los dos iconos y sin el par con etiqueta: escribir el orden y arrancar la
  review ya pasaron las dos. Plegada y no escondida, porque un archivo que existe y ninguna
  superficie nombra es justo lo que este panel no deja pasar en ningún otro lado. Y un orden que
  **no está escrito entero nunca es `reviewed`**, vaya donde vaya el marcador: sin esa condición,
  un *Start over* sobre una rama que no se movió cae en el mismo tip que el marcador registra y el
  esqueleto en blanco recién pedido quedaba plegado abajo, sin *Copy for agent* ni *Validate and
  start* — o sea sin forma de avanzar. Es el mismo test de `filled` que ya usan los tres paneles y
  cuesta cero, porque el par lo cuenta el `awk` que leyó el archivo.

  **Cuál de las dos ofertas del borrador sale es otra pregunta, y la contesta el mismo verbo.**
  `draft-resume` y `draft-update` son excluyentes y las decide `emit_reading_offers`, no el
  cliente: lo que las separa es si el orden **sigue cubriendo el rango**, y eso necesita el tip
  contra el que se escribió el borrador —`walk_sidecar_block_tip`, cero procesos sobre el archivo
  que `walk_use_draft` ya ubicó— y el de hoy. El `state` del registro `draft` **no** sirve de
  sustituto: contesta «¿ya se leyó este orden?», a propósito, así que una rama que avanzó después
  de su review sigue diciendo `reviewed`. Tres casos y sólo dos filas: **desfasado** →
  `draft-update`; **al día y a medio escribir** → `draft-resume`; **al día y completo** → ninguna,
  porque `walk` ya lo lee y no queda nada que reconciliar ni que terminar. Ese último es el único
  que cuesta un proceso (el `awk` del progreso) y se paga tarde, después de que la pregunta barata
  dijo «al día»; el `_ero_walk == 0` que lo acompaña no es adorno, es la red: un borrador completo
  cuyos paths ya no tocan el rango deja `walk` sin ofrecer, y callarse ahí sería un orden de
  lectura sin ninguna superficie que lo alcance.

  **Del lado del cliente eso es una cosa menos.** El asistente no pregunta nada: dibuja la oferta
  que llegó y la invoca. Hubo un modal *Update* / *Start over* sobre cualquier borrador cuya review
  ya había cerrado —el molde del picker de `walkthrough init` del autor— y se retiró junto con el
  paso `START_OVER` de `DraftStep`, porque preguntaba justamente lo que el cliente no podía saber:
  con el rango quieto, *Update* era un no-op que devolvía al revisor a una fila `reviewed`, o sea
  plegada abajo, sin *Copy for agent* y sin *Validate and start* — un paso del asistente cuyo único
  desenlace era un callejón. Empezar de cero **no se repone ahí**: del lado del autor el archivo
  está trackeado y `git checkout --` lo devuelve, del lado del revisor vive fuera de git y no hay
  vuelta atrás, así que es de Discard —que confirma y cuyo sujeto es el archivo— o de
  `walkthrough draft --force` en la terminal, nunca de un botón al paso.
  test de archivo y cero procesos nuevos; el gitdir del que cuelgan todos esos paths se resuelve
  **una vez por proceso** en `walk_gitdir_init`, llamado desde `walk_use_draft` (todo verbo con
  review activa) y a mano por los cuatro que arman un path sin fijar contexto — `list`, `save`,
  `continue` y
  `forget` —, porque un `$(...)` no puede cachear nada.

---

## 4. El bloque de instrucciones

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

---

## 5. El circuito con un agente

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

---

## 6. Que el panel se entere solo

- **Que el panel se entere solo** (el otro lado del circuito): llenar un borrador es lo único que
  cambia lo que el panel muestra sin pasar por git ni por una mutación del cliente — se escribe en
  el gitdir, o sea que no mueve `HEAD`, no toca el índice y no escribe `config`. Ninguna de las
  señales de refresco de los tres clientes lo veía, así que el progreso quedaba clavado hasta que
  alguien apretaba Refresh, justo mientras el revisor mira el panel para saber si el agente terminó.
  Los tres vigilan ahora los directorios de las rutas que la CLI **ya reportó** (`draftWatchDirs` en
  VS Code y JetBrains, `DraftWatch.WatchDirs` en Visual Studio; un único punto por cliente sobre los
  registros `draft` de `config`/`status --porcelain`), nunca un path rearmado del layout del gitdir
  — la misma regla que hace que *Open draft* abra la ruta que dio la CLI en vez de derivarla.
  Consecuencia deliberada: un borrador cuya carpeta no aparece todavía en ningún reporte (el creado
  a mano en una terminal) no tiene quién lo mire hasta el refresco siguiente — por eso **el cliente
  que crea el borrador refresca él mismo**, dentro del lock y pase lo que pase, igual que después
  de un `start`: el primero de una rama estrena su carpeta, así que ninguna señal lo ve y sin ese
  refresco la fila no aparecía hasta que algo ajeno tocara el repo. En Visual Studio sale gratis
  (`MutationRunner` refresca tras cada invocación) y en JetBrains lo hace el cierre del wizard; en
  VS Code va en `invokeDraft`, que es donde el asistente corre el verbo. El watcher es de cada
  host — `createFileSystemWatcher` no recursivo, watch roots planos más `VFS_CHANGES`, un
  `FileSystemWatcher` por directorio —, y **el conjunto sólo se rehace cuando cambia**: rehacerlo en
  cada refresco pierde justo los eventos que llegan mientras se rehace. En IntelliJ además es lazy,
  como el resto de ese cliente: un borrador que crece con el panel oculto se lee cuando la tool
  window vuelve, no antes.

  **Y lo que el verbo dijo se muestra: el resultado está en stdout, no en stderr.** Los verbos de
  este proyecto imprimen su resultado por **stdout** y reservan stderr para errores y notas
  (`start`, `finish`, `forget`… todos), así que un camino que sólo lee stderr en verde se queda sin
  la única frase que contesta qué pasó. En el borrador eso se nota más que en ningún lado porque el
  asistente cierra sin arrancar nada: un update dice «N kept, M added, K dropped» y sin eso apretar
  la oferta no producía señal ninguna —o peor, en una rama sin guía de autoría aparecía la nota de
  la guía, un consejo que no tenía que ver con lo que se acababa de apretar—. `draftOutcomeMessage`
  / `draftOutcomeText` / `DraftOutcomeText` (uno por cliente, en el módulo puro de cada uno) aplanan
  **cada tramo por separado** y recién después los unen, para que el separador quede entre el
  resultado y la nota y no adentro de ninguno. Sólo en verde: un fallo sigue siendo el stderr solo,
  que es donde la CLI lo escribió. El resto de las invocaciones del panel (build, start, forget) no
  cambian —ahí el efecto se ve en el panel y en verde no hay nada que decir—, y por eso el arreglo
  vive en el camino del asistente y no en un `flatten` compartido.

  Del lado de la CLI, el mismo mensaje **no promete entradas que no existen**: `fill in the new
  entries` sale sólo con `added > 0`. Un update que no agrega ninguna es un resultado legítimo —el
  rango se movió sin cambiar qué archivos toca, y el bloque de instrucciones se acaba de reescribir
  contra el tip nuevo—, pero mandar al revisor a llenar un placeholder que no está es mandarlo a
  buscar algo que no va a encontrar.

---

## 7. Las dos guías de autoría

- **Las dos guías de autoría** (`git review walkthrough guide`): prosa sobre el **contenido** del
  walkthrough —qué entradas merecen `> key`, cómo se escribe un porqué, qué va en el heads-up—, no
  sobre su formato. Son dos y contestan preguntas distintas: la **compartida**
  (`.review/walkthrough-guide.md`, committeada) dice cómo *este proyecto* quiere que se anoten sus
  PRs, y la **propia** (`<git-common-dir>/review-walkthrough-guide.md`) cómo *vos* anotás. La
  segunda está en el gitdir por las mismas tres paredes que el borrador del revisor: no aparece en
  `git status`, no se stagea ni se commitea, y `finish` no se la puede llevar a `review-fixes/` —
  cosa que haría, porque la extracción es `git add -A`, e intentar crear la compartida adentro de
  una review se niega justamente por eso. **`--git-common-dir`, nunca `--git-dir`:** un worktree
  enlazado comparte la común, y una guía es del repositorio y no del worktree donde estás parado;
  con el gitdir del worktree tenés una guía distinta por worktree, que no es algo que a nadie se le
  ocurra ir a buscar. Y va **plana**, fuera de `review-walkthrough/`: `walk_draft_list` recursa ese
  directorio y toma todo `*.md` como el `<src>` de una rama, así que una guía ahí adentro aparecería
  como un borrador fantasma en `list`, en `forget --draft --all` y en el conteo de progreso.
  **Aplican las dos si las dos tienen contenido, y la tuya gana ante contradicción** —la misma
  precedencia que `walk_read` ya aplica entre tu borrador y el sidecar del autor—; el orden en vigor
  se declara **en el esqueleto**, y ahí hay **dos formas y no una**: escribiendo un archivo van los
  **paths** (el esqueleto aterriza al lado de las guías, y una copia embebida en algo que sobrevive
  a la corrida se pondría vieja sin que nadie mire), y con `--stdout` va el **contenido inlineado**
  (ese esqueleto viaja por un pipe, y el path absoluto de un gitdir no es algo que el agente del
  otro lado pueda abrir — apuntarle a un archivo que no alcanza falla en silencio, porque nada
  verifica que lo leyó). Inlinear no rompe la promesa de `--stdout`, que es sobre no **escribir**.
  Dos cosas que el inlineado le hace a la prosa, las dos a propósito: reescribe `-->` como `-- >`
  (el bloque **es** un comentario HTML, así que uno literal lo cerraría antes de tiempo y volcaría
  el resto al preámbulo — la misma clase de byte invisible que el CR y el BOM) y corta a las **120
  líneas**, para que una guía enorme no se coma el contexto del agente; la cerca nombra el path, que
  es donde está el resto. La nota de stderr la emite `emit_guide_note`, y la llaman `init`, `draft`
  **y `build`**: build no es decoración ahí, es el verbo que hace cumplir la regla que una guía más
  suele llevar —«marcá pocas key»— porque el aviso que salta cuando están todas marcadas es el
  suyo. **La CLI detecta y apunta; no crea contenido, no
  valida, no interpreta**: `walkthrough guide` crea el archivo **vacío** a propósito, porque no hay
  `build` que rechace un esqueleto a medio llenar y las instrucciones que quedaran adentro las
  leería el próximo agente como si fueran las convenciones. La regla de «en vigor» es la de
  `walk_draft_body` —vacío o puro whitespace se comporta como ausente— pero con **cero procesos**:
  un `read` builtin que corta en la primera línea no vacía, porque esto se pregunta en cada refresco
  del panel. `clean` no las toca, y no hay `forget --guide`: el path es fijo y la CLI ya lo imprime,
  así que sería un comando cuyo trabajo entero es un `rm` de algo que acabás de ver en pantalla —a
  diferencia del borrador, cuyo nombre no podés deletrear. Borrar la compartida tampoco es de este
  comando: es un archivo trackeado, o sea `git rm` más un commit, y `--delete --team` se niega
  diciéndolo.

---

## 8. Los registros porcelain

- **El registro `guide` de `config --porcelain`:** `guide<TAB><kind><TAB><path><TAB><state>`, con
  `kind` = `team|own` y `state` = `in-force|empty|absent`. **Sólo de ese verbo**, y por eso sólo
  fuera de una review: las guías se dibujan en el pie del panel y una review no tiene pie, así que
  `status --porcelain` no las nombra — sería un dato que nadie pide en el camino que tiene que salir
  barato. **Siempre las dos filas**, exista o no
  cada archivo, y ahí está la diferencia con los registros `draft`: la ausencia se **reporta**, no
  se implica con el silencio, porque un cliente no puede ofrecer crear una guía de la que nunca le
  hablaron y rearmar el path de su lado es lo que la regla del path reportado existe para impedir.
  `empty` no se pliega en `absent` aunque las dos digan «no hay convenciones»: con el archivo ahí lo
  que se ofrece es abrirlo, no crearlo. Cuesta **un solo `rev-parse`** (`--show-toplevel` y
  `--absolute-git-dir` en la misma llamada, del que se deriva el común sacándole `/worktrees/<name>`
  — `--git-common-dir` contesta relativo al *cwd* y en Windows prefijarlo con `$PWD` mezcla estilos
  de path adentro de un mismo registro, y el cliente no puede abrir el resultado).
- **El registro `walkthrough` de `config --porcelain`:**
  `walkthrough<TAB><state><TAB><path><TAB><annotated><TAB><total>[<TAB><branch>]`, con `state` =
  `in-sync|stale|superseded|unknown|absent`. **Siempre la fila**, exista o no el archivo, por el
  mismo motivo que las guías. El campo `branch` es **cómo se llama la fila** en los tres paneles:
  antes decía «Walkthrough» debajo de una sección titulada *Walkthrough* y encima de dos botones
  que empezaban con la misma palabra, o sea el mismo sustantivo tres veces sin que ninguna de las
  tres agregara un dato. Se **omite, nunca va en blanco**, con `HEAD` detached —el archivo y los
  dos verbos funcionan igual ahí; lo único sin respuesta es el nombre, y esa copy es del cliente—
  y no cuesta un proceso: `current_branch_init` ya lo resolvió **una vez por proceso** para las
  filas `candidate` de la misma corrida (mismo patrón que `walk_gitdir_init`, y por el mismo
  motivo: un `$(...)` no cachea nada). Del lado del panel eso convierte el bloque en **tres filas
  y nada suelto arriba**: `walkthrough init` y `walkthrough build` son la botonera de la fila
  —su sujeto es el archivo que la fila nombra, igual que *Create* es el de cada guía— y sus
  etiquetas pierden el prefijo, que en el menú y la paleta sí se conserva porque ahí no hay
  sección que dé contexto. Siguen siendo dos de las 27 acciones: por eso se declaran en
  `panel_layout` (adentro del bloque de la fila) y no en el mapa de controles de fila, que es
  donde viven abrir y copiar.
- **Los tres registros porcelain del borrador:** `config --porcelain` emite un `draft<TAB><src><TAB>
  <path><TAB><annotated><TAB><total><TAB><source><TAB><range>` por cada borrador del namespace
  **activo**, con y sin argumento de rama (un borrador es un hecho del working tree, no de la rama
  consultada); `status --porcelain` le suma la ruta absoluta a su registro `draft` de presencia; y
  `list --porcelain` gana `branch-draft<TAB><branch>` detrás de cada fila `branch` que carga uno, con
  la misma condición de custodia que el `(draft)` legible y por un único helper para que las dos no
  puedan divergir. El progreso lo cuenta `walk_draft_progress` con **un solo `awk`** sobre todos los
  archivos a la vez; con cero borradores `emit_draft_records` corta **antes** de invocarlo, porque
  `awk` sin argumentos de archivo lee la entrada estándar y se cuelga — y este verbo corre en cada
  refresco del panel. **El par cuenta una unidad por entrada MÁS el heads-up**, porque la pregunta
  que contesta es la de `build`: el esqueleto deja un placeholder por entrada y uno de heads-up, y
  `build` los rechaza a todos igual, así que sin contarlo el caso más común de todos —un archivo en
  el rango— reportaba `1/1` y el `Validate and start` que los tres clientes apagan con ese par
  moría en «the heads-up placeholder is still there». Se cuenta sólo si la sección tiene **algo**
  escrito, que es lo que mantiene el par en paso con `build` del otro lado: borrarla entera es
  legal, así que el total baja de 1/2 a 1/1 en vez de quedar fuera de alcance. El placeholder se
  busca con la regla anclada de `build` y sobre **todo el preámbulo**, no dentro de la sección: un
  comentario que sobrevivió a su encabezado sigue contando, y uno citado dentro de un why no.

---

## 9. Los clientes del monorepo

**Las ramas de ediciones tienen filas, y un "Discard all" que nunca alcanza una sesión viva.** La
sección «Edits you extracted» del pie de `no-review` (`fixes_rows:` en el contrato) es la superficie
de las `review-fixes/*` que deja un `finish` —el último estado del repositorio que ninguna otra
nombraba: `list` no las enumeraba, el inventario del panel sale de `list`, y el único *Clean* del
panel vive en el banner de `finish-pending`—. Sus dos controles (`discardFixes` de fila y
`discardAllFixes` de sección) son ambos de `fixes_rows.controls` en el contrato y **no tocan el
conteo de 27**, igual que los de `draft_controls` y `guide_rows` — declarar `discardAllFixes` inline
en `panel_layout` lo volvería obligatorio en toda fixture `no-review`, incluidas las que no traen
fixes, porque el chequeo de secuencia estricto por situación de JetBrains/Visual Studio sólo entiende
gates de modo (`walk`/`step`/`whole`), no `when: has_fixes`. Tres reglas: **`discardAllFixes` corre
`clean --fixes-only` SIN rama**, nunca un `clean` a secas —por diseño de `clean`
(`bin/git-review-verbs/clean`) eso enumera sólo `review-fixes/*` y jamás toca una `review/*` viva de
otra rama, así que no hereda el problema de alcance que antes bloqueaba un botón así—; el Discard de
fila corre **siempre `--fixes-only <rama>`**, exista o no la sesión: el argv no puede depender de un
dato que se relee en cada refresco, y un `clean <x>` que llegue tarde —la review volvió a existir
entre el refresco y el click— se llevaría puesta una review viva; y las dos rutas siguen detrás de
una confirmación con el detalle completo, porque lo que hay acá es trabajo escrito a mano y no
basura de máquina — las filas con su badge por rama siguen siendo el camino de default para quien
quiere decidir rama por rama. El badge sale del campo `state` del registro `fixes` y los cuatro
valores **no se pliegan entre sí**: `empty` no es «seguro porque ya está integrada» (una rama intacta
está parada en la punta del PR y no contiene nada tuyo) y `unknown` no es `unmerged` (sin base la
pregunta no tiene respuesta). La fila `current` se dibuja igual y sin control de fila: la CLI la
saltea, y esconderla dejaría una rama que existe sin ninguna superficie que la nombre, que es justo
lo que la sección vino a arreglar.

**El pie se queda con el 55% del panel y scrollea adentro; nunca lo recorta.** Es un invariante de
los tres, con tres implementaciones: `max-height` + `overflow-y: auto` en `.pane-footer`, el
`preferredSize` capado del `JScrollPane` que `BorderLayout.SOUTH` consulta, y el `MaxHeight` que
`_root.SizeChanged` le pone al `ScrollViewer` del pie. Sin el tope, el pie **es** el panel: la banda
inferior de los tres layouts pide el alto que quiere, empuja el cuerpo fuera de la vista y después
se recorta ella misma contra el borde, sin barra con la que alcanzar el resto. En la extensión hay
además un eslabón que no se ve en el DOM: el flex item de `.tools` no es `.tools-body` sino el
`::details-content` que Chrome interpone, y el `overflow: auto` del cuerpo no se activa hasta que
ese wrapper —y el track del grid, que va `minmax(0, 1fr)` porque `1fr` es `minmax(auto, 1fr)`—
aceptan bajar del min-content. Los gates son `footer:capped` / `footer:scrolls` en el `--verify` de
Visual Studio y el test del renderer de JetBrains, los dos sobre el render de verdad; del lado de la
extensión, donde ni la suite de integración puede mirar el webview, es un assert estructural del
CSS.

**Una review no tiene pie: ninguna `tools_section`.** Todo lo que cuelga de `walkthrough` —los dos
verbos del autor y las dos guías de autoría— es de quien está parado en **su** PR, y adentro de una
review estás parado en el de otro; una sección titulada «Walkthrough» al pie del orden de lectura
que estás caminando diría además ese sustantivo por dos cosas distintas en la misma pantalla. Todo
eso vive en `no-review`. Y los registros ni siquiera llegan hasta ahí: son de `config --porcelain`,
que adentro de una review no se invoca, así que el modelo de los tres clientes tiene la lista vacía
y ninguna superficie puede ofrecer nada sobre ellas por accidente.

**Ninguno de los tres vigila el archivo de una guía, pero los tres escuchan el guardado.** El
watcher no las mira a propósito (la propia vive en la raíz del gitdir, que cambia en cada operación
de git), así que el cliente que la crea o la descarta refresca él mismo, dentro del lock; y para el
único momento en que el panel mentiría —apretás *Create*, escribís las convenciones, Ctrl+S, y el
badge sigue diciendo `empty`— cada host escucha el guardado del documento y refresca **sólo** sobre
las rutas que la CLI reportó: `onDidSaveTextDocument` en VS Code, el evento de VFS que produce un
save en IntelliJ (matcheado por path exacto, sin watch root nuevo), y `OnAfterSave` de la running
document table en Visual Studio.

**Un control cuyo sujeto es una FILA no es una acción del producto.** Los cuatro del bloque de
borradores (`draft_controls:`) y los tres del de guías (`guide_rows.controls:`) viven en mapas
propios del contrato y no adentro de `panel_layout:`, porque sin la fila que los dibuja no tienen
sujeto. Consecuencia: **no tocan el conteo fijo de 27**, no van a `contributes.commands` de VS Code,
ni al menú *Tools → git review* de JetBrains, ni al `.vsct` de Visual Studio — y el verificador lo
comprueba en esa dirección también, así que colar uno como acción falla CI.

**El icono de un control lo declara el contrato, no cada cliente.** `icon_vocabulary:` fija los
cinco nombres (`prev`, `next`, `file`, `trash`, `diff`) y cada control que lleva icono los usa con
`icon:`; lo que cambia por cliente es de dónde sale el dibujo —SVG inline en VS Code, `AllIcons` en
JetBrains, un carácter del BMP en Visual Studio— y nunca **cuál**. Los nombres son semánticos y no
del trazo (`prev`, no `left`): lo que el canónico fija es qué significa el icono. Existe porque el
icono era lo único de un control que ningún lado declaraba, y los dos clientes que lo **derivan del
id** se olvidaron del mismo control dos veces seguidas —los tres pares de las guías primero, el
tacho de las ramas de ediciones después—: el olvido no explota ni deja la pantalla en blanco, cae al
nombre accesible (un botón del ancho de una oración en la cabecera de una fila) o a la flecha de
`next`, que es un icono válido y equivocado. Cada cliente contesta ahora desde **un solo mapa**
(`ICON_OF` en `PanelRenderer.kt`, `IconOf` en `PanelView.cs`, el literal de cada llamada en
`panelHtml.ts`) y `check-client-product-surface.mjs` compara par por par contra las tres puntas, más
la dirección de vuelta dentro del YAML: un control con `emphasis: icon` y sin `icon:` falla. La
verificación va **del canónico a los clientes**, así que un cliente puede mapear un id que el
canónico no declara (`copyCliInstall` en JetBrains) pero no dejar sin mapear uno que sí está. Y como
segunda línea, el render de cada cliente se pregunta sobre **todas** sus fixtures si algún control de
icono cayó al fallback (`icons:own-glyph` y compañía en `--verify`, `no icon control anywhere falls
back to its accessible name` en JetBrains): el contrato ata el nombre, esto ata el dibujo.

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

**La paridad es una regla del monorepo, no una promesa al usuario.** Ninguna superficie que le
llegue a quien instala —el `README.md` de cada cliente, el `<description>` del `plugin.xml`, el
`overview.md` de Visual Studio, la ficha de cada tienda— nombra a los otros dos clientes ni dice
«paridad con X». Quien instala uno ya eligió su editor y lo más probable es que no sepa que los
otros existen: contarle que hay paridad es un dato sobre cómo está hecho el repo, no sobre lo que
recibe. La paridad se sigue verificando igual, pero se cuenta en `CONTRIBUTING.md` —el de la raíz y
el de cada cliente— y acá. En JetBrains la regla además la testea `PluginCompatibilityTest` sobre el
`<description>`.

**Y del desarrollo no hay nada en el README.** Los tres clientes siguen el reparto del proyecto
raíz: el `README.md` es producto (qué hace, cómo se empieza, qué ofrece el panel, requisitos,
settings, troubleshooting) y todo lo de construirlo, correrlo desde el checkout, testearlo y
empaquetarlo vive en el `CONTRIBUTING.md` de al lado —`vscode-extension/`, `jetbrains-plugin/` y
`visualstudio-extension/` tienen uno cada uno—, con la misma forma en los tres: *The CLI is the only
source of truth · Developing · Testing · Packaging*. El de la raíz sigue teniendo una sección por
cliente como puerta de entrada.


---

## 10. Plugin de JetBrains

**Las tres verificaciones corren en cada push, y sus warnings se anotan sin bloquear.**
`verifyPluginProjectConfiguration` y `verifyPluginStructure` terminan en BUILD SUCCESSFUL igual
cuando encuentran algo —un `since-build` por debajo de la plataforma contra la que se compila, un
nombre que el Marketplace va a objetar, un descriptor que la tienda lee distinto que el IDE—, y
`verifyPlugin` sí falla por incompatibilidad binaria pero sus usos de API deprecada / interna /
experimental viajan en el veredicto y en los archivos del reporte. Todo eso era invisible hasta
que la versión ya estaba publicada, porque el verifier sólo corría en el workflow del tag. Ahora
el job tee-a la salida y `jetbrains-plugin/verification-report.sh` la convierte en anotaciones de
GitHub más un resumen del job; **nunca sale distinto de cero** — un warning es un warning, y
volverlo build rojo es lo contrario de lo que se busca. Dos filtros, los dos tontos a propósito:
el del log es una **lista de lo benigno** y no una de warnings conocidos (una forma de mensaje que
nadie previó tiene que aparecer como ruido, no desaparecer), y el del reporte del verifier cuelga
de que por cada IDE salgan siempre tres archivos —`dependencies`, `telemetry`,
`verification-verdict`— y **cualquier otro** sea el verifier teniendo algo que decir, así que no
hay que conocer sus nombres de antemano.

**En CI el verifier corre contra IDEA sola** (`-PverifierIdes=idea`); los ocho productos van sólo
en el release. Cada entrada de `pluginVerification.ides` es un IDE que Gradle baja como
dependencia, y el set completo no entra en los 10 GB de cache del repo: lo llenaría y desalojaría
la plataforma que el release restaura. Lo que CI busca ahí son los usos de API, que salen iguales
contra cualquiera de los ocho; la compatibilidad binaria por producto se sigue verificando entera
antes de publicar nada.

**Prueba manual (como la extensión):** `./tests/sandbox.sh` →
`git -C <sandbox>/work review start feature/checkout` → `./gradlew runIde` → abrir solo
`<sandbox>/work` → setting **Tools → git review → Path to git-review** al `bin/git-review` del
checkout si hace falta → tool window **git review** + menú **Tools → git review**. Detalle en
`CONTRIBUTING.md`
(sección *The JetBrains IDE plugin*) y `specs/009-plugin-intellij/quickstart.md`.

**La VFS se toca en un solo lugar, y nunca desde el EDT.** `host/EditorFiles.kt` es la única
puerta: `openInEditor` resuelve el path en un pooled thread y abre el editor de vuelta en el EDT
—las dos mitades con el `Bg.async` que el camino del diff ya usaba—, y `refreshAndFind` queda para
los llamadores que necesitan el `VirtualFile` como *valor* (los lados del diff), que ya corren
adentro de un `work` de `Bg.async`. El motivo es que `refreshAndFindFileBy*` son dos operaciones
con un solo nombre: buscan el archivo y, si la VFS nunca lo vio, **crean el nodo y disparan el
evento de creación** — o sea mutan el modelo de la plataforma, que pide el write-intent lock que un
`ActionListener` de Swing no tiene (el panel entra por un `JButton`, no por una `AnAction` que la
plataforma envuelva). Lo que lo vuelve traicionero es *qué* archivos toman esa rama: los del
working tree pegan siempre en la caché y la llamada se lee como sana al lado de la que revienta,
mientras que **el borrador del revisor y su guía propia viven en el gitdir**, el único lugar que
ningún editor indexa, así que son siempre el nodo que hay que crear. Falla en runtime, sólo ahí, y
ningún test de la suite lo ve; el gate es `VfsAccessTest`, que prohíbe la llamada directa en todo
`src/main/kotlin`. Por lo mismo `saveDraftDocument` del wizard **no** resuelve el path: le pregunta
a `FileDocumentManager` por sus documentos sucios, que ya traen su `VirtualFile` cargado — sin
archivo en la VFS no hay documento abierto, que es la misma respuesta que quería.

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


---

## 11. Extensión de Visual Studio

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

**Los iconos de este cliente son glifos de texto.** Fuera del VSIX no hay Image Catalog, así que
`PanelView` dibuja cada icono del alfabeto del contrato como un carácter — todos del BMP a
propósito: un codepoint astral es un tofu en la fuente que traiga el tema. Los cinco son constantes
(`GlyphPrev`/`Next`/`File`/`Trash`/`Diff`) porque el mismo sujeto se dibuja **dos veces**: pelado en
la cabecera de una fila y al lado de una etiqueta en un botón (*File*, *Diff*, y cada file row). El
glifo va **pegado a la etiqueta en un solo string**, nunca como contenido compuesto con color
propio: un `Foreground` local le gana al setter `disabled` del `Style` y deja un botón apagado con el
texto vivo (la misma regla del párrafo de arriba, un nivel más adentro; el gate es
`buttons:content-inherits-foreground`). En las file rows va en el **mismo** `TextBlock` que el path,
porque partido en dos el path recibe ancho ilimitado y pierde el `…`. Y el fallback de un id sin
mapear sigue siendo la flecha de *Next* **a propósito**: es lo que `icons:own-glyph` busca para
distinguir un id mapeado de uno que nadie mapeó.

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

**Dos suites, y cubren mitades distintas.** `tests/GitReview.Domain.Tests` es la proyección pura
(porcelain → `PanelModel` → `PanelLayout`, más la tabla de argv y la copy) y lleva los dos gates
anti-drift contra el contrato — `PanelLayoutContractTests` y `ConfirmationContractTests` — más
`PanelLayoutInvariantsTests`, que es lo único que pide las reglas que el layout chequea al
construirse: una violación ahí es una excepción en el camino del render, no un test rojo, salvo que
algo arme la forma mala a propósito. `tests/GitReview.Host.Tests` es la capa que habla con la CLI: el
pipeline de refresh contra un invoker guionado (`FakeCliInvoker` — por eso `CliInvoker` no es
`sealed`) y el puñado de casos que necesitan un proceso real, que lanzan `git` en vez de fingirlo.

**Las fixtures del panel viven en `visualstudio-extension/fixtures/` y se compilan en los dos
proyectos** (el de test y `GitReview.VS`) con `Compile Include`, igual que
`jetbrains-plugin/fixtures/` se comparte entre los tests y el preview de ese cliente. Estuvieron
duplicadas: una copia privada en el proyecto de test y otra en `PreviewApp.cs`, y las situaciones que
sólo tenía la galería —finish-conflict, out-of-range, error, whole con 300 archivos— eran justo las
que ningún test afirmaba. Agregar una situación es agregarla a `All()`, y con eso entra a la
galería, al `--verify` y al alcance del test de contrato de una.

**Una acción `not_in: [visualstudio]` se afirma por id, nunca por label.** El enum no tiene
`OpenAllChanges`, así que un chequeo por el texto `"Diff"` de la única acción que este cliente omite
no podía fallar nunca. `PanelLayoutContractTests` lee el `not_in` del YAML y verifica las dos
direcciones, y además **rechaza cualquier control que la situación no declare**: sin esa parte el
matcher sólo probaba que los controles esperados estuvieran, y en orden — un botón de más en
cualquier lugar del panel pasaba entero (una mutación con un *Clean all* primary inyectado en toda
review lo confirmó). El mismo agujero estaba en `PanelLayoutContractTest` de JetBrains y se cerró
igual, en los dos a la vez.

`bin/`/`obj/` de los cuatro proyectos van al `.gitignore` raíz (`visualstudio-extension/**/bin/`,
`**/obj/`) — nunca se commitean. Versión propia, independiente de la CLI y de los otros clientes:
`./visualstudio-extension/bump-version.sh X.Y.Z` estampa
`GitReview.VS.csproj`, `source.extension.vsixmanifest` y
`Directory.Build.props` a la vez (cubierto por `tests/version-consistency.bats`).


---

## 12. Extensión de VS Code

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


- **Editor de pruebas:** abrir `vscode-extension/` en VS Code y F5 (config *Run Extension* de
  `.vscode/launch.json`) levanta un **Extension Development Host**
  con la extensión cargada desde el checkout; los cambios entran con *Developer:
  Reload Window* en esa ventana, no reiniciándola. El panel sólo tiene algo que mostrar dentro de un
  repo con review activo: armá uno con `./tests/sandbox.sh`, arrancá el review
  (`git -C <sandbox>/work review start feature/checkout` entra en walk, porque el sandbox commitea
  un walkthrough) y abrí `<sandbox>/work` en el host. Ojo: el host hereda el `PATH` del VS Code que
  lo lanzó, no el que arma el `env.sh` del sandbox — o instalás el checkout, o apuntás la setting
  `gitReview.path` a `bin/git-review`.
- **La suite de integración va en el contenedor**, misma regla que bats: los 91 tests tardan 38 s
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
  los 91 tests fallan con `cli-missing`.
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
  `file://`): los veintisiete estados del panel lado a lado, a ancho de sidebar, con selector de tema
  dark/light/alto contraste. El pane es el `panelHtml()` real y los estados de `preview/fixtures.ts`
  son salida `--porcelain` de ejemplo pasada por el parser y el modelo reales, así que **sigue al
  código y no se mantiene aparte**. Lo que no puede afirmar: los botones no tienen extensión del
  otro lado; las variables de tema de `preview/build.ts` son una aproximación — si el panel empieza
  a usar una `--vscode-*` que no está en esa lista, agregarla es parte del cambio; y el pane
  `loading` es ese estado congelado — su temporización (el umbral antes del esqueleto, el techo de
  un `--why` lento)
  sólo ocurre navegando. Para comportamiento, F5.


---

## 13. Assets del logo y la landing

### Assets del logo

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

### La landing

`docs/index.html` se publica en GitHub Pages desde la rama `main`, carpeta
`/docs` (Settings → Pages → *Deploy from a branch*). **No hay build ni workflow**: es un HTML
estático autocontenido, así que cada push a `main` que toque `docs/` lo republica solo en un par de
minutos. Para previsualizarlo, abrilo directo en el navegador — no necesita servidor.

- `docs/.nojekyll` evita que Pages lo pase por Jekyll.
- `docs/logo.svg` es el favicon: copia generada del maestro (ver *Assets del logo*), nunca a mano.
- `docs/og.png` es la preview de los links, y **la genera `scripts/og/render.mjs` desde
  `scripts/og/card.html`** (Chrome headless, un solo disparo del viewport): como el logo, no se
  edita a mano. Sale **a 2x, o sea 2400×1260 y no los 1200×630 nominales**, porque ese par es un
  *mínimo* para Open Graph y para Twitter y todos los scrapers bajan de escala solos; disparar a
  escala es además la única forma de que salga nítido en un paso, ya que remuestrear en JavaScript
  pediría un códec PNG y el navegador headless ya está ahí. Fue **copia de `demo-poster.png`** y dejó de serlo a propósito: un
  archivo hacía dos trabajos distintos —la carátula del video de YouTube de los dos README y la
  tarjeta social de la landing— y actualizar uno mentía sobre el otro. `demo-poster.png` sigue
  representando el video tal como se grabó; la tarjeta representa el producto de hoy. Su contenido
  es **el demo walk de la landing verbatim** (la misma paleta, la misma IBM Plex Mono, las mismas
  cuatro entradas de `rate-limit`) — copiarlo en vez de inventar copy nueva es lo que evita una
  cuarta superficie que mantener sincronizada; si los tokens de la landing se mueven, se mueven
  también en `card.html`. El `<head>` declara `og:image:width`/`height` porque Slack y Discord
  dibujan la card chica hasta que bajan y miden la imagen ellos mismos, y un `…:alt` en las dos
  puntas para quien tiene las imágenes apagadas. Las URLs de `og:image` y `canonical` están
  hardcodeadas a `ezevillo.github.io/git-review-workflow/` — si algún día se le pone dominio propio,
  hay que tocar esas líneas del `<head>` (y agregar un `docs/CNAME`).
- `docs/` **no** está en `files` de `package.json`, así que no viaja en el tarball de npm ni infla
  el paquete.


---

## 14. Release y versionado

Los releases de la CLI se cortan pusheando un tag `v*`: el workflow crea el GitHub Release, fija la
fórmula y publica a npm vía Trusted Publishing (OIDC, sin `NPM_TOKEN`: el repo está registrado como
trusted publisher en npmjs.com).

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

## 15. La copy de los paneles

Los tres clientes le hablaban a alguien que ya conocía la CLI, y no por descuido: los textos eran
**precisos sobre el mecanismo**. Un tooltip decía `git review forget --draft (with confirmation)`,
una confirmación arrancaba con el comando y seguía con globs (`review-fixes/*`, «banked edits»,
«delta markers»), y el banner de cierre mandaba a la terminal —`git review finish --abort`,
`clean --keep-fixes`— teniendo los dos botones que corren justo eso tres centímetros más abajo.
Nada de eso contesta la pregunta que alguien tiene delante de un panel.

Tres reglas, en orden de importancia:

**1. El próximo paso se dice sólo si está fuera del panel.** Si el próximo paso es un botón que ya
está en pantalla, el botón *es* el texto: nombrarlo en prosa lo dice dos veces y encima enseña una
sintaxis que quien mira el panel eligió no usar. Se escribe el próximo paso cuando vive en otro
lado —Source Control, el editor, `git checkout --`— porque ahí el panel es lo único que puede
señalarlo. El banner de `finish-pending` es el caso de manual: «Commit and push them from Source
Control» se queda, los dos comandos se fueron.

**2. Tres capas, y el mecanismo nunca en la primera.** Etiqueta (qué hace, 1-3 palabras); contexto
(una oración, sólo si el resultado no es obvio o no tiene vuelta atrás); detalle técnico —el
comando, el stderr, la ruta— siempre a un clic, nunca en el camino.

**3. Se confirma lo que no se puede deshacer.** Un cartel que aparece siempre deja de leerse, y
entonces tampoco se lee el que importa. Por eso la confirmación de `start` **se borró**: el
asistente ya pregunta cuatro cosas, la quinta pantalla repetía las cuatro respuestas y agregaba el
comando, y `start` no destruye nada (se niega solo con el árbol sucio, y una review empezada se
cancela con un botón). Lo que sobrevive de esa pantalla es la frase, mudada al paso que ahora
ejecuta: el título del picker de forma de lectura nombra la rama (`UserCopy.startLayoutTitle`).

**Un aviso de estado obsoleto, no diez.** Eran diez constantes por cliente —catorce literales en VS
Code— y cada una nombraba el verbo que no corrió: «nothing was finished», «nothing was saved». Ese
verbo no es información, es el botón que el revisor acaba de apretar. Lo único que no puede deducir
es *por qué* no pasó nada, y eso es idéntico en los diez casos. Tampoco lleva «try again»: el panel
ya se refrescó solo, así que el estado que se ve al leer el mensaje es el nuevo.

**Los fallbacks de error dicen qué no pasó, no qué comando falló.** Son lo único que llega cuando la
CLI muere *sin stderr* (matada, rota, un exit ≠ 0 mudo), o sea el peor momento para contestar con
un argv. Cuando la CLI **sí** trae stderr no cambió nada: ese texto se sigue mostrando tal cual
(FR-024), porque los mensajes de esta CLI dicen qué pasó y cómo salir.

**Un nombre por concepto, y ninguno prestado de git**: `orphan` → `broken`, `no metadata` →
`details are gone`, `uncovered` → `not covered`, `banked edits` → `saved edits`, y un solo verbo
para borrar (`Delete`, no `Discard`/`Clean`/`Forget` según el día). La distinción entre el
*walkthrough* (el archivo del autor, versionado en el PR) y el *reading order* (el que escribe el
revisor) sí se mantiene: son dos objetos distintos y el producto los trata distinto.

**Esto es de los paneles, no de la CLI.** `git review status` sigue imprimiendo `(uncovered)` y los
README siguen diciendo «banked edits»: esa superficie es para quien eligió la terminal, y ahí el
vocabulario de git es el vocabulario correcto.

**Dónde vive cada texto.** El patrón que ya tenían JetBrains y Visual Studio —un `UserCopy` con
todas las cadenas— es ahora también el de VS Code (`src/review/userCopy.ts`), y el canónico sigue
siendo `contracts/client-product-surface.yaml`. Los tooltips entraron ahí: se declaraban en cuatro
formas distintas y sólo una tenía parser, así que el de `openAllChanges` vivía en el contrato sin
que nadie lo verificara. Ahora `check-client-product-surface.mjs` barre **toda** clave que empiece
con `tooltip` y la exige en los tres paneles (con `not_in:` en la misma línea como única excepción),
en vez de una regex por forma que se olvida de la quinta.

### 15.1 El acuse de recibo: lo que el panel muestra no se notifica

La primera pasada dejó una notificación que era el diagnóstico entero en un párrafo. Al crear un
borrador desde el asistente caía esto, y el panel se actualizaba al mismo tiempo:

> wrote $GIT_DIR/review-walkthrough/feature/legacy.md with 1 file(s) from origin/feature/legacy;
> fill in the order and why, then run `git review walkthrough draft --build feature/legacy` — note:
> feature/legacy already carries a walkthrough from its author; your draft takes precedence over it
> while it exists. Delete it to go back to theirs. note: no authoring guide. Create one with:
> `git review walkthrough guide` (yours, outside the work tree) `git review walkthrough guide --team`
> (this repository, committed)

Las tres partes tienen su propia fila en el panel que el refresco acaba de dibujar: el archivo y el
comando siguiente son la fila del borrador y su botón *Validate and start*; el walkthrough del autor
al que tapa es la fila de arriba, con su badge; y la guía que falta son las dos filas de guías, cada
una con su *Create*. Era el panel entero, repetido en prosa, con tres comandos encima.

**Toda mutación refresca el panel antes de hablar**, así que en el camino feliz el acuse ya está en
pantalla. No notifican: crear un borrador, `walkthrough build` (que además abre el archivo) y un
`finish` que quedó `pending` (cuyo banner decía la misma frase que el toast, un segundo después).

Sí notifican los que el panel no puede contestar: un `update` de borrador —«N kept, M added, K
dropped», que la fila no muestra porque sólo trae el par nuevo—, copiar al portapapeles, y el
`finish` residual sin registro `pending`, que es el único caso sin banner.

**Cuál de los dos es se decide por lo que se pidió, nunca leyendo la salida de la CLI.** `create` y
`update` corren exactamente el mismo comando, así que la distinción no está en el texto: viaja en
`DraftFlowState.Create.update`, puesto por `initialDraftFlowState` a partir del `DraftStep` que el
revisor eligió. La misma forma tiene el otro lado: `finishSuccess` devuelve `null` cuando el panel
ya lo dijo, de modo que la regla vive en el dominio compartido y no repetida en tres hosts.

Cuidado con revertir esto a «mostrar sólo stderr»: esa fue la versión anterior y tenía un bug propio
—apretar la oferta de *update* no producía señal ninguna, porque el resultado del verbo viaja por
stdout— que es justo lo que `draftOutcomeMessage` vino a arreglar. Las dos funciones conviven a
propósito.

**Las notas que la CLI emite en verde** —`start` ofreciendo `walkthrough draft`, `draft` ofreciendo
`walkthrough guide`— quedaron fuera de esta pasada porque filtrarlas desde el cliente exigiría
parsear la salida humana, que el contrato prohíbe. Se arreglaron en la CLI: ver §15.2.

### 15.2 Advice: lo que quien tiene el porcelain no necesita

§15.1 terminaba con un pendiente: varias notas que la CLI emite **en verde** ofrecen un comando, y en
un panel ese comando es un botón que está a la vista. Filtrarlas del lado del cliente exigiría
parsear la salida humana, que su contrato de invocación prohíbe. La única solución de fondo era que
la CLI no las emitiera cuando quien la invoca ya ofrece el control, y es lo que se hizo.

**El mecanismo es el de git, no uno nuevo.** `git status` sugiere comandos y `advice.statusHints=false`
los apaga dejando el estado. Acá la llave es `reviewworkflow.advice` (o `GIT_REVIEW_ADVICE` en el
entorno, que gana, como los knobs de git); sin definir significa **encendido**, así que una terminal
conserva todas las notas de siempre. Los tres clientes exportan la variable en **un solo lugar**: su
invocador (`invoke.ts`, `CliInvoker.kt`, `CliInvoker.cs`).

**La definición es una pregunta, no una lista.** ¿Quien invoca ya tiene esto? Dos formas de que la
respuesta sea sí, y las dos son advice:

- **ofrece un comando o un flag** — el panel tiene el botón (`use --local`, `then run git review
  walkthrough draft --build`, `Create one with: git review walkthrough guide`);
- **es estado que ya viaja como registro porcelain** — el panel tiene la fila (qué guía está en
  vigor, que el borrador tapa el walkthrough del autor, que hay un borrador archivado).

Lo que **no** es advice es todo lo demás que el verbo tiene para decir: una entrada que el PR ya no
cambia y su path, un cursor que se movió, una rama que difiere de la local, un walkthrough que no
aplica al rango. Ningún registro las lleva, así que ninguna fila puede contestarlas, y se imprimen
igual con el advice apagado. Esa es la línea — **no** cuán larga es la nota. `tests/advice.bats`
prueba las dos mitades, y el test que cuida la de abajo (una entrada caída se sigue nombrando) es el
que rompe si alguien vuelve a confundir «largo» con «prescindible».

Las notas mixtas conservan su estado y pierden su oferta, con `advice_suffix`: «reviewing X, which
differs from your local Y» se queda; «; use `--local` to review what you have checked out» se va. Un
suffix y no una nota aparte porque las dos mitades son una oración.

**Los tres números del update viajan como registro, no como frase.** Es lo único que el verbo dice y
ninguna fila contesta —la del borrador muestra el par annotated/total **nuevo**, nunca lo que se
movió para llegar ahí—, así que apagar la frase sin reemplazo dejaba *Update* sin señal, el bug que
§15.1 acababa de arreglar. `walkthrough draft --porcelain` (y `init --porcelain`) emiten
`merged<TAB>kept<TAB>added<TAB>dropped` en lugar de la línea humana, y la frase la escribe
`UserCopy.draftUpdated` de cada cliente: sin ruta absoluta, sin comando, y sin decir los ceros —«0
added, 0 dropped» es hacer leer dos cifras para descubrir que no pasó ninguna de las dos cosas. Un
create emite el mismo registro con `0 kept, N added, 0 dropped` para que tenga **una sola forma**: un
cliente no debería tener que saber qué paso corrió para leer la respuesta.

Sin registro (una CLI vieja) el acuse se cae entero y el cliente se calla. Es deliberado: una
mutación sin acuse molesta menos que un acuse inventado, y el panel igual se refrescó. El caso real
lo cubre `min_cli_version`, que subió a 0.8.0 porque `--porcelain` es superficie nueva y una CLI
0.7.0 lo rechazaría con `unknown option` — o sea el borrador no se escribiría.

### 15.3 Que `confirms:` gobierne

Mirando el código para lo de arriba apareció algo peor que una copy repetida: **`confirms:` del
canónico no gobernaba nada en ninguno de los tres**. En JetBrains `requiresConfirmation(id)` se
consultaba en un `if` de cuerpo vacío; en Visual Studio sólo en un `default:` que hacía un refresh
no-op; en VS Code la tabla no existía y había 16 `showWarningMessage` sueltos en 16 archivos. El
diálogo real vivía esparcido en cada acción, y `ConfirmationContractTest` comparaba una constante
contra el YAML que nadie leía para decidir.

La prueba estaba en el árbol: el canónico decía `startFromDraft: {confirms: true}`, la tabla de
JetBrains tenía `START_FROM_DRAFT`, y el comportamiento real ya no confirmaba en ninguno de los tres
—`runStart` había dejado de hacerlo—, con las cinco suites en verde. También explica por qué dos
clientes se movieron juntos y el tercero no: no era un gate haciendo su trabajo, era que dos
comparten `runStart`.

**Una puerta por cliente, y toma el id.** `UiMessages.confirm(project, id, …)`,
`GitReviewDialogs.Confirm(id, …)`, `confirmMutation(id, …)`. El id no cambia lo que se dibuja: cambia
que un llamador no pueda abrir un modal que el contrato no declara. En runtime un id no declarado se
reporta y **confirma igual** — un cartel de más molesta, uno de menos borra trabajo sin preguntar.

**Tres gates, y los tres se probaron rompiéndolos:**

1. la tabla del cliente == el `confirms: true` del canónico;
2. todo id declarado **pasa por la puerta**;
3. **no hay ningún otro modal** fuera de ella.

El (2) se escribió dos veces. La primera versión preguntaba «¿el archivo menciona la puerta y
menciona el id?», y con el call site de `saveReview` cambiado a otro id **daba verde**: el string
`saveReview` está en ese archivo como nombre de función, de comando y de import. La versión que
quedó extrae el **primer argumento** de la llamada y compara conjuntos, en las dos direcciones. Un
gate que no se probó rompiéndolo es exactamente el gate que este §15.3 vino a arreglar.

**Dos formas que no encajan, las dos declaradas y no escondidas:**

- **`walkthroughInit`** no confirma: elige entre dos cursos («Update» / «Start over»), y la puerta no
  puede expresarlo porque su «no» es un cancel. Sigue siendo `confirms: true` porque hay un modal
  entre el clic y la mutación, que es lo que esa clave significa; los tres gates lo excluyen por
  nombre, y el modal lleva el comentario que lo dice.
- **`forgetReview`** no tiene `ControlId`: llega por el menú y la paleta, y el canónico declara
  `confirms:` **por control**, así que no hay dónde declararlo. Comparte la puerta del housekeeping
  con `clean`, que sí lo tiene, y pasa el de `clean`. Es el hueco conocido: cerrarlo es declarar
  `confirms:` también en `actions:` y darles `ControlId` a las acciones que no dibujan control.

Un detalle del barrido: el checker leía `confirms:` de dos bloques y el canónico lo declara en
**tres formas** —entrada inline con `id:`, clave de mapa en una línea, y clave de mapa en bloque—.
Con la lista de bloques, `discardGuide` y `discardInventory` quedaban afuera en silencio. El barrido
que quedó recorre el archivo entero recordando la última clave abierta, que es lo que una regex
sola no puede hacer.

### 15.4 El reveal: que el panel esté a la vista

§15.1 dejó una regla —«lo que el panel muestra no se notifica»— apoyada en un supuesto que nadie
garantizaba: **que el panel esté a la vista**. El borrador nace en el asistente de inicio, que corre
sobre el editor; con la vista cerrada o el sidebar en otra pestaña, la fila nueva se dibuja donde
nadie la ve, y como esa mutación tampoco notifica, no queda ningún acuse en ningún lado.

**Se revela, no se notifica.** El acuse correcto es la cosa, no un párrafo sobre la cosa — que es la
regla 1 otra vez. Y **sin robar el foco**: `view.show(true)` en VS Code, `ToolWindow.show()` (no
`activate`) en JetBrains, `IVsWindowFrame.ShowNoActivate()` en Visual Studio. El revisor sigue
escribiendo donde estaba; lo que cambia es que el panel deja de estar tapado.

**La lista es corta a propósito:** `startReview`, `startFromDraft`, `continueReview`, `finishReview`
— sólo las mutaciones cuya respuesta es un bloque que **antes no estaba**. Una guía que se crea, un
borrador que se descarta, un cursor que avanza mueven una fila ya dibujada, y para verlas el panel
tenía que estar a la vista igual. Si el panel salta en cada mutación, deja de significar que pasó
algo — el mismo error que notificar en cada mutación, un escalón más arriba.

De las cuatro, `startReview` es la que importa y la que menos se nota: es el **único** camino que
puede terminar *sin* cambiar de situación —el del borrador, que deja el panel en `no-review` con el
bloque nuevo arriba de todo— y es justo el que motivó todo esto.

**Nació con sus gates, y esa es la decisión.** `confirms:` había estado años declarado en tres
lugares sin gobernar en ninguno (§15.3); una tabla nueva sin gate nace decorativa. Así que `reveals:`
copia la forma entera: una puerta por cliente que toma el id, y tres chequeos —la tabla == el
canónico, todo id declarado pasa por la puerta leyendo el **argumento**, y ninguna otra superficie
trae la ventana al frente—. Los tres se probaron rompiéndolos.

Una diferencia con la puerta de confirmación, y es deliberada: ante un id no declarado, `confirm`
**confirma igual** y el reveal **no revela**. Un cartel de más molesta y uno de menos borra trabajo
sin preguntar; un reveal de más es exactamente el ruido que esta tabla existe para evitar.

**Lo que no cubre:** el scroll. Un panel visible pero scrolleado en el pie tampoco muestra la fila
nueva, que nace primero en `no-review`. Llevarlo al tope es otra superficie —un mensaje al webview en
VS Code, otra cosa en cada host— y no entró acá.
