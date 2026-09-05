# Tasks: El ciclo de una review, completo desde el panel

**Input**: Design documents from `/specs/005-ciclo-review-panel/`

**Prerequisites**: [plan.md](./plan.md), [research.md](./research.md),
[data-model.md](./data-model.md),
[contracts/config-porcelain.md](./contracts/config-porcelain.md),
[contracts/finish-state.md](./contracts/finish-state.md),
[contracts/cli-invocation.md](./contracts/cli-invocation.md),
[quickstart.md](./quickstart.md)

**Tests**: la spec pide "controlÃ¡ los errores de la mejor manera" y `../../AGENTS.md`
manda asserts fuertes para todo comportamiento observable; `003`/`004` fijaron el
precedente test-first para cambios de porcelain y se mantiene acÃ¡ â€” se incluyen
en cada historia.

**Organization**: por historia de usuario, en el orden de prioridad de la spec
(P1 Ã— 3, P2 Ã— 2, P3 Ã— 1). US1 es el MVP: sin ella ninguna otra historia tiene una
review que abrir. US2 y US3 dependen de que exista una review activa (que US1
crea) pero son independientes entre sÃ­. US4 depende del contrato que US3
introduce. US5 es independiente de US2/US3/US4. US6 extiende el asistente que
US1 construye.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: puede correr en paralelo (archivos distintos, sin dependencia de una
  tarea sin terminar)
- **[Story]**: US1 (iniciar), US2 (cancelar), US3 (cerrar), US4 (deshacer/
  destrabar un cierre), US5 (pausar), US6 (rango y origen)
- Cada tarea nombra el archivo exacto que toca

## Path Conventions

Proyecto Ãºnico, dos subÃ¡rboles: `bin/` (CLI, shell POSIX, tests en `tests/` vÃ­a
Docker) y `vscode-extension/src` (TypeScript, tests en `vscode-extension/test/`).
NingÃºn archivo cruza esa lÃ­nea.

---

## Phase 1: Setup

**Purpose**: lÃ­nea base verde antes de tocar cÃ³digo que varias historias
comparten.

- [ ] T001 Correr `./tests/run-docker.sh` completo y `npm test --prefix
  vscode-extension` en el estado actual del branch, para tener un punto de
  partida limpio antes de invertir ningÃºn test.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: la infraestructura que **toda** acciÃ³n mutante nueva (US1-US5)
necesita â€” research.md Decisiones 5, 6, 7 y 8. Sin esto, la primera historia que
la implemente tendrÃ­a que resolverla a mitad de su propio trabajo, y las
siguientes cuatro la reimplementarÃ­an con matices distintos.

**âš ï¸ CRITICAL**: T002-T009 bloquean la implementaciÃ³n de todas las historias.
Los tests de cada historia (que deben escribirse y fallar primero) no dependen
de esta fase, salvo cuando se indica.

### Tests foundational âš ï¸

- [ ] T002 [P] En `vscode-extension/test/unit/mutationLock.spec.ts`, agregar el
  caso: una segunda `run()` mientras la primera estÃ¡ en vuelo invoca un callback
  `onDiscarded` (o dispara `onDidChangeBusy` con una razÃ³n), ademÃ¡s de devolver
  `undefined` como hoy (research.md DecisiÃ³n 7, FR-036).
- [ ] T003 [P] Crear `vscode-extension/test/unit/staleGuard.spec.ts`: un
  `StaleGuard` capturado sobre `{branch, tip, situation}` que, revalidado contra
  un `ReviewState` con el mismo testigo, aprueba; revalidado contra uno con
  `tip` o `situation` distintos, rechaza con el motivo (research.md DecisiÃ³n 8,
  FR-038).
- [ ] T004 [P] Crear `vscode-extension/test/unit/invokeClass.spec.ts`: una
  funciÃ³n pura `timeoutForClass(verb, args)` devuelve 15000 para lecturas
  (`status`, `list`, `config`, `--why`, `--version`), 120000 para mutaciones
  locales (`finish`, `save`, `abort`, `continue`, `next`, `prev`), 300000 para
  `start` (research.md DecisiÃ³n 6).

### ImplementaciÃ³n foundational

- [ ] T005 [P] En `vscode-extension/src/review/mutationLock.ts`, agregar
  `onDidDiscard`/razÃ³n de descarte a `MutationLock.run()`: cuando `busy` ya es
  `true`, ademÃ¡s de devolver `undefined` notifica a los listeners con el motivo
  ("otra operaciÃ³n estÃ¡ en curso"), para que quien la dispare desde la paleta o
  un atajo se entere sin silencio (FR-036). Sin dependencia de `vscode`, como
  hoy. Depende de T002.
- [ ] T006 [P] Crear `vscode-extension/src/review/staleGuard.ts`: tipo
  `StateToken = {branch?: string; tip?: string; situation: Situation}`, funciÃ³n
  `captureToken(state: ReviewState): StateToken` y `tokenStillValid(token,
  state): boolean` (data-model.md Â§ `StateToken`). Sin `vscode`, funciÃ³n pura.
  Depende de T003.
- [ ] T007 En `vscode-extension/src/cli/invoke.ts`, agregar
  `timeoutForClass(verb: string): number` (research.md DecisiÃ³n 6) y usarla como
  default de `timeoutMs` en `invokeGitReview` cuando el llamador no pasa uno
  explÃ­cito. Depende de T004.
- [ ] T008 Crear el script no-op de askpass (`vscode-extension/scripts/askpass-noop.js`)
  y hacer que la cadena de build lo copie a `dist/`. Va en esta fase y no en
  Polish: T008a lo referencia y no puede quedar apuntando a un archivo que no
  existe todavÃ­a.
- [ ] T008a En `vscode-extension/src/cli/invoke.ts`, agregar a `InvokeOptions` un
  flag `network?: boolean` que, cuando estÃ¡ en `true`, agrega al `env` del
  proceso hijo `GIT_TERMINAL_PROMPT=0` y apunta `GIT_ASKPASS`/`SSH_ASKPASS` al
  script de T008 (research.md DecisiÃ³n 5). Sin uso todavÃ­a â€” lo consume T024
  (`start`). Depende de T008.
- [ ] T009 En `specs/002-extension-vscode/contracts/cli-invocation.md`, agregar
  al encabezado un puntero explÃ­cito: *"Enmendado por
  [`005-ciclo-review-panel/contracts/cli-invocation.md`](../../005-ciclo-review-panel/contracts/cli-invocation.md),
  que es el que rige a partir de esa feature."* (FR-001 â€” no pueden convivir dos
  listas vigentes que se contradigan).

**Checkpoint**: con T005-T009 hechos, cualquier historia puede implementar su
acciÃ³n mutante sobre la misma base.

---

## Phase 3: User Story 1 - Empezar a revisar sin saber el comando (Priority: P1) ðŸŽ¯ MVP

**Goal**: desde el estado vacÃ­o del panel, el revisor elige rama, forma de
lectura y (si hace falta) fija la base, y queda con una review activa
idÃ©ntica a la que dejarÃ­a el comando equivalente.

**Independent Test**: en un repositorio sin review, iniciar una desde el panel
y verificar contra `git review status` que la rama, el modo y la posiciÃ³n
coinciden con los del comando equivalente (quickstart.md Â§ 2).

### Tests para US1 âš ï¸

> **Escribir primero; deben fallar contra el estado actual (el verbo `config`
> no existe todavÃ­a).**

- [ ] T010 [P] [US1] Crear `tests/config.bats`: forma humana de
  `git review config` sin argumentos (imprime `base`/`remote` alineados, omite
  `base` si no estÃ¡ configurada); `git review config base` (imprime el valor o
  nada con exit `0` si no hay); `git review config base main` (lo fija, exit
  `0`, verificado leyendo `git config reviewworkflow.base`); `git review config
  --unset base` (lo borra); `git review config bese main` (exit `1`, stderr
  menciona la clave desconocida, y `git config --get reviewworkflow.bese` sigue
  sin existir â€” el efecto colateral no ocurriÃ³). **Las mismas formas sobre
  `remote`**: FR-010b exige que la escritura cubra la misma configuraciÃ³n que el
  reporte, asÃ­ que testear sÃ³lo `base` dejarÃ­a la mitad sin red. Incluir el caso
  de leer `remote` sin configurar, que devuelve el default `origin` y no vacÃ­o.
- [ ] T011 [P] [US1] En `tests/config.bats`, agregar: fuera de un repositorio
  git, exit `1` con el mismo diagnÃ³stico que los demÃ¡s verbos; con review
  activa, `git review config` sigue funcionando igual (no depende de `HEAD`); y
  `git review config base -- -foo` fija la base en la rama `-foo` en vez de
  tratarla como opciÃ³n (mismo caso que `tests/range.bats` ya cubre para `start`).
- [ ] T012 [P] [US1] Crear `tests/config-porcelain.bats`: `--porcelain` en un
  repositorio reciÃ©n clonado sin configurar emite sÃ³lo `config	remote	origin`
  (`base` omitida, no vacÃ­a); con `base` configurada, emite las dos lÃ­neas.
- [ ] T013 [P] [US1] En `tests/config-porcelain.bats`, agregar: sobre el sandbox
  de `feature/checkout`, `--porcelain` emite un `candidate` por rama de
  `refs/heads/` y de `refs/remotes/origin/` (marcando `origin`/`local`
  correctamente), **sin ninguna fila** para `review/*`, `review-saved/*`,
  `review-fixes/*` ni `<remote>/HEAD`; `current=1` sÃ³lo en la rama donde estÃ¡
  parado `HEAD`, y en ninguna con `HEAD` desacoplado.
- [ ] T014 [P] [US1] En `tests/config-porcelain.bats`, agregar: una rama local
  con espacios o acentos en el nombre (los que git permite) sale byte a byte sin
  citar, igual que un path â€” mismo criterio que `porcelain-bytes.bats` ya aplica
  a paths. Confirmar ademÃ¡s que el costo es constante: con 30 ramas de mÃ¡s
  creadas en el fixture, `--porcelain` sigue completando sin que el test tenga
  que esperar mÃ¡s que con el fixture base (guard de regresiÃ³n, no un benchmark
  estricto).
- [ ] T015 [P] [US1] Crear `vscode-extension/test/unit/configPorcelain.spec.ts`:
  parsea un `config`/`candidate` de ejemplo a `EffectiveConfig`/
  `CandidateBranch[]` (data-model.md); ignora una etiqueta desconocida y campos
  extra al final (mismo criterio que `porcelain.spec.ts` ya prueba para
  `status`); un `candidate` duplicado (misma rama, dos orÃ­genes) produce dos
  entradas, no una fusionada.
- [ ] T016 [P] [US1] Crear `vscode-extension/test/unit/reviewIntent.spec.ts`:
  la funciÃ³n que traduce `ReviewIntent` a argv (data-model.md Â§ `ReviewIntent`)
  â€” `layout: "auto"` no agrega flags, `"step"` agrega `--step`, `"no-walk"`
  agrega `--no-walk`; `source: "local"`/`"offline"` agregan `--local`/
  `--offline`; `range: "delta"` agrega `--delta`; nunca agrega `--base`, `--from`
  ni el `<base>` posicional (contracts/cli-invocation.md Â§ `start`, tabla de
  argumentos permitidos). **Y el caso de U1**: una rama llamada `-foo` produce
  `[..., "--", "-foo"]`, con el `--` inmediatamente antes del nombre y despuÃ©s
  de todos los flags; el nombre nunca sale en una posiciÃ³n donde la CLI pudiera
  leerlo como opciÃ³n.

### ImplementaciÃ³n para US1

- [ ] T017 [US1] En `bin/git-review-lib.sh`, agregar `candidate_branches`: un
  Ãºnico `git for-each-ref --format='%(refname)'` sobre `refs/heads/` y
  `refs/remotes/<remote>/`, filtrando en shell los namespaces `review/`,
  `review-saved/`, `review-fixes/` y `<remote>/HEAD`, y emitiendo
  `nombre<TAB>origin<TAB>current` por lÃ­nea (research.md DecisiÃ³n 3 â€” procesos
  constantes, no uno por rama). Depende de T013/T014 (deben fallar antes).
- [ ] T018 [US1] Crear `bin/git-review-verbs/config`: gramÃ¡tica `git review
  config [<clave> [<valor>]] [--unset <clave>] [--porcelain [<rama>]]`
  (contracts/config-porcelain.md), **incluido `--` como fin del parseo de
  opciones**, con el mismo idiom que `start` ya implementa
  (`bin/git-review-verbs/start:92-109`): sin Ã©l, un valor que empieza con guion
  â€”un nombre de rama legalâ€” se leerÃ­a como opciÃ³n. Claves vÃ¡lidas
  `base`â†’`reviewworkflow.base`, `remote`â†’`reviewworkflow.remote` (default
  `origin` si no estÃ¡ seteada). Exit `1` sobre clave desconocida, uso invÃ¡lido o
  fuera de un repo git. Depende de T017. Depende de T010-T012 (deben fallar
  antes).
- [ ] T019 [US1] En `bin/git-review-verbs/config`, la forma `--porcelain
  [<rama>]`: registros `config` (uno por clave con valor efectivo, `remote`
  siempre, `base` si estÃ¡), `candidate` (vÃ­a `candidate_branches`), y `delta`
  (sÃ³lo si se pasÃ³ `<rama>`; una fila por marker presente, con `origin`
  remote|local â€” no OR de tips; mismo par de claves que lee `start`). Depende
  de T018.
- [ ] T020 [US1] Registrar `config` en el listado de `-h` de `bin/git-review`.
- [ ] T021 [US1] `shellcheck` limpio sobre `bin/git-review-verbs/config`,
  `bin/git-review-lib.sh` y `bin/git-review` (vÃ­a Docker). `./tests/run-docker.sh
  config.bats config-porcelain.bats`: en verde.
- [ ] T022 [P] [US1] Crear `vscode-extension/src/cli/configPorcelain.ts`:
  parser de lÃ­nea a lÃ­nea con el mismo tokenizador de `porcelain.ts` (split por
  tab, primer campo = etiqueta, `switch`, ignorar etiqueta/campos desconocidos).
  Exporta `EffectiveConfig`, `CandidateBranch`, `DeltaRecord`,
  `parseConfigPorcelain(stdout): {config; candidates; deltas?: DeltaRecord[]}`
  y `deltaForSource`. Depende de T015.
- [ ] T022a [US1] En `vscode-extension/src/review/state.ts`, poblar
  `ReviewState` con el reporte de configuraciÃ³n (`EffectiveConfig` + las
  `candidate`) cuando `situation === "no-review"` o `"finish-pending"`, con el
  mismo criterio que `listBranches` ya aplica al inventario: su fallo **no** es
  una situaciÃ³n, deja el estado vacÃ­o como estaba. No se invoca con review
  activa â€” nada de lo que reporta se dibuja ahÃ­, y agregar un proceso por
  refresco irÃ­a contra el costo que `002` acotÃ³. Es el productor del dato que
  T024, T025 y T026 consumen. Depende de T022.
- [ ] T023 [P] [US1] Crear `vscode-extension/src/review/reviewIntent.ts`: tipo
  `ReviewIntent` (data-model.md) y `intentToArgs(intent, currentBranch):
  string[]` â€” sÃ³lo los argumentos enumerados en
  contracts/cli-invocation.md Â§ `start`, **incluido el `--` que precede
  siempre al nombre de rama** (U1: sin Ã©l, una rama llamada `-foo` se
  interpretarÃ­a como flag; es el idiom de git que el verbo ya soporta,
  `bin/git-review-verbs/start:92-109`). Depende de T016.
- [ ] T024 [US1] Crear `vscode-extension/src/commands/startReview.ts`:
  asistente multi-step con `vscode.window.createQuickPick` (research.md
  DecisiÃ³n 9) â€” (1) `config --porcelain` con `options.network = false` para leer
  candidatas y config, con la rama actual primera y filtro incremental; (2) tres
  Ã­tems con descripciÃ³n (AutomÃ¡tico / Commit por commit / Ignorar el
  walkthrough); (3) confirmaciÃ³n con la frase resumen (FR-017); (4) invoca
  `start` con `intentToArgs`, `options.network = true` (T008), progreso no
  cancelable (`withProgress`), refresca pase lo que pase, muestra el `stderr` de
  advertencias aunque el exit sea `0` (FR-031). Si el reporte de `config` no
  trae `base`, el paso 1 se antecede por T025 antes de continuar. Depende de
  T022a, T023, T007, T008.
- [ ] T024a [US1] En `vscode-extension/src/commands/startReview.ts`, clasificar
  el fallo de `start` en las tres categorÃ­as que SC-007 exige diferenciar y
  presentar cada una distinto: **credenciales** (ofrece *Run in Terminal*, que
  manda el comando exacto a una terminal integrada donde sÃ­ hay quiÃ©n conteste),
  **red** (el remoto no responde; sin escape a terminal, que no resolverÃ­a
  nada), y **repositorio** (working tree sucio, rama inexistente, review ya
  existente: el diagnÃ³stico de la CLI y nada mÃ¡s). La clasificaciÃ³n mira el
  `stderr` **de git** que el verbo propaga, no la salida del verbo â€” la
  frontera estÃ¡ fijada en contracts/cli-invocation.md Â§ "Clasificar no es
  parsear". Si la distinciÃ³n entre las dos primeras no resulta fiable
  (research.md DecisiÃ³n 5, riesgo registrado), colapsarlas en una y ofrecer el
  escape ante cualquier fallo de red: mÃ¡s ruidoso, nunca engaÃ±oso â€” y
  actualizar SC-007 en consecuencia en vez de dejarlo afirmando algo que no
  ocurre. Depende de T024.
- [ ] T025 [US1] Crear `vscode-extension/src/commands/setBase.ts`: `QuickPick`
  sobre las `candidate` del Ãºltimo reporte de `config --porcelain`, invoca
  `git review config base <rama>` al elegir. Invocable standalone (desde el
  estado vacÃ­o) y como paso del asistente de T024. Depende de T022.
- [ ] T026 [US1] En `vscode-extension/src/views/panelHtml.ts`, funciÃ³n
  `renderEmptyState`, caso `"no-review"`: reemplazar `docsLink("How to start a
  review")` por `button("Start a review", "startReview", "primary")`. Si el
  reporte de `config` (obtenido al construir el estado vacÃ­o) no trae `base`, un
  pÃ¡rrafo adicional lo explica con un botÃ³n `Set the base branch` que dispara
  `gitReview.setBase` â€” no bloquea el asistente, que ya lo resuelve inline
  (FR-010/FR-010a).
- [ ] T027 [US1] En `vscode-extension/src/extension.ts`, registrar los comandos
  `gitReview.startReview` y `gitReview.setBase`, cableados al `MutationLock`
  compartido (T005) y a `StaleGuard` no aplica acÃ¡ (sin confirmaciÃ³n previa: el
  asistente entero es la decisiÃ³n). En `vscode-extension/package.json`, agregar
  ambos a `contributes.commands` y a `commandPalette` con
  `"when": "gitReview.situation == no-review"` para `startReview`, sin
  restricciÃ³n para `setBase`.
- [ ] T029 [P] [US1] En `vscode-extension/test/integration/helpers/fixture.ts`,
  agregar un modo de fixture "sin review, sin base configurada" y otro "sin
  review, con base configurada" (data que T028 y T024 necesitan). Sin `[P]`
  respecto de T028: es su prerequisito.
- [ ] T028 [US1] Crear `vscode-extension/test/integration/start-review.spec.ts`:
  con un repositorio sin review (fixture de T029), correr
  `gitReview.startReview` con las respuestas simuladas del `QuickPick` (rama
  actual, automÃ¡tico), confirmar, y afirmar contra `git review status
  --porcelain` invocado directo que la review resultante coincide con la que
  dejarÃ­a `git review start` a mano. Repetir con `--step` y `--no-walk`.
  Depende de T029.
- [ ] T030 [US1] `npm run compile` y `tsc --noEmit` limpios. `npm run
  test:unit` y `npm run test:integration` en verde (incluidas T015, T016, T022,
  T023, T028).

**Checkpoint**: desde el estado vacÃ­o se llega a una review activa sin escribir
ningÃºn comando, en cualquiera de las tres formas de lectura, y la base se puede
fijar desde el mismo lugar. Esto ya es demostrable de punta a punta.

---

## Phase 4: User Story 2 - Salir de una review sin dejar rastro (Priority: P1)

**Goal**: cancelar una review desde el panel deja el repositorio exactamente
como antes de iniciarla.

**Independent Test**: iniciar una review, cancelarla desde el panel y verificar
que el repositorio volviÃ³ al estado previo y el panel al estado vacÃ­o
(quickstart.md Â§ 5).

**Depende de**: que exista una review activa que cancelar â€” la crea T024 (US1)
o el usuario a mano; el comando en sÃ­ no depende de ningÃºn artefacto de US1
salvo el `MutationLock`/`StaleGuard` de la Fase 2.

### Tests para US2 âš ï¸

- [ ] T031 [P] [US2] Crear
  `vscode-extension/test/integration/abort-review.spec.ts`: con una review
  activa con ediciones sin commitear, invocar `gitReview.abortReview` con la
  confirmaciÃ³n simulada, y afirmar que `git branch --list 'review/*'` ya no
  incluye esa rama y que `HEAD` volviÃ³ a la rama de origen (comparado contra el
  `reviewreturn` que la CLI registrÃ³ al iniciar).
- [ ] T032 [P] [US2] En el mismo archivo, afirmar que descartar la confirmaciÃ³n
  (simulando que el `QuickPick`/`showWarningMessage` devuelve `undefined`) no
  invoca `abort` â€” verificado con un spy sobre `invokeGitReview` o revisando que
  la rama de review sigue existiendo.

### ImplementaciÃ³n para US2

- [ ] T033 [US2] Crear `vscode-extension/src/commands/abortReview.ts`, con el
  molde exacto de `continueReview.ts`: `showWarningMessage` modal **fuera** del
  lock, con `detail` que dice explÃ­citamente "your uncommitted edits will be
  discarded" (FR-023); dentro de `lock.run`, `withProgress` no cancelable,
  invoca `git review abort` sin argumentos, refresca pase lo que pase, muestra
  el `stderr` si el exit no es `0`. Captura el `StateToken` (T006) al abrir el
  diÃ¡logo y lo revalida antes de invocar (FR-038): si no coincide, no invoca y
  avisa que el estado cambiÃ³.
- [ ] T034 [US2] En `vscode-extension/src/extension.ts`, registrar
  `gitReview.abortReview`. En `package.json`: comando con `icon` de descarte,
  entrada en `commandPalette` con `"when": "gitReview.situation == review"`, y
  botÃ³n en la barra del panel (`view/title` o dentro del webview, siguiendo el
  patrÃ³n de `refresh`).
- [ ] T035 [US2] En `vscode-extension/src/views/panelHtml.ts`, agregar el botÃ³n
  "Cancel review" a la barra del panel (`renderBar` o un contenedor de acciones
  nuevo), deshabilitado mientras `model.busy`.
- [ ] T036 [US2] `npm run compile`, `test:unit`, `test:integration` en verde
  (incluidas T031, T032).

**Checkpoint**: cualquier review iniciada por error, o cuyo modo no era el
querido, se deshace con el mismo costo que elegirla.

---

## Phase 5: User Story 3 - Quedarse con las ediciones al terminar (Priority: P1)

**Goal**: cerrar la review desde el panel, eligiendo dÃ³nde quedan las
ediciones, y que el panel deje de verlo como "no hay ninguna review" cuando en
realidad hay un cierre pendiente.

**Independent Test**: con una review con ediciones, cerrarla desde el panel con
cada una de las dos ubicaciones y verificar contra `git review status`/`list`
que las ediciones quedaron donde corresponde (quickstart.md Â§ 3).

**Depende de**: una review activa (US1 o a mano). Introduce el contrato que US4
consume.

### Tests para US3 âš ï¸

> **Escribir primero; deben fallar contra el contrato actual, que no reporta
> ningÃºn estado de cierre.**

- [ ] T038 [P] [US3] Crear `tests/finish-state.bats`: helper para construir el
  fixture de conflicto â€” modo `--step`, bancar una ediciÃ³n en un commit
  temprano (`git review next` tras editar), avanzar hasta el tip, editar el
  mismo archivo en el tip de forma incompatible, y correr `git review finish`
  para que quede trabado (research.md DecisiÃ³n 13, mismo mecanismo que
  `bin/git-review-verbs/finish:406-426`). Este helper lo reusan T037 y
  T039-T041, asÃ­ que va primero.
- [ ] T037 [US3] En `tests/status-porcelain.bats`, agregar: sobre una rama
  `review/*` con un cierre trabado por conflicto (fixture de T038),
  `status --porcelain` sale con exit `0` y emite una lÃ­nea `finish	conflict`,
  ademÃ¡s del `state` de siempre. Afirmar tambiÃ©n que sobre una review sin
  ningÃºn cierre en curso el registro **no** aparece. Depende de T038.
- [ ] T039 [P] [US3] En `tests/finish-state.bats`, agregar: sobre un cierre
  **completo** (sin `--onto-source`), `git review list --porcelain` emite
  `finish	review/<src>	pending` para esa rama; con `--onto-source`, tambiÃ©n
  (verificando que el `branch` reportado sigue siendo `review/<src>`, no la
  rama de destino). Sin ningÃºn cierre pendiente, ninguna fila `finish`. **Y el
  segundo estado**: sobre el fixture de conflicto (T038), estando parado en
  otra rama, `list --porcelain` emite `finish	review/<src>	conflict` â€” el
  contrato dice que en `list` aparecen los dos estados, y `conflict` visto
  desde afuera es el caso que sÃ³lo `list` puede reportar.
- [ ] T040 [P] [US3] En `tests/finish-state.bats`, agregar: tras resolver el
  conflicto (aplicar la resoluciÃ³n al working tree) y correr `git review finish
  --resume`, el registro `finish` desaparece de `status --porcelain` de ahÃ­ en
  mÃ¡s. Tras `git review finish --abort` sobre un cierre `pending`, el registro
  desaparece de `list --porcelain`.
- [ ] T041 [P] [US3] En `tests/finish-state.bats`, agregar: una CLI que no
  conoce la etiqueta `finish` (simulado invocando `status`/`list` normales
  contra un fixture sin cierre) no cambia ningÃºn registro existente â€” es
  puramente aditivo, verificado comparando la salida completa contra la de
  antes de esta feature en un caso sin cierre.
- [ ] T042 [P] [US3] Extender `vscode-extension/test/unit/state.spec.ts`, que
  ya es el dueÃ±o de la derivaciÃ³n de `Situation`: con un `finish
  conflict` en la salida de `status --porcelain`, `Situation` resuelve a
  `finish-conflict` aun con exit `0`; con un `finish pending` en `list
  --porcelain` y `status` en exit `2`, resuelve a `finish-pending`; sin ninguno
  de los dos, el comportamiento de `002`/`003`/`004` no cambia (data-model.md Â§
  `Situation`).
- [ ] T043 [P] [US3] Extender `vscode-extension/test/unit/panelModel.spec.ts`:
  con `finish-conflict`, `PanelModel` no ofrece `atFirst`/`atLast` operables
  (o expone un flag `navigationLocked: true` â€” FR-027) aunque el `state` tenga
  cursor; con `finish-pending`, el inventario del estado vacÃ­o incluye la fila
  del cierre pendiente en vez de mostrarse vacÃ­o.

### ImplementaciÃ³n para US3

- [ ] T044 [US3] En `bin/git-review-verbs/status`, forma `--porcelain`: despuÃ©s
  de emitir `state`, si `branch.$cur.reviewundohead` estÃ¡ seteado (un finish
  dejÃ³ un punto de undo sin resolver) **y** `branch.$cur.reviewresume` vale
  `conflict`, emitir `porcelain_row finish conflict "$onto"`, donde `$onto` es
  `1` si `branch.$cur.reviewundokind` vale `onto-source` y `0` si no. Leer las
  tres claves con `|| true`, como el resto del verbo. Depende de T037/T038
  (deben fallar antes).
- [ ] T045 [US3] En `bin/git-review-verbs/list`, forma `--porcelain`: por cada
  rama `review/*` enumerada, si tiene `reviewundohead` seteado, emitir
  `porcelain_row finish "$b" "$state" "$onto"` donde `$state` es `conflict` si
  `reviewresume=conflict`, si no `pending`, y `$onto` sale de `reviewundokind`
  igual que en T044 â€” inmediatamente despuÃ©s de su registro `branch`. Depende de
  T039 (debe fallar antes).
- [ ] T045a [P] [US3] En `tests/finish-state.bats`, cubrir el campo `onto` en
  los dos verbos: un cierre con `--onto-source` reporta `1` y uno sin Ã©l `0`,
  tanto en `status --porcelain` (caso `conflict`) como en `list --porcelain`
  (casos `pending` y `conflict`). Es el campo del que depende que continuar un
  cierre trabado mande las ediciones al mismo lugar donde empezaron.
- [ ] T046 [US3] `shellcheck` limpio sobre `bin/git-review-verbs/status` y
  `bin/git-review-verbs/list`. `./tests/run-docker.sh status-porcelain.bats
  finish-state.bats list.bats`: en verde. Depende de T044, T045.
- [ ] T047 [P] [US3] En `vscode-extension/src/cli/porcelain.ts`, parsear el
  registro `finish` de `status --porcelain` (`state: "conflict"`, `onto:
  boolean`) y exponerlo en el resultado de `parsePorcelain`. En
  `parseListPorcelain`, parsear el `finish` de `list --porcelain` (`branch`,
  `state: "pending" | "conflict"`, `onto`) y anexarlo al `BranchRecord`
  correspondiente por nombre. Depende de T042 (debe fallar antes).
- [ ] T048 [US3] En `vscode-extension/src/review/situation.ts`, agregar
  `"finish-conflict"` y `"finish-pending"` a `Situation`. En
  `vscode-extension/src/review/state.ts` (`doRefresh`), tras parsear `status`:
  si trae el registro `finish conflict`, `situation = "finish-conflict"`; si
  `status` saliÃ³ `2` y el inventario trae **al menos una** fila `finish â€¦
  pending`, `situation = "finish-pending"`. Nada de "la rama previamente
  conocida": la extensiÃ³n no tiene esa memoria despuÃ©s de reiniciarse, y el
  contrato no la pide â€” el inventario es autosuficiente, que es lo que hace
  cumplible SC-008. La precedencia es la de data-model.md Â§ `Situation`
  (finish-* gana siempre sobre el estado sin cierre). Depende de T047.
- [ ] T049 [US3] En `vscode-extension/src/views/panelModel.ts`,
  `buildPanelModel`: con `situation === "finish-conflict"`, `atFirst`/`atLast`
  quedan en `false` y se agrega `navigationLocked: true` a `PanelModel`
  (FR-027); con `"finish-pending"`, `reviews` sigue poblÃ¡ndose desde
  `state.branches` pero se agrega `pendingFinish: {branch, onto: boolean}`
  derivado del registro. Depende de T048.
- [ ] T050 [US3] Crear `vscode-extension/src/commands/finishReview.ts`:
  `QuickPick` de dos Ã­tems con descripciÃ³n ("A separate branch" /
  "Onto the PR branch itself", FR-018) â€” sin casilla; captura `StateToken`
  (T006) antes del `QuickPick`, lo revalida antes de invocar; invoca `git
  review finish [--onto-source]`, `withProgress` no cancelable, refresca pase
  lo que pase. **"No habÃ­a ediciones que extraer" se deriva del estado
  posterior, nunca del texto** (FR-006 y la fila "Parsear la salida humana de
  cualquier verbo" de contracts/cli-invocation.md): tras un exit `0`, si el
  refresco **no** reporta un cierre `pending` para esa review, no hubo ediciones
  â€” la CLI deshace su propio punto de undo en ese caso
  (`bin/git-review-verbs/finish:446-451`), asÃ­ que la ausencia del registro es
  la seÃ±al, y es la misma que el contrato ya expone. Se informa como resultado
  normal, no como error (FR-019). Depende de T023 (patrÃ³n de `StaleGuard`),
  T006, T047 (el registro `finish` tiene que estar parseado para poder leer su
  ausencia).
- [ ] T050a [US3] En `vscode-extension/test/unit/` (junto a los tests del
  parser), agregar el caso que fija la regla de T050: dado un refresco posterior
  a un `finish` con exit `0` **sin** registro `finish pending`, la funciÃ³n que
  decide el mensaje devuelve "sin ediciones"; con el registro presente,
  devuelve "cierre pendiente". La funciÃ³n es pura y no recibe `stdout` ni
  `stderr` de ningÃºn verbo â€” que es lo que hace verificable que no se parsea
  nada. Escribir antes de T050.
- [ ] T051 [US3] En `vscode-extension/src/views/panelHtml.ts`: caso
  `"finish-conflict"` en el estado de review â€” banner que explica el cierre
  trabado, sin los controles de navegaciÃ³n (usa `navigationLocked`), con los
  botones que US4 agrega (T057-T058); caso `"finish-pending"` dentro de
  `renderEmptyState` â€” encabeza el inventario con el cierre pendiente en vez de
  "No active review", con los botones que US4 agrega (T059).
- [ ] T052 [US3] En `vscode-extension/src/extension.ts`, registrar
  `gitReview.finishReview`. En `package.json`: comando, entrada en
  `commandPalette` con `"when": "gitReview.situation == review"`, botÃ³n en la
  barra del panel.
- [ ] T053 [P] [US3] Crear `vscode-extension/test/integration/finish-review.spec.ts`:
  con una review con ediciones, `gitReview.finishReview` eligiendo cada
  ubicaciÃ³n, y afirmar contra `git review status --porcelain`/`list --porcelain`
  invocados directo que el resultado coincide con el de `git review finish` a
  mano; con una review sin ediciones, afirmar que se informa como normal.
  **Y FR-030**: descartar el `QuickPick` de ubicaciÃ³n no invoca `finish` â€” la
  review sigue activa y sin cierre pendiente, verificado por el efecto sobre
  git y no sÃ³lo por el retorno del comando.
- [ ] T054 [US3] `npm run compile`, `test:unit`, `test:integration` en verde.

**Checkpoint**: cerrar una review desde el panel dice dÃ³nde quedaron las
ediciones y el panel deja de mentir sobre "no hay ninguna review" cuando hay un
cierre sin resolver â€” aunque todavÃ­a no se pueda actuar sobre ese cierre (US4).

---

## Phase 6: User Story 4 - Deshacer un cierre, o destrabar uno que quedÃ³ a mitad (Priority: P2)

**Goal**: sobre los dos estados que US3 hizo visibles, el panel ofrece la
acciÃ³n que corresponde a cada uno.

**Independent Test**: producir cada estado de cierre y verificar que el panel
ofrece exactamente su salida, y que Ã©sta deja el repositorio como lo dejarÃ­a el
comando equivalente (quickstart.md Â§ 3, secciÃ³n "El cierre trabado").

**Depende de**: T044-T049 (US3) â€” sin el registro `finish` en el contrato, no
hay estado sobre el que actuar.

### Tests para US4 âš ï¸

- [X] T055 [P] [US4] En `vscode-extension/test/integration/finish-review.spec.ts`
  (extiende el de T053): sobre un cierre `pending` sin tocar, invocar el
  deshacer y afirmar contra `git branch --list` que `review/<src>` volviÃ³ a
  existir con `HEAD` ahÃ­ y las ediciones intactas (comparado por el diff contra
  el tip); sobre un cierre `pending` con un commit nuevo hecho encima, invocar
  el deshacer simple y afirmar que **falla** (la rama de arreglos sigue
  existiendo con el commit nuevo), y sÃ³lo entonces la segunda confirmaciÃ³n con
  `--force` lo completa. **Y FR-030 en su forma mÃ¡s importante**: descartar esa
  *segunda* confirmaciÃ³n deja el commit nuevo intacto â€” es el Ãºnico punto del
  ciclo donde una confirmaciÃ³n mal manejada destruye trabajo.
- [X] T056 [P] [US4] En el mismo archivo: sobre el fixture de conflicto (T038),
  afirmar que `PanelModel.navigationLocked` es `true` y que invocar `next`/`prev`
  vÃ­a el comando de la extensiÃ³n no cambia `git review status --porcelain`
  (FR-027 â€” verificado por el efecto, no por una excepciÃ³n lanzada); resolver
  los marcadores en el working tree del fixture e invocar continuar, y afirmar
  que el registro `finish` desaparece y la review queda como una review normal.
  **Y el caso que motivÃ³ exponer `onto`**: un cierre trabado que habÃ­a empezado
  con `--onto-source`, continuado despuÃ©s de recargar la ventana del editor
  (para que ninguna memoria en proceso sobreviva), termina con las ediciones
  sobre la rama del PR y no sobre una rama de arreglos.

### ImplementaciÃ³n para US4

- [X] T057 [US4] Extender `vscode-extension/src/commands/finishReview.ts` (o
  crear `vscode-extension/src/commands/undoFinish.ts` si el archivo de T050 ya
  es grande) con la acciÃ³n de deshacer: captura el `StateToken` (T006) al abrir
  el diÃ¡logo y lo revalida antes de invocar (FR-038 â€” la acciÃ³n tiene
  confirmaciÃ³n previa, asÃ­ que la ventana de premisa caduca existe igual que en
  `finish`, `save` y `abort`); confirmaciÃ³n (FR-029) â†’ invoca `git review finish
  --abort`. Si falla, el `stderr` de la CLI se muestra y se ofrece una
  **segunda** confirmaciÃ³n, visualmente distinta (texto que nombra el trabajo
  que se perderÃ­a, tomado del `stderr`) â†’ sÃ³lo si se acepta, invoca `git review
  finish --abort --force` (FR-021 â€” nunca automÃ¡tico, nunca la misma
  confirmaciÃ³n). El testigo se revalida **otra vez** antes del `--force`: entre
  el rechazo y la segunda confirmaciÃ³n pasa tiempo, y es la invocaciÃ³n mÃ¡s
  destructiva de todo el ciclo.
- [X] T058 [US4] En el mismo mÃ³dulo, la acciÃ³n de continuar un cierre trabado:
  sin confirmaciÃ³n previa (no descarta nada â€” FR-020 la trata distinto de
  deshacer), invoca `git review finish --resume [--onto-source]`, tomando el
  `--onto-source` del campo `onto` del registro `finish` que el contrato reporta
  â€” **nunca de memoria del comando**: el editor se reinicia y ahÃ­ el resume
  mandarÃ­a las ediciones a un lugar distinto del que el usuario eligiÃ³, en
  silencio. Y la acciÃ³n de dar marcha atrÃ¡s desde el conflicto: mismo camino de
  `finish --abort` que T057, sin necesidad de resolver los marcadores primero.
  Depende de T047 (el campo tiene que estar parseado).
- [X] T059 [US4] En `vscode-extension/src/extension.ts`, registrar
  `gitReview.undoFinish` y `gitReview.resumeFinish` (o los nombres que T057/T058
  hayan fijado), con `"when"` acotado a `gitReview.situation ==
  finish-pending` y `finish-conflict` respectivamente. En `package.json`:
  comandos + entradas de paleta.
- [X] T060 [US4] En `vscode-extension/src/views/panelHtml.ts`: los botones de
  T051 (banner de `finish-conflict` y encabezado de `finish-pending`) pasan a
  invocar los comandos reales de T057-T058 en vez de quedar sin acciÃ³n.
  Confirmar visualmente (en `npm run preview`, T087) que ninguna acciÃ³n de
  navegaciÃ³n queda clickeable mientras `navigationLocked`.
- [X] T061 [US4] `npm run compile`, `test:unit`, `test:integration` en verde
  (incluidas T055, T056).

**Checkpoint**: los dos estados que introdujo US3 dejan de ser un callejÃ³n â€”
cada uno tiene su salida operable desde el panel, con el mismo molde de riesgo
asimÃ©trico que la CLI ya aplica.

---

## Phase 7: User Story 5 - Dejar la review a un lado (Priority: P2)

**Goal**: pausar una review desde el panel, apareciendo en el inventario que ya
existe y retomable con la acciÃ³n que ya existe desde `002`.

**Independent Test**: con una review con ediciones, pausarla desde el panel,
verificar que aparece en el inventario, y retomarla verificando que las
ediciones volvieron (quickstart.md Â§ 4).

**Depende de**: sÃ³lo de la Fase 2 (foundational) y de una review activa.
Independiente de US2/US3/US4.

### Tests para US5 âš ï¸

- [X] T062 [P] [US5] Crear
  `vscode-extension/test/integration/save-review.spec.ts`: con una review en
  modo `whole` con ediciones sin commitear, invocar `gitReview.saveReview` con
  confirmaciÃ³n simulada, afirmar que `review-saved/<src>` existe, `HEAD` volviÃ³
  a la rama de origen, y que `git review list --porcelain` la reporta `saved`
  con su modo y posiciÃ³n. Repetir en modo `step` con ediciones en mÃ¡s de un
  paso, afirmando que ninguna se pierde tras retomar con `gitReview.continueReview`
  (ya existente). **Y FR-030**: descartar la confirmaciÃ³n no invoca `save` â€” la
  review sigue activa y `review-saved/<src>` no existe.
- [X] T063 [P] [US5] En el mismo archivo: con `review-saved/<src>` ya existente
  para ese source, invocar `gitReview.saveReview` sobre otra review del mismo
  source y afirmar que falla con el diagnÃ³stico de la CLI y que la review activa
  original **sigue existiendo intacta** (no sÃ³lo que el comando devolviÃ³ error).

### ImplementaciÃ³n para US5

- [X] T064 [US5] Crear `vscode-extension/src/commands/saveReview.ts`, mismo
  molde que `abortReview.ts` (T033): confirmaciÃ³n fuera del lock (mÃ¡s suave que
  la de abort â€” no se pierde nada, sÃ³lo se pausa), captura y revalida
  `StateToken`, invoca `git review save` sin argumentos, refresca pase lo que
  pase.
- [X] T065 [US5] En `vscode-extension/src/extension.ts`, registrar
  `gitReview.saveReview`. En `package.json`: comando, entrada de paleta con
  `"when": "gitReview.situation == review"`, botÃ³n en la barra del panel.
- [X] T066 [US5] En `vscode-extension/src/views/panelHtml.ts`, agregar el botÃ³n
  "Save for later" junto al de cancelar (T035).
- [X] T067 [US5] `npm run compile`, `test:unit`, `test:integration` en verde
  (incluidas T062, T063).

**Checkpoint**: el ciclo pausarâ†’retomar queda cerrado por los dos lados â€”
`continue` ya existÃ­a desde `002`, `save` se agrega acÃ¡.

---

## Phase 8: User Story 6 - Elegir quÃ© se compara y de dÃ³nde sale (Priority: P3)

**Goal**: el asistente de US1 gana un paso opcional de rango (`--delta`) y
origen (`--local`/`--offline`), con el origen recordado como preferencia del
editor.

**Independent Test**: iniciar reviews con cada combinaciÃ³n de rango y origen
desde el panel y verificar contra la CLI que el rango resultante es idÃ©ntico al
del comando equivalente (quickstart.md Â§ 2, variantes).

**Depende de**: T017-T030 (US1) â€” extiende el mismo asistente y el mismo verbo
`config` en vez de crear superficie paralela.

### Tests para US6 âš ï¸

- [X] T068 [P] [US6] En `tests/config-porcelain.bats`, agregar: `git review
  config --porcelain <rama-nunca-revisada>` no emite registro `delta`; sobre una
  rama con un `reviewworkflow.<rama>.reviewed` seteado (simulado a mano en el
  fixture, o generado corriendo un `start`+`finish` de esa rama primero),
  `--porcelain <rama>` emite `delta	<rama>	<tip>	remote|local` con el SHA
  completo (cero, una o dos filas: ejes remoto y local disjuntos). Verificar
  tambiÃ©n el caso `reviewworkflowlocal.<rama>.reviewed` (marcador de `--local`).
- [X] T069 [P] [US6] Extender `vscode-extension/test/unit/configPorcelain.spec.ts`
  (T015): parsea el registro `delta` opcional (con `origin`).
- [X] T070 [P] [US6] Extender `vscode-extension/test/unit/reviewIntent.spec.ts`
  (T016): `range: "delta"` sÃ³lo es una combinaciÃ³n vÃ¡lida cuando el `ReviewIntent`
  se construyÃ³ con un `delta` del origin del source elegido â€” la funciÃ³n de
  validaciÃ³n (no la de traducciÃ³n a args) lo rechaza si no.
- [X] T071 [P] [US6] Crear `vscode-extension/test/unit/sourcePreference.spec.ts`:
  con el ajuste `gitReview.defaultSource` en `"local"` a nivel *workspace* y
  `"remote"` a nivel *user*, el valor efectivo que lee el asistente es
  `"local"` (el workspace gana â€” FR-016a). Sin ningÃºn ajuste, el efectivo es
  `"remote"`.

### ImplementaciÃ³n para US6

- [X] T072 [US6] Extender `vscode-extension/src/commands/startReview.ts`
  (T024) con el paso "MÃ¡s opcionesâ€¦" detrÃ¡s de un Ã­tem del paso de forma de
  lectura: origen (Remoto / Local / Local sin red, con descripciÃ³n de la
  diferencia â€” FR-014) y, sÃ³lo si hay un `delta` del origin del source elegido,
  la opciÃ³n de rango incremental (FR-015 â€” no se ofrece con el marker del otro
  origen). Depende de T068-T070.
- [X] T073 [US6] En `vscode-extension/package.json`, agregar
  `contributes.configuration.properties["gitReview.defaultSource"]`: enum
  `["remote", "local", "offline"]`, default `"remote"`, con la descripciÃ³n de
  cada valor (research.md DecisiÃ³n 11).
- [X] T074 [US6] En `vscode-extension/src/commands/startReview.ts`, leer
  `gitReview.defaultSource` (con `vscode.workspace.getConfiguration`, que ya
  resuelve user/workspace) para preseleccionar el Ã­tem de origen del paso de
  T072 â€” nunca para decidir por sÃ­ solo; el argumento que llega a la CLI sigue
  siendo el que el usuario confirmÃ³ (FR-016a). Depende de T071, T073.
- [X] T075 [US6] `npm run compile`, `test:unit`, `test:integration` en verde.

**Checkpoint**: el asistente cubre los dos ejes que motivaron la pregunta
original del usuario, sin convertirse en un formulario de flags â€” quedan detrÃ¡s
de una puerta y con su default recordado.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: validaciÃ³n de punta a punta, documentaciÃ³n y las dos rutas que
ningÃºn test automÃ¡tico cubre.

- [X] T076 [P] En `tests/sandbox.sh`, agregar dos ramas nuevas al PR de juguete:
  una con un cierre completo pendiente (`review-fixes/<src>` sin resolver) y
  otra con un cierre trabado por conflicto (el fixture de T038, reusado). El
  texto que `sandbox.sh` imprime al terminar las describe con su estado real â€”
  el precedente de `004` (T042) es verificar contra el sandbox reconstruido, no
  asumir el nÃºmero.
- [ ] T077 [P] Verificar a mano que el entorno no interactivo (T008/T008a) hace
  fallar rÃ¡pido un `git fetch` contra un remoto que pide credenciales, en vez de
  colgarse hasta el timeout (quickstart.md Â§ 6). No hay remoto autenticado en
  CI, asÃ­ que la parte automatizable es el test de que el entorno **se pasa**;
  Ã©sta es la mitad que sÃ³lo se comprueba a mano (research.md DecisiÃ³n 13). Es
  tambiÃ©n la validaciÃ³n que confirma o refuta el riesgo registrado en la
  DecisiÃ³n 5, y de la que depende si T024a mantiene tres categorÃ­as o dos.
- [ ] T078 Ejecutar quickstart.md Â§ 6 ("Demora") contra un repositorio clonado
  con historia grande: confirmar que el progreso es visible, el editor queda
  usable, y ningÃºn control de la extensiÃ³n es operable mientras `start` corre.
- [ ] T079 Ejecutar quickstart.md Â§ 7 ("Estado cambiado por fuera"): abrir la
  confirmaciÃ³n de `finishReview`, correr `git review abort` en una terminal
  aparte, confirmar en el panel, y verificar que **no se invocÃ³ nada** (afirmar
  con un spy o revisando que no aparece un segundo `finish` en el historial de
  invocaciones si el test lo instrumenta).
- [X] T080 Actualizar el mÃ­nimo de CLI a `0.4.0` en
  `vscode-extension/src/cli/version.ts` y en los textos del panel que lo
  nombran (`panelHtml.ts`, casos `cli-missing`/`cli-outdated`, que hoy dicen
  `0.3.0`), mÃ¡s `vscode-extension/test/unit/version.spec.ts`. Ejecutar
  quickstart.md Â§ 8 contra una CLI `0.3.x` real y confirmar el comportamiento
  **real**: la sesiÃ³n entera entra en `cli-outdated` con el aviso de
  actualizaciÃ³n â€” el panel no lee ni navega, exactamente como le pasÃ³ a `0.2.x`
  cuando `002` subiÃ³ el mÃ­nimo a `0.3.0`. SC-009 se cumple asÃ­ (el panel no
  ofrece nada cuyo resultado no sepa leer); lo que **no** hay es degradaciÃ³n
  parcial por capacidad, y research.md DecisiÃ³n 12 quedÃ³ corregida en ese
  sentido.
- [X] T081 [P] `README.md`: agregar la fila de `git review config` a la tabla de
  verbos, con su gramÃ¡tica completa; extender la descripciÃ³n de `status` y
  `list` para mencionar el registro de cierre pendiente/trabado donde
  corresponda; una secciÃ³n `<summary>` para `git review config` si el resto de
  los verbos complejos la tiene.
- [X] T082 [P] `README.es.md`: los mismos cambios que T081, traducidos, en el
  mismo commit (regla de los dos README).
- [X] T083 [P] `vscode-extension/README.md`: documentar las acciones nuevas
  (Start a review, Cancel review, Finish review, Save for later, y deshacer/
  continuar un cierre) en inglÃ©s, siguiendo la secciÃ³n existente que describe
  los comandos actuales.
- [X] T084 Verificar (no asumir) `docs/index.html` contra sus cuatro
  superficies duplicadas: la tabla comparativa no cambia; los mÃ©todos de
  instalaciÃ³n no cambian; los comandos de los ejemplos â€”si alguno usa
  `reviewworkflow.base` o similarâ€” siguen siendo vÃ¡lidos con `git review
  config` disponible como alternativa (no hace falta reescribir el ejemplo,
  sÃ³lo confirmar que no queda desactualizado); el formato del walkthrough del
  demo no cambia. Si ninguno requiere ediciÃ³n, dejar constancia de quÃ© se
  revisÃ³ (siguiendo el precedente de `004` T045).
- [X] T085 `shellcheck` sobre la lista completa de CI (incluido
  `tests/sandbox.sh` despuÃ©s de T076).
- [X] T086 `./tests/run-docker.sh` completo. `npm test --prefix
  vscode-extension` completo (unit + integraciÃ³n). Cero regresiones fuera de
  las inversiones deliberadas de esta feature.
- [X] T087 [P] `npm run preview --prefix vscode-extension`: agregar a
  `preview/fixtures.ts` los estados `finish-pending` y `finish-conflict`
  (`--porcelain` de ejemplo pasada por el parser real, siguiendo la disciplina
  ya documentada del preview). Verificar visualmente en los tres temas
  (claro/oscuro/alto contraste) que los banners nuevos no dependen sÃ³lo de
  color y que los botones son `<button>` reales en orden de tab (FR-031,
  heredado de `002`).
- [ ] T088 `./tests/sandbox.sh` completo + recorrido manual de quickstart.md Â§
  1 a Â§ 5 contra el sandbox real, no sÃ³lo los tests automÃ¡ticos.
- [X] T088a AuditorÃ­a de SC-004 y SC-005, que la spec define como "una revisiÃ³n
  del cÃ³digo lo verifica" y que hasta acÃ¡ no tenÃ­a quiÃ©n la ejecutara: recorrer
  el cÃ³digo de la extensiÃ³n contra
  [contracts/cli-invocation.md](./contracts/cli-invocation.md) confirmando (a)
  que toda invocaciÃ³n estÃ¡ en la lista, **verbo y argumentos** â€” el gate nuevo
  de FR-002, mÃ¡s estricto que el de `002`; (b) que ninguna acciÃ³n que cambia de
  rama, mueve refs o descarta trabajo llega a invocarse sin confirmaciÃ³n previa;
  y (c) que ninguna de las prohibiciones de la tabla aparece en el cÃ³digo,
  incluida la fila nueva sobre enumerar ramas. Dejar constancia de quÃ© se
  revisÃ³, como hizo `004` con su verificaciÃ³n de la landing.
- [ ] T088b Validar SC-008 y el edge case de interrupciÃ³n: matar el editor (o el
  proceso de la extensiÃ³n) mientras corre un `finish` sobre una review con
  ediciones, reabrirlo, y confirmar que el panel **describe** el estado en el
  que quedÃ³ el repositorio â€” sea review normal, cierre pendiente o cierre
  trabado â€” en vez de mostrar un estado vacÃ­o o un error genÃ©rico. Repetir con
  `start` a mitad de un `fetch`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: sin dependencias.
- **Foundational (Phase 2)**: depende de Setup. Bloquea la *implementaciÃ³n* de
  todas las historias (no sus tests, salvo donde se marca explÃ­citamente).
  Dentro de la fase, T008 va antes que T008a (el flag apunta a un script que
  tiene que existir).
- **US1 (Phase 3)**: depende de Foundational. Es el MVP â€” ninguna otra historia
  tiene una review propia que operar sin ella (aunque cada una puede probarse
  con una review creada a mano). Dentro de la historia, T022a es el productor
  del reporte de configuraciÃ³n que T024, T025 y T026 consumen: sin ella el
  estado vacÃ­o no tiene con quÃ© decir contra quÃ© se compararÃ­a.
- **US2 (Phase 4)**: depende de Foundational. Independiente de US1 en el
  sentido de la spec.
- **US3 (Phase 5)**: depende de Foundational. Independiente de US1/US2.
  Introduce el contrato que US4 necesita.
- **US4 (Phase 6)**: depende de US3 completa (T044-T049) â€” sin el registro
  `finish` no hay estado sobre el que actuar.
- **US5 (Phase 7)**: depende de Foundational Ãºnicamente. Independiente de
  US2/US3/US4.
- **US6 (Phase 8)**: depende de US1 completa (T017-T030) â€” extiende el mismo
  asistente y el mismo verbo en vez de duplicarlos.
- **Polish (Phase 9)**: depende de todas las historias que se vayan a incluir.

### User Story Dependencies

- **US1 (P1)**: sin dependencia de otra historia. MVP.
- **US2 (P1)**: sin dependencia de otra historia.
- **US3 (P1)**: sin dependencia de otra historia.
- **US4 (P2)**: depende de US3.
- **US5 (P2)**: sin dependencia de otra historia.
- **US6 (P3)**: depende de US1.

### Parallel Opportunities

- T002-T004 (tests foundational) en paralelo entre sÃ­, antes de T005-T008a.
- Con Foundational hecho: US1, US2, US3 y US5 pueden implementarse en paralelo
  por personas distintas â€” no comparten archivo salvo `extension.ts` y
  `package.json` (comandos), donde conviene coordinar el orden de merge.
- T010-T016 (tests de US1) en paralelo entre sÃ­, antes de T017-T024a. **T028 no
  es paralelizable con T029**: necesita su fixture.
- T038-T043 (tests de US3) en paralelo entre sÃ­, antes de T044-T052. **T037 no
  es paralelizable con T038**: necesita su fixture de conflicto, que es la
  pieza mÃ¡s cara de la feature y la que todos los demÃ¡s reusan.
- T055-T056 (tests de US4) en paralelo, despuÃ©s de que US3 estÃ© mergeada.
- T062-T063 (tests de US5) en paralelo, en cualquier momento despuÃ©s de
  Foundational.
- T068-T071 (tests de US6) en paralelo, despuÃ©s de que US1 estÃ© mergeada.
- T081-T083 (los tres README) en paralelo entre sÃ­.

---

## Parallel Example: User Story 1

```bash
# Tests de US1, en paralelo (archivos distintos, sin dependencia entre sÃ­):
Task: "Forma humana de git review config en tests/config.bats"
Task: "--porcelain de config, sin candidatas, en tests/config-porcelain.bats"
Task: "--porcelain de config, candidatas y exclusiones, en tests/config-porcelain.bats"
Task: "Parser configPorcelain.spec.ts"
Task: "TraducciÃ³n de ReviewIntent a argv en reviewIntent.spec.ts"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup (T001).
2. Phase 2: Foundational (T002-T009) â€” bloquea la implementaciÃ³n, no los tests.
3. Phase 3: User Story 1 completa (T010-T030).
4. **Parar y validar**: quickstart.md Â§ 2 contra el sandbox.
5. Esto ya es demostrable de punta a punta: desde el estado vacÃ­o hasta una
   review activa, sin la terminal.

### Incremental Delivery

1. Setup + Foundational â†’ infraestructura compartida lista.
2. US1 â†’ se puede iniciar desde el panel â†’ validar â†’ MVP.
3. US2 â†’ se puede cancelar â†’ validar independientemente.
4. US3 â†’ se puede cerrar, y el panel deja de mentir sobre el cierre pendiente â†’
   validar.
5. US4 â†’ el cierre pendiente y el trabado dejan de ser callejones â†’ validar
   (depende de US3 mergeada).
6. US5 â†’ se puede pausar, cerrando el ciclo con `continue` (ya existente) â†’
   validar.
7. US6 â†’ el asistente gana rango y origen â†’ validar (depende de US1 mergeada).
8. Polish â†’ sandbox completo, documentaciÃ³n, suites completas.

### Parallel Team Strategy

Con varias personas, despuÃ©s de Foundational:

- Persona A: US1 (Phase 3) â†’ luego US6 (Phase 8), que depende de su propio US1.
- Persona B: US3 (Phase 5) â†’ luego US4 (Phase 6), que depende de su propio US3.
- Persona C: US2 (Phase 4) y US5 (Phase 7) en paralelo entre sÃ­, sin depender
  de las otras dos personas.
- Todas coordinan el orden de merge de `extension.ts`/`package.json`, el Ãºnico
  punto de archivo compartido entre historias.

---

## Notes

- [P] = archivos distintos, sin dependencia entre sÃ­.
- El verbo `config` (T017-T021) y el asistente de inicio (T024) son la pieza
  mÃ¡s grande de la feature y la que mÃ¡s historias tocan indirectamente (US1 y
  US6 la extienden, US3-US5 sÃ³lo dependen de la Fase 2). Conviene que sea de lo
  primero en mergearse.
- El registro `finish` (T044-T049) es la segunda pieza compartida real: US3 lo
  produce, US4 lo consume. No dividir esa dependencia entre personas distintas
  sin coordinar el punto de corte.
- Confirmar que cada test nuevo falla antes de la implementaciÃ³n
  correspondiente (T010-T016 antes de T017-T024a; T037-T043 y T050a antes de
  T044-T052; T055-T056 antes de T057-T058; T062-T063 antes de T064; T068-T071
  antes de T072-T074).
- **La regla que mÃ¡s fÃ¡cil se pierde en la implementaciÃ³n** es la de no parsear
  la salida humana. El punto donde la tentaciÃ³n es mÃ¡xima es T050: la CLI dice
  con todas las letras "no review changes to apply" y leer esa lÃ­nea serÃ­a lo
  mÃ¡s corto. No se hace â€” se mira el estado posterior. T050a existe para que eso
  quede afirmado por un test, no por una nota.
- No hacer commit por tarea suelta si eso rompe `set -eu`/`shellcheck` o
  `tsc --noEmit` a mitad de camino: agrupar segÃºn haga falta para no dejar el
  checkout roto en ningÃºn commit â€” la regla dura, no la granularidad de la
  lista.
- `--force` (T057) es la Ãºnica acciÃ³n de todo el ciclo que nunca aparece como
  opciÃ³n de primera clase: si en algÃºn momento de la implementaciÃ³n aparece
  como casilla o botÃ³n del primer diÃ¡logo, es una seÃ±al de que FR-021 se estÃ¡
  perdiendo.
