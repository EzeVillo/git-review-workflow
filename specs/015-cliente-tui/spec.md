# Feature Specification: Cliente TUI de terminal, cuarto cliente del monorepo

**Feature Branch**: `015-cliente-tui`

**Created**: 2026-08-30

**Status**: Draft

**Input**: User description: "Cuarto cliente del monorepo: una TUI de terminal que
vive en un pane de tmux, con paridad de superficie con los otros tres clientes
—ni más ni menos que lo que sea lógico a nivel de implementación—, escrita en Go
con bubbletea/lipgloss/bubbles/fsnotify, más el verbo POSIX `git review ui` que
la lanza. Las decisiones técnicas (lenguaje, frontera de código, forma de
invocar la CLI, mecanismo de refresco, vías de distribución) ya están tomadas y
van declaradas como constraints, no reabiertas."

## Contexto y Motivación *(el porqué)*

### El problema

El público que descubre este producto por Hacker News o por un thread **vive en
la terminal**. Hoy recibe la superficie sin panel: la CLI contesta preguntas de
a una, y el estado de la review —el modo, el cursor, el borrador, las guías, las
ramas de ediciones— hay que volver a preguntárselo cada vez. Los tres clientes
que sí tienen panel están atados a un editor, y quien usa nvim, emacs o helix no
tiene ninguno.

### Por qué importa ahora

- La TUI **no** arregla la primera impresión. Eso lo arreglan el demo y la
  landing. Arregla **la segunda semana**: es retención, no descubrimiento.
- Al vivir en un pane de un multiplexor es **agnóstica del editor**: es lo único
  que le sirve a nvim, emacs y helix a la vez sin ser tres plugins más.
- El contrato porcelain de la CLI ya soporta tres consumidores y está gateado en
  el **emisor**, no en cada cliente: `tests/status-porcelain.bats` (40 tests),
  `tests/config-porcelain.bats` (16), `tests/list.bats` (19) y
  `tests/porcelain-bytes.bats` (6, sobre bytes hostiles), más un contrato escrito
  por superficie en `specs/*/contracts/`. Un cuarto consumidor no agrega riesgo
  de formato: agrega un parser.

### Qué habilita

Que el revisor que trabaja en una terminal tenga **el panel**, no una CLI con
ANSI: un pane que no cierra, que se re-renderiza solo cuando el estado cambia, y
donde las acciones son controles en pantalla en vez de comandos que hay que
componer.

### Las tres cosas que la definen

Sin las tres, esto no es un panel:

1. **Vive en un pane que no cerrás.**
2. **Se re-renderiza sola** cuando el estado cambia, sin que nadie se lo pida.
3. **Las acciones son controles en pantalla**, no comandos que el revisor
   compone. Con qué se activa cada uno —una tecla o un clic— es un detalle de
   input, no la propiedad. El canónico ya está escrito en vocabulario de botón
   (`emphasis: primary | secondary | link | icon`, `label:`, los `row:` con sus
   `controls:`), así que dibujar controles de verdad es **más** paridad, no menos.

La diferencia con la CLI **no es la información, es la persistencia**: la CLI
contesta una pregunta, la TUI sostiene la respuesta mientras trabajás. Si el
resultado termina siendo `git review status` con cajas y bordes, está mal —eso ya
es `watch`.

### Qué NO es esto

- **No comparte una sola línea de código con ningún otro cliente.** Es lo
  contrario del motivo por el que se eligió el lenguaje: ver *Restricciones
  técnicas*.
- **No deriva estado por su cuenta.** Todo sale de reinvocar porcelain, igual que
  los otros tres. No lee refs, no lee `git config` de review, no mueve nada.
- **No pollea** como mecanismo de refresco.
- **No tiene pie (`tools_section`) dentro de una review.** Adentro de una review
  estás parado en el PR de otro, y todo lo que cuelga de `walkthrough` es de
  quien está parado en el suyo.
- **No agrega vías de distribución.** Tres, más el binario del GitHub Release:
  Homebrew y los dos one-liner. **npm queda deliberadamente afuera** —ver
  `FR-049`—, y también **Scoop, WinGet y `go install` como vía soportada**.
  Ninguna tienda entra.
- **No inventa superficie de producto.** Paridad significa las **27 acciones** del
  canónico y los tres mapas de controles de fila, ni una más; lo que no tiene
  traducción honesta se declara, no se aproxima.
- **No incluye planificación ni implementación.** Esta spec es el *qué* y el *por
  qué*; el *cómo* es del plan.

## Restricciones técnicas *(decididas, no reabiertas)*

Estas decisiones ya están tomadas. Se registran acá con su rationale porque son
el marco del alcance, no alternativas a evaluar.

### El lenguaje, y por qué la frontera es el punto

**Go**, con `bubbletea` + `lipgloss` + `bubbles` + `fsnotify`: cuatro
dependencias directas, tres del mismo org.

- **La frontera de lenguaje es un requisito, no un efecto colateral.** Se
  descartó Node/Ink *precisamente* porque compartir el parser de porcelain con
  `vscode-extension/` estaría a un `import` de distancia, y el motivo siempre
  parecería bueno en el momento. Un firewall que depende de disciplina no es un
  firewall.
- **El cuarto parser es barato** porque el formato está gateado en el emisor (las
  81 pruebas citadas arriba). Lo que sí hay que replicar es la **tolerancia**:
  campo libre al final del registro, no asumir cantidad de campos, ignorar
  registros desconocidos.
- **Cross-compilation**: un solo runner ubuntu cubre todos los targets. Rust
  pedía `cross` o una matriz de runners reales más `lipo` para el universal de
  macOS.
- **La arquitectura Elm de Bubble Tea es el modelo del problema**: un evento de
  fsnotify, un focus-in, una tecla y el resultado de un verbo son cuatro
  mensajes que entran al mismo `Update`.
- **Bubble Tea es el host.** Los otros tres clientes delegan ciclo de vida a una
  plataforma; acá la librería resuelve alt-screen, restauración del terminal ante
  panic, resize y focus reporting.
- **Se descartó Rust**: no hay performance crítica, ni FFI, ni `unsafe`, ni
  presión de memoria. No compra nada y cobra compile times, curva y matriz de CI.
- **Riesgo declarado**: el ecosistema TUI de Go es prácticamente un solo vendor.
  Mitigación: la arquitectura Elm es portable y el layout vive declarado afuera,
  en el canónico.

### Cómo la TUI invoca la CLI

**Siempre `git review <verbo> …`. Nunca resolver el dispatcher a mano.**

`bin/git-review` es un script de shell sin extensión con `#!/usr/bin/env sh`.
Para Windows eso **no es un ejecutable**: `CreateProcess` corre `.exe`/`.com`/
`.bat`/`.cmd` y no lee shebangs. `git review` funciona en Windows porque lo
ejecuta **git**, con su capa MSYS y su `sh.exe` embebido. Spawneando el
dispatcher directo, lo que hay en disco cambia según la instalación: npm deja un
shim `.cmd` que termina llamando al `sh` del PATH (y si no hay, muere — ya mordió
a la extensión de VS Code), `web-install.ps1` deja el script sin shim
(`CreateProcess` falla), Homebrew deja un symlink (funciona). Invocar `git` es
**una sola forma** en las tres instalaciones y los tres sistemas operativos.

Corolario del argv: llamando a `git`, la palabra `review` la consume git y el
dispatcher recibe `$1=<verbo>`; llamando al dispatcher directo el verbo va
primero. `resolveCommand` en `vscode-extension/src/cli/invoke.ts` tiene esto
comentado y elige `git` por default — la TUI hace lo mismo, **sin** el fallback
de path configurable que aquel cliente ofrece.

Beneficios: `git` está garantizado; se usa **el mismo git que el usuario**; y si
`git review` no anda en su shell, la TUI falla igual en vez de esconder una
instalación rota detrás de un camino privado. Costo aceptado: un proceso extra
por invocación (~50 ms en Windows), ruido frente a un refresco que es por evento
y no un poll.

### El verbo `git review ui`

Verbo POSIX real en `bin/git-review-verbs/ui`, con `prog="git review ui"`,
`set -eu` y shell POSIX puro, como los quince que ya existen. Resolución en
orden: `$GIT_REVIEW_UI` → `git-review-ui` en el `PATH` → si no está, **rechaza
con un hint accionable** (el patrón que el proyecto ya usa: negarse, no
preguntar ni actuar por el usuario). Hace `exec`. Quince líneas, cero
acoplamiento: si mañana la TUI se reescribe en otro lenguaje, este verbo no
cambia un byte.

Ventaja lateral: el verbo aparece en `git review -h` **desde el día uno**, así
que la TUI es descubrible *antes* de existir en la máquina.

### Los tres nombres, y por qué el binario va al `PATH`

Son tres cosas distintas y conviene no confundirlas:

- **`git review ui`** es el **punto de entrada canónico y documentado**. Es el
  único que funciona *antes* de que la TUI exista en la máquina —es el que imprime
  el hint de instalación— y el único que aparece en `git review -h`.
- **`git-review-ui`** es el ejecutable. Va al `PATH` porque **es el único lugar
  donde dos programas instalados por separado se encuentran**: la TUI la deja
  Homebrew o el instalador en su propio prefijo y no puede escribir en el libexec
  de la CLI. Es exactamente por eso que `git-lfs`, `git-crypt` y `git-absorb`
  viven ahí.
- **`git review-ui`** es la consecuencia: git descubre como subcomando cualquier
  `git-*` que encuentre en el `PATH`.

**Esto no es una excepción a ninguna regla del proyecto.** La regla de
`../../AGENTS.md` dice que **los verbos** son privados y no van al `PATH`, para que git
no los descubra como `git <verbo>` y el único punto de entrada sea el dispatcher.
La TUI **no es un verbo**: es un programa aparte, instalado aparte, que git expone
por la convención `git-*` de terceros, igual que `git lfs`. La regla queda
intacta.

Los dos README nombran `git review ui` como la forma de invocarla y mencionan
`git review-ui` en una línea, como el sinónimo que git expone solo — sin pedir
disculpas y sin convertirlo en una segunda forma documentada.

## Superficie consolidada (lo que la TUI tiene que ofrecer)

Fuente normativa: `contracts/client-product-surface.yaml` y el código de la CLI.
La TUI es un **cuarto consumidor** del mismo canónico.

### Las ocho situaciones

Las mismas ocho, con las mismas reglas de prioridad: `cli-missing`,
`cli-outdated`, `no-review`, `finish-pending`, `review`, `finish-conflict`,
`out-of-range`, `error`. Más la **superficie de espera** («todavía no miré»), que
no es una situación: se dibuja `waiting_text` hasta que hay un veredicto, y las
tres situaciones que son respuestas sobre el entorno no se repintan de memoria.

**`cli-missing` y `cli-outdated` no son un renglón: son dos situaciones de panel
completas**, con los mismos seis bloques que en los otros tres clientes. Al
bajarlas a una terminal aparecen dos choques que hay que resolver, no esquivar:

- **Copiar el comando de instalación al portapapeles.** Por SSH o dentro de un
  multiplexor no hay portapapeles del sistema: la vía es el portapapeles mediado
  por el terminal, que funciona en la mayoría de los setups modernos y en algunos
  está restringido por seguridad. Cuando no se puede, el fallback es mostrar el
  comando en una línea limpia y seleccionable — que **exige apagar el reporte de
  mouse**, así que el control de copiar y el toggle de mouse son la misma
  conversación.
- **`reload_or_wait` contradice el diseño.** El string compartido dice que se
  recargue la ventana o se espere, porque «el panel vuelve a chequear cada pocos
  segundos». En una terminal no hay ventana que recargar, y volver a chequear cada
  pocos segundos **es un poll**. La TUI no dibuja esa copy tal cual: cae bajo la
  exención de `strings:` que queda por resolver.

### Las 27 acciones, clasificadas

Esta clasificación **es el alcance**, no una sugerencia.

| Clase | Cuántas | Acciones |
|---|---|---|
| **Nativas** | 22 | `showWhy`, `next`, `prev`, `goToEntry`, `refresh`, `installCli`, `continueReview`, `startReview`, `setBase`, `setRemote`, `abortReview`, `saveReview`, `finishReview`, `undoFinish`, `resumeFinish`, `discardInventory`, `cleanReview`, `forgetReview`, `previewEditsStat`, `walkthroughInit`, `walkthroughBuild`, `showCliLog` |
| **Delegadas** | 4 | `openEntry`, `openChange` → `$EDITOR`; `previewEdits`, `compareReview` → `git difftool` / `$PAGER` con el color de git |
| **`not_in: [tui]`** | 1 | `openAllChanges` |

Cuatro que se clasifican mal fácil, y por qué caen donde caen:

- **`showCliLog` no es una acción de editor.** Es la **tercera capa** de la regla
  de copy —el detalle técnico siempre a un clic—. En la TUI es un overlay o
  `$PAGER`.
- **`previewEditsStat` es `--stat`**, o sea texto: nativa. (`previewEdits` sin
  `--stat` es un diff, y ahí sí gana el difftool del usuario.)
- **`goToEntry` es un picker**, y es la superficie que mejor le queda a una TUI.
- **`walkthroughInit` y `walkthroughBuild` son mutaciones nativas.** Lo único que
  se delega es la cola de «y después abre el archivo».

**Por qué delegar es la respuesta correcta y no una renuncia:** quien vive en un
multiplexor ya tiene `$EDITOR`, `diff.tool` y `$PAGER` configurados mejor de lo
que esta TUI los va a resolver. Reimplementar un visor de diffs adentro del pane
sería peor que lo que el revisor ya eligió, y sería la primera cosa de este
cliente que no respeta lo que la máquina ya sabe.

**`openAllChanges` no tiene traducción honesta.** Abrir N diffs de golpe en un
multiplexor no existe como gesto. Va al canónico con el motivo al lado,
exactamente como está hoy la divergencia de Visual Studio, y se verifica en las
**dos direcciones**.

### Controles de fila

`draft_controls:`, `guide_rows.controls:` y `fixes_rows.controls:` existen los
tres, completos. **No tocan el conteo de 27**: no van a `contributes.commands`,
ni al menú *Tools → git review*, ni al `.vsct`, ni a la lista de acciones de la
TUI. Colar uno como acción falla CI.

### El problema de las dos superficies

El canónico declara `surface: panel | action | both`, donde `action` significa
paleta de comandos (VS Code), menú *Tools* (JetBrains) o `.vsct` (Visual
Studio). **La TUI tiene una sola superficie visible.** Sin un equivalente, las
cuatro de `panel_excluded: [goToEntry, forgetReview, previewEditsStat,
showCliLog]` se quedarían sin ninguna.

El equivalente es **una tecla que abre la lista completa de acciones** —un
overlay que enumera todo lo que la situación actual habilita, con su tecla al
lado donde la tenga—. Es la paleta de comandos de este cliente, y las cuatro
excluidas del cuerpo viven **sólo** ahí, igual que en los otros tres.

## El refresco: lo único genuinamente nuevo

Los paneles de IDE se enteran porque el host les avisa. **La TUI no tiene host.**
Esto se resuelve antes de dibujar una sola caja.

**No pollear.** Ese impuesto ya se pagó una vez (los ~28 s de `status
--porcelain` en walk) y en Windows cada proceso cuesta ~50 ms. Un `status` cada
dos segundos es una CLI corriendo para siempre.

Los cuatro disparadores, en orden de importancia:

1. **Re-render después de cada acción que causó la propia TUI.** Gratis: sabés
   que pasó.
2. **Vigilancia del sistema de archivos sobre CONTENEDORES, no sobre refs
   finos**, con debounce (~200 ms) y coalescencia. Los directorios:
   `<git-common-dir>/` filtrado a `config` y `packed-refs`;
   `<git-common-dir>/refs/`; `<git-common-dir>/reftable/` si existe;
   `<git-dir>/review-walkthrough/`; `<git-dir>/review-saved-walkthrough/`. El
   trigger es **grueso a propósito**: sólo dice «reinvocá `status --porcelain`»,
   no deriva estado, así que un falso positivo cuesta un proceso y nada más.
3. **Focus reporting.** Un refresco en focus-in es el mismo evento que los
   paneles de IDE usan para agarrar cambios externos (*window activated*), y
   cubre el caso real —«me fui a otra terminal, hice cosas, volví»— con **cero
   procesos en reposo**. Caveat: en tmux `focus-events` viene **apagado por
   default**; la TUI lo pide y **degrada sin romperse** si no lo consigue.
4. **La tecla `r`**, siempre, como escape hatch garantizado.

### Los cuatro agujeros, cada uno con su test

1. **`git config` se escribe con rename atómico** (`config.lock` → `config`): un
   watch sobre el *archivo* deja de disparar cuando el inode se reemplaza. Hay
   que mirar el **directorio** y filtrar por nombre. Idem `packed-refs`.
2. **`refs/review-*` puede no existir como archivo**: `git gc` / `git pack-refs`
   los mete en `packed-refs`. Y con el backend **reftable** `refs/` no existe:
   todo vive en `<git-common-dir>/reftable/`.
3. **La vigilancia no es recursiva, a propósito** —lo cual coincide con vigilar
   contenedores—, y `refs/review-edits/<src>/<step>` está dos niveles adentro.
4. **inotify tiene agujeros reales**: no cruza un bind mount Windows→WSL y en
   varios NFS/SMB no dispara nunca. Falla **en silencio**, que es el peor modo de
   falla para lo único que sostiene «se re-renderiza sola». Mitigación: la tecla
   `r`, más un **piso de poll opt-in por configuración, apagado por default** y
   nunca como mecanismo.

### La vigilancia es un acelerador, no un cimiento

Vigilar esos directorios **es** una dependencia de la disposición interna de git,
que git considera un detalle de implementación —el backend de refs sin directorio
`refs/` es la prueba de que cambia—. La fragilidad se acota haciendo que no
sostenga nada:

- La vigilancia **nunca lee** el contenido de una ruta vigilada: no parsea un ref
  ni lee `config`. Produce un solo tipo de mensaje, sin payload: «reinvocá
  `status --porcelain`».
- Por eso los dos modos de falla son baratos. Un **falso positivo** cuesta un
  proceso. Un **falso negativo** deja el panel viejo hasta el próximo focus-in, la
  próxima acción o la tecla de refresco — los otros tres disparadores, que ya
  existen y no dependen del sistema de archivos.
- **La TUI es completamente correcta y usable con la vigilancia apagada.** Ése es
  el requisito que convierte la fragilidad en irrelevancia: si git cambia su
  almacenamiento mañana, la TUI no se rompe, tarda más en enterarse.
- La vigilancia es **best-effort**: una ruta que no existe se ignora en silencio y
  nunca es un error.

### El lock de mutación

Mientras corre un verbo, el watch dispara N veces —el verbo mismo escribe config
y refs—. Hay que **suprimir los refrescos disparados por el watch durante la
invocación y hacer uno solo al final**. Sin eso, un `finish` repinta cinco veces.
Es el mismo lock que ya existe en los *Host* de JetBrains y de Visual Studio.

## Lo que el canónico tiene que ganar

Regla del proyecto: **una tabla sin gate nace decorativa**. Todo lo que sigue va
con gate.

- **`reveals:` para la TUI no es una ausencia: es una lista vacía declarada con el
  motivo.** Un pane que abriste vos no se revela, y robarle el foco a alguien en
  un multiplexor es agresión. Si queda como ausencia, en seis meses alguien
  agrega un reveal y nada se pone rojo.
- **`confirms:` aplica entero**, y la TUI necesita **su única puerta**: el cuarto
  equivalente de `UiMessages.confirm` / `GitReviewDialogs.Confirm` /
  `confirmMutation`. Un modal en una TUI es un overlay; que haya **uno solo**.
  Los tres gates de siempre: la tabla del cliente == el canónico, todo id
  declarado **pasa por la puerta leyendo el argumento** (no buscando el nombre
  suelto en el archivo), y **no hay ningún otro modal**. Única excepción,
  declarada: `walkthroughInit`, que elige entre dos cursos en vez de confirmar.
- **`icon_vocabulary:`** — los cinco nombres (`prev`, `next`, `file`, `trash`,
  `diff`) se contestan desde **un solo mapa**. Los glifos tienen que ser de
  **ancho no ambiguo**: nada de emoji en el layout, porque el ancho ambiguo rompe
  las columnas. Fallback ASCII cuando el terminal no da.
- **`panel_layout:` aplica**, con el **tope del 55% del pie** y **una sola barra
  de scroll**. En un pane de 40 filas eso importa más que en un IDE, no menos.
- **`min_cli_version` propio para la TUI.**
- **`listing:` NO aplica** (no hay ficha de tienda) y **eso se declara**, no se
  deja como hueco.
- **`not_in:` se verifica en las dos direcciones**, como hoy.
- **Advice**: **un solo lugar** en el invocador de la TUI exporta
  `GIT_REVIEW_ADVICE=0`. Sin eso, la TUI reenvía las notas que sus propias teclas
  ya cubren.
- **El gate en CI**: `scripts/check-client-product-surface.mjs` tiene que aprender
  a leer los archivos de dominio del cuarto cliente. Está en alcance. Del lado del
  cliente, además, un test de layout equivalente a `PanelLayoutContractTest` /
  `PanelLayoutContractTests`.

## Controles, teclas y mouse

El panel dibuja **controles**: botones con su etiqueta, filas con su botonera,
secciones plegables — el mismo `panel_layout:` que los otros tres, en caracteres.
Se activan de dos formas, y el teclado es la completa.

### Teclado (completo y primario)

- **vim-first, flechas como alias.** `j`/`k` para moverse por filas; letras
  mnemónicas para las acciones; **`n`/`p` reservadas para el cursor de la
  review** (`git review next` / `prev`), que es un concepto distinto de navegar
  la lista. Las flechas funcionan igual.
- **Barra de teclas visible**, y es el equivalente exacto del botón: **si la
  tecla está en pantalla, la tecla ES el texto**. La regla de copy de que el
  próximo paso sólo se dice si está *fuera* del panel aplica igual acá.
- **El teclado alcanza y activa TODOS los controles.** Nunca hay uno que sólo
  responda al mouse. Es lo que hace que agregar mouse no le saque nada a nadie.

### Mouse (encendido por default, con toggle)

- El reporte de mouse del terminal va **encendido por default**, como en lazygit,
  gitui, k9s y btop. Un panel cuyos botones parecen botones y no se pueden
  clickear es peor que uno sin botones.
- **Con el reporte activo, el terminal deja de hacer la selección nativa por
  arrastre.** El escape habitual es Shift+arrastre, y no todos los terminales lo
  dan. Por eso hay **una tecla que apaga el mouse** y devuelve la selección
  nativa, con su estado visible en el panel. Es la misma tecla que hace
  seleccionable el comando de instalación cuando el portapapeles del terminal no
  está disponible.
- En un multiplexor el usuario necesita habilitar el mouse para que los eventos
  lleguen al pane. La TUI **no lo configura ni lo exige**: sin mouse, el teclado
  ya alcanza todo.

## Distribución y release

**Homebrew y los dos one-liner** (`web-install.sh` y `web-install.ps1`), más los
binarios del GitHub Release. **npm queda afuera**, y es la única vía de la CLI que
la TUI no hereda.

- **Por qué npm no.** npm es un buen transporte para la CLI porque la CLI es un
  script de shell. Para un binario estático es el peor de los cuatro: `bin` en un
  `package.json` mapea a **un** archivo, así que un paquete con varios binarios
  necesita un shim que elija —y ese shim es JavaScript, o `sh`, que en Windows es
  peor—. O sea que instalar la TUI por npm **pediría Node para correr un binario
  de Go**: exactamente la dependencia de runtime que motivó elegir el lenguaje,
  reintroducida en una sola vía. Sumado a que el tarball llevaría todas las
  plataformas y a que vendorear ejecutables en npm rompe el bit de ejecución en
  silencio, no paga.
- **Y nadie queda bloqueado.** El binario del Release es un archivo: no necesita
  registro, ni runtime, ni gestor de paquetes. Se baja con `curl`, con `wget`, con
  el navegador o con un `COPY` en un Dockerfile. Es el artefacto **más** portable
  de los cuatro. Lo que cambia es la ergonomía de quien busca `npm i -g` por
  costumbre, y a ése le contesta el hint del verbo.
- **Homebrew: fórmula propia** con binario prebuilt. La fórmula de la CLI **no se
  toca** —hoy es `depends_on "git"` y nada más, y ese es el punto de esa vía—.
- **Tags `tui-v*`**, workflow propio, `bump-version.sh` propio y fila propia en
  `tests/version-consistency.bats`.
- **GitHub Release con `--latest=false`**, por la misma razón exacta que el plugin
  de JetBrains: `web-install.sh` y `web-install.ps1` resuelven `releases/latest`
  para elegir el ref de la CLI, así que un release de cliente marcado *latest*
  haría que el instalador de la CLI se pare en un tag ajeno.

## Documentación

- **Los DOS README** (`README.md` y `README.es.md`) se actualizan en el mismo
  cambio: el verbo `ui`, el alias `git review-ui` declarado, y las vías de
  instalación de la TUI.
- **La landing** (`docs/index.html`) duplica los métodos de instalación y es
  bilingüe en un solo archivo —inglés en el HTML, español en el diccionario `ES`,
  emparejados por `data-i18n`—: si la sección de instalación cambia, se editan
  **las dos puntas**.
- **`CONTRIBUTING.md` propio del cliente**, como los otros tres.
- **Ninguna superficie que le llegue a quien instala nombra a los otros tres
  clientes ni dice «paridad con X».** Eso se cuenta en `CONTRIBUTING.md` y en
  `../../AGENTS.md`.

## Compatibilidad de terminal

Respetar `NO_COLOR`. Fallback ASCII para el box-drawing cuando el terminal o el
locale no dan. **Nada de emoji en el layout.** Objetivo: Windows Terminal,
conhost con VT, macOS Terminal, iTerm2, tmux, screen y los terminales de Linux.

## User Scenarios & Testing *(mandatory)*

El actor es el **revisor que trabaja en una terminal**, con un multiplexor
abierto y su editor en otro pane. Se asume git instalado y la CLI instalada o
instalable.

### User Story 1 - Un panel que vive en un pane y se entera solo (Priority: P1)

El revisor abre un pane, lanza la TUI y la deja abierta. Mientras trabaja en el
pane de al lado —edita, corre tests, corre verbos de `git review` a mano, deja a
un agente llenando el borrador— el panel se actualiza solo, sin que él lo pida y
sin que la máquina gaste procesos en reposo.

**Why this priority**: es la única diferencia entre esto y `git review status`
con bordes. Sin refresco por evento no hay producto, hay un `watch`.

**Independent Test**: sandbox con review activa; con la TUI abierta y sin tocarla,
mutar el repo desde otro pane (`git review next`, escribir el borrador, `git
pack-refs`, `git review config base`) y verificar que el panel refleja cada
cambio; medir que en reposo no se lanza ningún proceso.

**Acceptance Scenarios**:

1. **Given** la TUI abierta sobre una review walk, **When** en otro pane se corre
   `git review next`, **Then** el panel muestra la entrada nueva sin que nadie
   apriete nada.
2. **Given** la TUI abierta y el revisor sin tocar el teclado, **When** pasan
   varios minutos, **Then** no se lanza ni un proceso de `git review`.
3. **Given** la TUI abierta, **When** un agente escribe el borrador del revisor
   en el gitdir, **Then** la fila del borrador actualiza su par de progreso sola.
4. **Given** una mutación larga lanzada desde la TUI que escribe config y refs
   varias veces, **When** termina, **Then** el panel se repinta **una** vez, no
   una por evento.
5. **Given** un entorno donde la vigilancia del sistema de archivos no dispara
   (montaje de red, bind mount), **When** el estado cambia por fuera, **Then** la
   tecla de refresco lo trae y el panel no queda mintiendo para siempre.
6. **Given** tmux con `focus-events` apagado, **When** la TUI arranca, **Then**
   pide el reporte de foco y sigue funcionando con los otros tres disparadores si
   no lo consigue.
7. **Given** la TUI corriendo con la vigilancia del sistema de archivos
   **enteramente apagada**, **When** el revisor opera el panel entero, **Then**
   todo funciona igual y ningún dato que el panel muestra es incorrecto — sólo
   deja de enterarse solo de los cambios externos.

---

### User Story 2 - Instalar, descubrir y arrancar (Priority: P1)

El revisor se entera de que existe una TUI **desde la ayuda de la CLI que ya
tiene**, la instala por la misma vía por la que instaló la CLI, y la lanza con
`git review ui`. Si todavía no la tiene, el verbo se lo dice y le da el comando.

**Why this priority**: es la primera impresión y la única forma de que la TUI se
descubra sin leer el README.

**Independent Test**: máquina con la CLI y sin la TUI: `git review -h` la lista y
`git review ui` se niega con un hint que instala. Después de instalar, el mismo
comando la abre.

**Acceptance Scenarios**:

1. **Given** una CLI que trae el verbo y ninguna TUI instalada, **When** corre
   `git review ui`, **Then** obtiene un exit distinto de cero y un mensaje en
   `stderr` que dice qué falta y cómo instalarlo — sin preguntar ni instalar por
   su cuenta.
2. **Given** la TUI instalada, **When** corre `git review ui`, **Then** el verbo
   la reemplaza en el mismo proceso, y el código de salida de la TUI es el que ve
   la shell.
3. **Given** la variable de entorno que apunta al ejecutable, **When** corre el
   verbo, **Then** gana esa ruta sobre lo que haya en el `PATH`.
4. **Given** la TUI instalada, **When** corre `git review-ui`, **Then** obtiene
   exactamente lo mismo, y ese alias está documentado en los dos README.
5. **Given** una CLI ausente o anterior al mínimo del cliente, **When** la TUI
   arranca, **Then** dibuja la situación correspondiente con el comando de
   instalación copiable — y **no** la confunde con un timeout.
6. **Given** esa misma situación en un terminal donde el portapapeles mediado no
   está disponible, **When** usa el control de copiar, **Then** el comando queda
   en una línea limpia seleccionable y el panel dice cómo seleccionarlo — nunca
   afirma haber copiado algo que no copió.

---

### User Story 3 - Leer el estado y operar el panel (Priority: P1)

Con una review activa, el revisor ve el modo, la posición, la entrada actual y
sus marcas; se mueve por la lista con `j`/`k` o flechas, mueve el cursor de la
review con `n`/`p`, salta a una entrada cualquiera con el picker sin mover el
cursor de la CLI — y puede hacer todo eso clickeando los controles, que se ven y
se comportan como botones.

**Why this priority**: es el flujo diario de lectura guiada, y es donde se decide
si el panel es una UI o una lista de atajos.

**Independent Test**: sandbox con review walk, step y whole; contrastar cada campo
del panel contra `git review status --porcelain` en otro pane, y recorrer la
secuencia entera **dos veces**: una sólo con teclado y otra sólo con mouse.

**Acceptance Scenarios**:

1. **Given** una review walk con el cursor en la entrada 2 de 7 y la 3 marcada
   `key`, **When** mira el panel, **Then** ve la entrada 2, la posición 2/7 y la
   3 distinguida en la lista.
2. **Given** la lista de entradas, **When** se mueve con `j`/`k`, **Then** cambia
   la fila enfocada y **no** se mueve el cursor de la review.
3. **Given** la misma review, **When** aprieta `n`, **Then** la CLI mueve el
   cursor y el panel muestra la entrada nueva.
4. **Given** `finish-conflict`, **When** intenta mover el cursor, **Then** esas
   teclas no están disponibles y la barra de teclas no las ofrece.
5. **Given** una entrada cualquiera de la lista, **When** usa el picker, **Then**
   se abre esa entrada **sin** cambiar el cursor de la CLI.
6. **Given** un walkthrough degradado a whole, **When** mira el panel, **Then**
   ve la nota de degradación y la review sigue usable.
7. **Given** cualquiera de las ocho situaciones, **When** recorre el panel **sólo
   con el teclado**, **Then** alcanza y activa todos los controles que esa
   situación habilita, sin excepción.
8. **Given** el mouse encendido, **When** clickea un control, **Then** hace
   exactamente lo mismo que su tecla, y el control que está bajo el cursor se
   distingue del resto.

---

### User Story 4 - Abrir archivo, diff y why (Priority: P1)

El revisor abre el archivo de la entrada en **su** editor, el diff en **su**
difftool o pager, y lee el *why* dentro del panel.

**Why this priority**: sin esto el panel es un cartel; con las historias 1 y 3
forma el mínimo instalable.

**Independent Test**: para cada modo, abrir entrada, cambio y *why*, con paths
con espacio y no-ASCII; verificar que lo que se abre es el path correcto y que la
herramienta usada es la que el usuario configuró.

**Acceptance Scenarios**:

1. **Given** una entrada con path con espacios y acentos, **When** abre el
   archivo, **Then** se abre el path correcto en el editor configurado.
2. **Given** la misma entrada, **When** abre el diff, **Then** lo ve con la
   herramienta de diff del usuario y el color de git, no con un visor propio.
3. **Given** una entrada walk con *why* escrito, **When** lo muestra, **Then** el
   texto coincide con el que la CLI devuelve para el path **crudo** de esa
   entrada.
4. **Given** un archivo eliminado en el rango, **When** abre la entrada, **Then**
   no hay error fatal y el resultado es informativo.
5. **Given** una review whole, **When** busca «abrir todos los cambios», **Then**
   esa acción **no existe** en esta TUI, y su ausencia está declarada en el
   canónico con el motivo.

---

### User Story 5 - El ciclo de riesgo, con una sola puerta (Priority: P1)

El revisor arranca una review con el asistente, la pausa, la aborta, la cierra,
deshace el cierre y reanuda un cierre en conflicto. Lo que no se puede deshacer
pregunta; lo demás no.

**Why this priority**: es el ciclo que ya es producto en los otros tres, y donde
un cartel de más o de menos cuesta trabajo del revisor.

**Independent Test**: sandbox sin review; configurar la base, arrancar con el
asistente en cada forma de lectura, guardar, continuar, cerrar, deshacer y
abortar; contrastar cada argv contra el contrato de invocación.

**Acceptance Scenarios**:

1. **Given** un repo sin base configurada, **When** mira el panel, **Then** ve
   sólo el paso de configurar base y remote, sin un *Start* engañoso.
2. **Given** base configurada, **When** completa el asistente, **Then** ve **sólo**
   las formas de lectura que la CLI reporta como viables, y al terminar la última
   pregunta la review arranca **sin** un cartel de confirmación.
3. **Given** una review activa, **When** aprieta abortar, **Then** aparece **una**
   confirmación, la del único punto de confirmación del cliente, y sólo entonces
   se aborta.
4. **Given** un cierre que quedó pendiente, **When** mira el panel, **Then** ve
   su banner con los dos controles y **ningún** aviso que repita en prosa lo que
   los controles ya dicen.
5. **Given** un cierre en conflicto, **When** lo reanuda, **Then** el argumento de
   destino se usa **sólo** si el porcelain de la review lo reporta.
6. **Given** una mutación en curso, **When** dispara otra, **Then** la segunda se
   descarta con un aviso, no se encola.

---

### User Story 6 - El pie: walkthrough, guías, borradores y ediciones (Priority: P2)

Fuera de una review, el revisor ve y opera el pie completo: la fila del
walkthrough con sus dos verbos, las dos guías de autoría, los borradores frescos
y los gastados, las ramas de ediciones que dejó un cierre, la configuración y el
soporte. Adentro de una review, el pie **no existe**.

**Why this priority**: es la mitad del panel que no es la lectura, y la que hace
que el revisor no tenga que deletrear rutas en una terminal.

**Independent Test**: sandbox sin review, con borrador fresco, borrador gastado,
guías en los tres estados y al menos una rama de ediciones; recorrer cada fila y
cada control; después entrar en una review y verificar que ninguna sección del
pie se dibuja.

**Acceptance Scenarios**:

1. **Given** un repo sin review y con walkthrough presente, **When** mira el pie,
   **Then** ve la fila del walkthrough nombrada por su rama, con su badge de
   estado y sus dos verbos.
2. **Given** las dos guías, una con contenido y otra ausente, **When** mira el
   pie, **Then** ve **las dos filas** con badges distintos y el control correcto
   habilitado en cada una.
3. **Given** un borrador a medio llenar, **When** mira su fila, **Then** ve el par
   de progreso y el control de arrancar apagado, con el motivo a mano.
4. **Given** ramas de ediciones de cierres anteriores, **When** mira la sección
   correspondiente, **Then** las ve una por fila con su badge, y la rama en la que
   está parado no ofrece borrarse.
5. **Given** una review activa, **When** mira el panel, **Then** **no** hay
   ninguna sección de pie.
6. **Given** un pane bajo y varias secciones abiertas, **When** el pie crece,
   **Then** ocupa a lo sumo el 55% del alto y scrollea **con una sola barra**, sin
   recortar contenido.

---

### User Story 7 - La lista completa de acciones y el housekeeping (Priority: P2)

Lo que no tiene lugar en el cuerpo del panel vive detrás de una tecla que abre la
lista completa de acciones: saltar a una entrada, olvidar estado persistente, ver
el *stat* de las ediciones y leer el registro de invocaciones.

**Why this priority**: menos frecuente que el ciclo diario, pero es lo que
impide que cuatro acciones del canónico se queden sin ninguna superficie.

**Independent Test**: para cada situación, abrir la lista y comprobar que enumera
exactamente las acciones que esa situación habilita, incluidas las cuatro que no
se dibujan en el cuerpo.

**Acceptance Scenarios**:

1. **Given** cualquier situación, **When** abre la lista de acciones, **Then**
   enumera las acciones habilitadas ahí, con su tecla al lado donde la tengan.
2. **Given** una review activa, **When** abre la lista, **Then** encuentra las
   cuatro acciones que el cuerpo no dibuja.
3. **Given** una acción destructiva elegida desde la lista, **When** la confirma,
   **Then** pasa por la **misma** puerta de confirmación que si se hubiera
   apretado en el cuerpo.
4. **Given** una invocación que falló, **When** abre el registro de invocaciones,
   **Then** ve el comando, el directorio, la duración y el error — el detalle
   técnico a un solo gesto y nunca en la primera capa.

---

### User Story 8 - El pane real: tamaños, colores y terminales (Priority: P1)

La misma TUI se comporta bien en un pane de 80×24 y en uno de 120×40, con y sin
color, con y sin soporte de dibujo de cajas, en Windows Terminal, macOS,
Linux, tmux y screen.

**Why this priority**: un panel que se descuadra en el pane real no es un panel,
y este cliente no puede ser «sólo macOS con una fuente Nerd».

**Independent Test**: renderizar el mismo estado a los dos tamaños fijos y
comparar contra archivos de referencia; repetir con el color apagado y con el
fallback ASCII forzado.

**Acceptance Scenarios**:

1. **Given** un pane de 80×24, **When** dibuja cualquiera de las ocho
   situaciones, **Then** ninguna línea se desborda ni se corta a mitad de una
   columna.
2. **Given** la variable que apaga el color, **When** dibuja, **Then** no emite
   secuencias de color y todo sigue siendo legible sin ellas.
3. **Given** un terminal o locale que no banca el dibujo de cajas, **When**
   dibuja, **Then** cae al juego ASCII sin perder ninguna fila.
4. **Given** cualquier fila con icono, **When** dibuja, **Then** el glifo es de
   ancho no ambiguo y las columnas de todas las filas caen alineadas.
5. **Given** el pane redimensionado mientras la TUI corre, **When** cambia el
   tamaño, **Then** el layout se rehace sin quedar corrupto.
6. **Given** un fallo inesperado, **When** el proceso muere, **Then** el terminal
   queda restaurado (sin alt-screen colgada ni cursor escondido).
7. **Given** un terminal o un multiplexor que no entrega eventos de mouse,
   **When** la TUI arranca, **Then** dibuja los mismos controles y todo se opera
   con el teclado, sin un mensaje de error ni una degradación visible.
8. **Given** el mouse encendido, **When** el revisor aprieta la tecla que lo
   apaga, **Then** recupera la selección nativa por arrastre del terminal y el
   panel muestra que el mouse quedó apagado.

---

### Edge Cases

- **Config reescrito por rename**: el estado cambia y el archivo vigilado ya no
  es el mismo inode. Sin vigilar el directorio, el panel se queda clavado.
- **`git gc` / `git pack-refs` en el medio**: los refs de review dejan de existir
  como archivos sueltos y pasan a `packed-refs`.
- **Backend `reftable`**: no hay directorio `refs/` que vigilar.
- **Worktree enlazado**: las guías y los datos comunes viven en el directorio
  común, y el borrador en el del worktree. Vigilar el equivocado deja media
  pantalla muerta.
- **Ráfaga de eventos durante una mutación**: sin lock, un cierre repinta cinco
  veces.
- **El conjunto de directorios a vigilar cambia** (nace la carpeta del primer
  borrador de una rama): rehacerlo en cada refresco pierde justo los eventos que
  llegan mientras se rehace.
- **`$EDITOR` no configurado o inexistente**: se dice qué no pasó, no qué comando
  falló.
- **`$EDITOR` o el difftool son de pantalla completa** y se comen el pane: al
  volver, la TUI recupera la pantalla y refresca.
- **La CLI muere sin `stderr`**: el fallback dice qué no pasó; con `stderr` no se
  toca nada.
- **La CLI tarda**: un timeout **no** es una CLI ausente; se dice que tardó y
  dónde mirar.
- **`cwd` fuera de un repositorio git**: situación de error accionable, no una
  pantalla en blanco.
- **Pane más chico que el mínimo dibujable**: se degrada a algo legible en vez de
  romper el layout.
- **Terminal sin reporte de foco**: se pierde el disparador 3 y quedan los otros
  tres.
- **Una CLI anterior a la que trae `--porcelain` de borrador**: el acuse se cae
  entero y el cliente se calla, en vez de inventar uno.

## Requirements *(mandatory)*

### Functional Requirements

**El verbo y su frontera**

- **FR-001**: El proyecto MUST agregar un verbo `ui` como ejecutable de shell
  POSIX en `bin/git-review-verbs/`, con `set -eu` y `prog="git review ui"`, igual
  que los quince verbos existentes.
- **FR-002**: El verbo MUST resolver el ejecutable de la TUI en este orden:
  variable de entorno dedicada, luego `git-review-ui` en el `PATH`; y MUST
  reemplazarse por él (`exec`) para que señales y código de salida pasen sin
  intermediarios.
- **FR-003**: Con la TUI ausente, el verbo MUST **negarse** con exit distinto de
  cero y un mensaje en `stderr` que nombre qué falta y cómo instalarlo; MUST NOT
  preguntar, instalar ni actuar por el usuario.
- **FR-004**: El verbo MUST NOT conocer el lenguaje ni la implementación de la
  TUI: reescribir la TUI en otro lenguaje MUST NOT requerir tocarlo.
- **FR-005**: El verbo MUST aparecer en `git review -h` y en las tres
  completions del repo desde la versión que lo introduce.
- **FR-006**: El ejecutable de la TUI MUST llamarse `git-review-ui` y MUST
  instalarse en el `PATH`, porque es el único lugar donde dos paquetes instalados
  por separado se encuentran. Los dos README MUST nombrar `git review ui` como la
  forma de invocarla y MUST mencionar en una línea el sinónimo `git review-ui`
  que git deriva de la convención `git-*` de terceros. Esto MUST NOT presentarse
  como una excepción a la regla del proyecto: esa regla alcanza a **los verbos**,
  que siguen siendo privados y fuera del `PATH`.

**Invocación de la CLI**

- **FR-007**: La TUI MUST invocar siempre `git review <verbo> …` y MUST NOT
  resolver ni ejecutar el dispatcher por su cuenta, en ningún sistema operativo.
- **FR-008**: La TUI MUST NOT ofrecer un ajuste de ruta al dispatcher.
- **FR-009**: La TUI MUST exportar el apagado de las notas de *advice* en **un
  solo lugar** de su invocador.
- **FR-010**: La TUI MUST decodificar `stdout`/`stderr` como UTF-8 explícito en
  los tres sistemas operativos, y MUST aplicar timeouts por clase de invocación
  equivalentes a los de los otros clientes (lectura / mutación local / red).
- **FR-011**: Las invocaciones de clase red MUST impedir prompts interactivos de
  credenciales y fallar con diagnóstico.
- **FR-012**: La TUI MUST obtener **todo** el estado reinvocando porcelain, y
  MUST NOT derivar situación leyendo refs, config de review o el working tree.
- **FR-013**: La TUI MUST NOT parsear la salida humana de un verbo mutativo para
  decidir la situación; y cuando muestre el resultado de un verbo en verde MUST
  leerlo de `stdout`, que es donde los verbos lo escriben.
- **FR-014**: La feature MUST declarar la **lista cerrada** de invocaciones que la
  TUI puede hacer, como contrato versionado, al modo de
  `specs/002-extension-vscode/contracts/cli-invocation.md`.
- **FR-015**: El parser de porcelain de la TUI MUST ser tolerante en las tres
  formas ya establecidas: campo libre al final del registro, sin asumir cantidad
  de campos, e ignorando registros desconocidos.

**Superficie de producto**

- **FR-016**: La TUI MUST implementar las ocho situaciones del canónico con las
  mismas reglas de prioridad, más la superficie de espera previa al primer
  veredicto.
- **FR-017**: La TUI MUST ofrecer las 22 acciones nativas listadas en la
  clasificación de esta spec.
- **FR-018**: La TUI MUST delegar las cuatro acciones de apertura a las
  herramientas ya configuradas por el usuario (editor para archivos, difftool o
  pager con color de git para diffs), y MUST NOT implementar un visor propio de
  archivos o de diffs.
- **FR-019**: `openAllChanges` MUST declararse `not_in: [tui]` en el canónico con
  el motivo al lado, y el gate de CI MUST verificarlo en **las dos direcciones**.
- **FR-020**: La TUI MUST ofrecer **todos** los mapas de controles de fila que
  declara el canónico, completos — hoy `draft_controls:`, `guide_rows.controls:`,
  `fixes_rows.controls:`, `inventory_controls:` y los del `walkthrough_row`. El
  requisito MUST NOT fijar un número: la lista se lee del canónico, porque un
  conteo escrito acá y otro allá es exactamente el drift que el canónico existe
  para impedir. Esos controles MUST NOT contar contra las 27 acciones ni aparecer
  en ninguna lista de acciones del producto.
- **FR-021**: La TUI MUST ofrecer una superficie única equivalente a `surface:
  action` —una tecla que abre la lista completa de acciones habilitadas—, y las
  cuatro de `panel_excluded:` MUST existir **sólo** ahí.
- **FR-022**: La TUI MUST respetar `panel_layout:`, incluido el tope del 55% del
  alto para el pie y **una sola barra de scroll**, y MUST NOT recortar el
  contenido del pie.
- **FR-023**: Una review activa MUST NOT dibujar ninguna sección de pie.
- **FR-024**: La TUI MUST enrutar **toda** confirmación por una **única** puerta
  que recibe el id del control; MUST NOT existir ningún otro modal; y
  `walkthroughInit` MUST ser la única excepción declarada.
- **FR-025**: El canónico MUST declarar `reveals:` de la TUI como **lista vacía
  con su motivo**, con gate, y la TUI MUST NOT traer el pane al frente ni robar
  el foco por su cuenta.
- **FR-026**: La TUI MUST contestar los cinco nombres de `icon_vocabulary:` desde
  **un solo mapa**, con glifos de ancho no ambiguo, sin emoji, y con fallback
  ASCII.
- **FR-027**: La TUI MUST mostrar el texto de cada clave `tooltip*:` del canónico
  como el detalle de la fila enfocada, de modo que el gate que hoy exige esas
  claves en tres paneles pueda exigirlas también acá.
- **FR-028**: `min_cli_version` MUST dejar de ser un escalar compartido y pasar a
  ser un **valor por cliente, totalmente independiente**, con los cuatro
  declarados explícitamente y ningún default heredado. El motivo es concreto: hoy
  el escalar no es un piso compartido sino una **igualdad forzada** entre las
  constantes de los clientes, así que subirlo por lo que necesita un cliente le
  muestra *CLI desactualizada* a los usuarios de los otros tres por una función
  que no pueden usar. Independiente significa las cinco cosas:
  - Cada cliente declara su propio valor, y ese valor MUST ser la única fuente de
    su piso.
  - Subir el de un cliente MUST NOT obligar a tocar el de ningún otro, ni en el
    canónico, ni en su código, ni en su release.
  - Cada punto del verificador MUST comparar la constante de un cliente **contra
    el valor de ese mismo cliente**, y MUST NOT comparar dos clientes entre sí.
  - Que los cuatro valores difieran **MUST NOT** tratarse como drift: es el estado
    esperado, no una divergencia que haya que declarar con `not_in:` ni con
    ninguna otra exención. Ningún gate, presente o futuro, MUST exigir que sean
    iguales.
  - Los cuatro clientes MUST poder versionar y publicar sin coordinarse por este
    valor, igual que ya versionan y publican sin coordinarse por su propia
    versión.
- **FR-076**: La situación en la que el cliente no puede resolver **un único root
  de repositorio** MUST existir en la TUI, porque una terminal puede arrancar
  fuera de un repositorio. Su copy MUST declararse **por cliente** en vez de
  compartirse byte por byte, porque el próximo paso es distinto y en los dos casos
  está fuera del panel: en un IDE es abrir un workspace de una sola carpeta, en
  una terminal es pararse dentro de un repositorio. El canónico MUST reflejar esa
  forma —copy por cliente para una situación compartida— sin agregar exenciones
  dentro de `strings:`, que MUST seguir significando exactamente una cosa: copy
  compartida byte por byte.
- **FR-029**: El canónico MUST declarar explícitamente que `listing:` no aplica a
  la TUI, en vez de dejar el hueco.
- **FR-030**: Toda la copy de la TUI MUST vivir en un `UserCopy` propio del
  cliente, nunca embebida en un comando.
- **FR-031**: Ninguna superficie que le llegue a quien instala MUST nombrar a los
  otros tres clientes ni afirmar paridad con ellos.

**Refresco**

- **FR-032**: La TUI MUST refrescar por los cuatro disparadores declarados
  (acción propia, evento de archivo, entrada de foco y tecla de refresco) y MUST
  NOT usar polling como mecanismo.
- **FR-033**: La vigilancia MUST ser sobre **contenedores** —los seis directorios
  enumerados— con debounce y coalescencia, y MUST NOT depender de la existencia de
  un ref concreto como archivo.
- **FR-080**: La sexta raíz es **`<git-dir>` filtrada a `HEAD`**, para que un
  cambio de rama hecho por fuera —un `git checkout` en otro pane— llegue al panel,
  que es el evento que más cambia lo que el panel muestra, porque toda la sesión
  de review es por rama. Va sobre `<git-dir>` y no sobre el directorio común
  porque cada worktree tiene su propio `HEAD`; cuando los dos resuelven al mismo
  directorio, la raíz MUST contarse una sola vez.

  **Esto no agrega fragilidad, y el motivo importa.** Es la misma forma que ya se
  usa para `config` y `packed-refs` —un directorio vigilado, filtrado por nombre
  de archivo—, no un mecanismo nuevo. Y `HEAD` es de lo **menos** frágil que hay
  para mirar: junto con `config`, es parte de la disposición **documentada** del
  repositorio (`gitrepository-layout`), estable desde siempre; los detalles de
  implementación que sí cambian son el empaquetado de refs y el backend
  alternativo, que esta spec ya trata como best-effort. La fragilidad de toda la
  vigilancia sigue acotada por los mismos tres requisitos: no lee contenido
  (`FR-062`), la TUI es correcta con la vigilancia apagada (`FR-063`) y una ruta
  ausente se ignora (`FR-064`).
- **FR-034**: Un evento de archivo MUST provocar **únicamente** una reinvocación
  de porcelain; MUST NOT derivar estado del evento.
- **FR-035**: La vigilancia MUST seguir funcionando cuando el estado se escribe
  por rename atómico, cuando los refs se empaquetan y cuando el repositorio usa el
  backend de refs sin directorio `refs/`.
- **FR-036**: Las rutas del borrador y del borrador archivado MUST derivarse de
  los paths que la CLI **ya reportó**, y las de datos de git de preguntarle a git
  —distinguiendo directorio común y directorio del worktree—; MUST NOT rearmarse
  del layout del gitdir.
- **FR-037**: La TUI MUST pedir el reporte de foco al terminal y MUST degradar sin
  romperse cuando no lo obtiene.
- **FR-038**: La tecla de refresco MUST estar disponible en las ocho situaciones.
- **FR-039**: El piso de poll MUST ser opt-in por configuración y estar apagado
  por default; MUST NOT presentarse como el mecanismo de refresco.
- **FR-040**: La TUI MUST suprimir los refrescos disparados por la vigilancia
  mientras corre una invocación y hacer **uno solo** al terminar; MUST serializar
  las mutaciones, descartando la segunda con aviso en vez de encolarla.

- **FR-062**: La vigilancia MUST NOT leer el contenido de ninguna ruta vigilada
  y MUST producir un único tipo de mensaje, sin payload.
- **FR-063**: La TUI MUST ser completamente correcta y usable con la vigilancia
  apagada; ningún requisito de esta spec MUST depender de que la vigilancia
  funcione.
- **FR-064**: La vigilancia MUST ser best-effort: una ruta ausente se ignora en
  silencio y MUST NOT ser un error ni impedir el arranque.

**Teclas y terminal**

- **FR-041**: El mapa de teclas MUST ser vim-first con las flechas como alias,
  MUST reservar las teclas del cursor de la review para el cursor de la review, y
  MUST declararse en el canónico con gate, no sólo en el código del cliente.
- **FR-042**: La barra de teclas MUST estar visible, y la copy MUST NOT nombrar en
  prosa un comando que una tecla en pantalla ya corre.
- **FR-043**: La TUI MUST respetar `NO_COLOR`, MUST caer a un juego ASCII cuando el
  terminal o el locale no dan, y MUST NOT usar emoji en el layout.
- **FR-044**: La TUI MUST comportarse correctamente en Windows Terminal, conhost
  con VT, macOS Terminal, iTerm2, tmux, screen y los terminales de Linux, y MUST
  dejar el terminal restaurado incluso ante un fallo inesperado.

- **FR-065**: El panel MUST dibujar controles con su etiqueta según
  `panel_layout:`, con la misma jerarquía de énfasis que declara el canónico;
  MUST NOT reducirse a una lista de teclas.
- **FR-066**: El teclado MUST alcanzar y activar **todos** los controles en las
  ocho situaciones; MUST NOT existir un control que sólo responda al mouse.
- **FR-067**: El reporte de mouse MUST estar encendido por default y MUST tener
  una tecla que lo apague y devuelva la selección nativa del terminal, con su
  estado visible en el panel.
- **FR-068**: El control de copiar el comando de instalación MUST usar el
  portapapeles mediado por el terminal cuando esté disponible, y MUST degradar a
  mostrar el comando en una línea seleccionable diciendo cómo seleccionarlo.
- **FR-069**: La TUI MUST NOT dibujar copy que prometa que el panel vuelve a
  chequear solo cada pocos segundos, porque describe un poll que esta spec
  prohíbe.

**Estructura del cliente y gates**

- **FR-045**: El cliente MUST tener un **dominio puro** —sin dependencias de la
  librería de TUI— donde vivan el parseo, la proyección del panel, la tabla de
  confirmaciones y la copy; la capa de dibujo MUST limitarse a renderizar ese
  modelo.
- **FR-046**: `scripts/check-client-product-surface.mjs` MUST aprender a leer los
  archivos de dominio del cuarto cliente y verificar contra ellos los mismos
  escalares y tablas que ya verifica contra los otros tres.
- **FR-047**: El cliente MUST tener un test de contrato de layout propio,
  equivalente al de JetBrains y al de Visual Studio, que corra en su propia suite.

**Distribución, release y documentación**

- **FR-048**: La TUI MUST distribuirse por Homebrew, por los dos one-liner y como
  binario adjunto al GitHub Release, y por ninguna otra vía en la v1.
- **FR-079**: Los instaladores de la CLI **MUST NOT** instalar la TUI por default,
  ni con opt-out, ni preguntando. Instalar la CLI MUST dejar exactamente lo que
  deja hoy. La vía one-liner de la TUI MUST ser un **flag explícito y apagado**
  del mismo instalador: sin el flag no se descarga ni se escribe nada de la TUI, y
  el instalador MUST NOT prompt-ear por él —el proyecto se niega con un hint, no
  pregunta—. Que la TUI esté disponible por una vía no autoriza a esa vía a
  entregarla sin que se la pidan.
- **FR-049**: La TUI **MUST NOT publicarse en npm** en la v1, ni como paquete
  único ni como envoltorio con paquetes por plataforma. El motivo es que `bin` en
  un `package.json` mapea a **un** archivo, así que un paquete con varios binarios
  necesita un shim que elija cuál correr, y ese shim tiene que ser JavaScript (o
  `sh`, peor en Windows): la vía npm **pediría Node para correr un binario
  estático de Go**, que es la dependencia de runtime que motivó elegir el
  lenguaje. El paquete npm de la CLI MUST seguir existiendo, MUST conservar cero
  dependencias y MUST NOT mencionar ni transportar la TUI.
- **FR-081**: La matriz de plataformas del **GitHub Release** MUST declararse
  explícitamente, y el hint de `git review ui` MUST nombrar la vía que le
  corresponde a la plataforma donde corre en vez de una sola genérica. Una
  plataforma fuera de la matriz es una vía degradada, no un usuario bloqueado: el
  binario del Release es un archivo y se obtiene con cualquier descargador, sin
  registro ni runtime ni gestor de paquetes.
- **FR-050**: La fórmula de Homebrew de la TUI MUST ser propia y con binario
  prebuilt; la fórmula de la CLI MUST NOT tocarse.
- **FR-051**: La TUI MUST versionar aparte, con su propio namespace de tags, su
  propio workflow de release, su propio script de bump y su fila en
  `tests/version-consistency.bats`.
- **FR-052**: El GitHub Release de la TUI MUST crearse con `--latest=false`, para
  no romper a los dos instaladores que resuelven `releases/latest` para elegir el
  ref de la CLI.
- **FR-053**: La TUI MUST NOT publicar nada en ningún registro de paquetes en la
  v1. Sus únicos artefactos publicados MUST ser los binarios adjuntos al GitHub
  Release y la fórmula de Homebrew que los apunta, así que no hay altas de
  publicación que hacer antes del primer tag.
- **FR-054**: `README.md` y `README.es.md` MUST actualizarse en el mismo cambio,
  con el verbo, el alias declarado y las vías de instalación.
- **FR-055**: La landing MUST actualizarse en sus **dos puntas** (el HTML en
  inglés y el diccionario en español) cuando cambien los métodos de instalación.
- **FR-056**: El cliente MUST tener su propio `CONTRIBUTING.md`.

**Testing**

- **FR-057**: El layout MUST estar cubierto por archivos de referencia a **dos
  tamaños fijos, 80×24 y 120×40**, que fallen cuando el dibujo cambie.
- **FR-058**: La vigilancia MUST tener tests sobre un repositorio de prueba que
  cubran: crear y borrar refs, empaquetarlos, escribir config, tocar el borrador y
  un worktree enlazado.
- **FR-059**: El verbo MUST tener tests `bats` que afirmen el exit code **y** el
  mensaje de `stderr` cuando el ejecutable falta, y el reemplazo correcto cuando
  está; los nombres de `@test` MUST ser ASCII puro.
- **FR-060**: Todos los tests nuevos MUST cumplir las reglas de tests del
  proyecto: afirmar el status además de la salida, verificar el efecto real sobre
  el estado de git, y nada tautológico.

- **FR-070**: Los archivos de referencia de layout MUST cubrir **las ocho
  situaciones** a los dos tamaños, MUST estar versionados y revisarse como diff, y
  MUST NOT regenerarse automáticamente en CI — un archivo de referencia que se
  regenera al fallar no afirma nada.
- **FR-071**: `confirms:` MUST tener los **tres** gates que ya tienen los otros
  tres clientes: la tabla igual al canónico, todo id declarado pasando por la
  puerta única **leyendo el argumento** (no buscando el nombre suelto en el
  archivo), y ningún otro modal en el cliente.
- **FR-072**: La lista vacía de `reveals:` MUST tener gate propio que falle si el
  cliente adquiere una puerta de revelado.
- **FR-073**: MUST existir un test que recorra las ocho situaciones y afirme que
  cada control declarado es alcanzable y activable **sólo con el teclado**.
- **FR-074**: La suite MUST correr entera también con la vigilancia apagada, y
  MUST pasar igual.
- **FR-075**: MUST existir un test que afirme que el módulo del cliente declara
  exactamente las dependencias previstas y **ninguna ruta hacia otro cliente del
  monorepo**, en el mismo espíritu que la regla de importaciones del dominio de
  JetBrains.

**Configuración propia del cliente**

- **FR-061**: La configuración propia de la TUI —el piso de poll opt-in y las
  preferencias equivalentes a las que los otros clientes exponen como settings,
  entre ellas el origen preseleccionado del asistente— MUST vivir en claves
  `git config` bajo el namespace **`reviewui.*`**, leídas defensivamente como el
  resto de la config del proyecto. El alcance global es la preferencia del
  usuario y el local del repositorio es el override, que es exactamente el par
  que los otros tres reciben de sus IDEs (*user settings* contra *workspace
  settings*).
- **FR-077**: Las claves `reviewui.*` MUST NOT tocar `reviewworkflow.*`, que
  conserva sus tres claves por diseño, y **la CLI MUST NOT leer ninguna clave
  `reviewui.*`** en ningún verbo. La frontera es en las dos direcciones: la TUI
  no escribe configuración de la CLI y la CLI no consulta configuración de un
  cliente.
- **FR-078**: La TUI MUST NOT tener ningún archivo de configuración propio en
  disco. El estado de una sesión y las preferencias del cliente viven en los datos
  de git, nunca en archivos que la TUI administre.

### Key Entities

- **RepositoryTarget**: el repositorio del `cwd` donde corre la TUI. Uno solo, y
  sin la ambigüedad multi-root de los editores: el directorio de trabajo lo
  resuelve.
- **ReviewState**: situación más los datos porcelain parseados (estado, entradas,
  ramas, config, cierre, marcas de solo-lectura y solo-keys).
- **PanelModel**: proyección serializable de qué debe mostrarse, sin nada del
  dibujo. Es lo que los archivos de referencia y el test de contrato leen.
- **PathRef**: el par crudo/mostrable de un path de entrada. Lo mostrable va a la
  pantalla y al editor; lo crudo vuelve a la CLI.
- **ReviewIntent**: las elecciones del asistente de inicio (rama, origen, rango,
  forma de lectura) antes de materializar el argv.
- **StateToken**: huella de frescura del estado, para no mutar sobre datos viejos
  después de una confirmación.
- **InvocationClass**: lectura / mutación local / red — define timeout y entorno.
- **WatchSet**: el conjunto de directorios vigilados, derivado de lo que la CLI
  reportó y de lo que git contesta; se rehace **sólo** cuando cambia.
- **RefreshTrigger**: cuál de los cuatro disparadores pidió el refresco. Decide si
  se suprime por el lock de mutación.
- **KeyBinding**: el par tecla → acción o movimiento, declarado en el canónico y
  dibujado en la barra de teclas.
- **Viewport**: filas y columnas del pane, más las capacidades del terminal
  (color, ancho de glifos, dibujo de cajas).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un revisor con la CLI y la TUI instaladas puede completar, **sin
  salir del pane y sin escribir un solo comando**, el flujo arrancar → leer →
  mover el cursor → cerrar, sobre el sandbox del repo.
- **SC-002**: Con la TUI abierta y el revisor sin tocar nada, **cero procesos de
  `git review` por minuto** en reposo (medible contando invocaciones en el
  registro del cliente).
- **SC-003**: Cada uno de los cuatro disparadores de refresco tiene al menos un
  test que falla si ese disparador deja de funcionar, y los cuatro agujeros
  declarados (rename atómico, refs empaquetados, backend sin `refs/`, dos niveles
  de anidamiento) tienen el suyo.
- **SC-004**: Una mutación que escribe config y refs varias veces produce
  **exactamente un** repintado.
- **SC-005**: El 100% de las situaciones del canónico son alcanzables y
  distinguibles en la TUI con fixtures controladas.
- **SC-006**: El 100% de las 27 acciones del canónico está en una de las tres
  clases declaradas (nativa, delegada, `not_in`), verificado automáticamente
  contra el canónico; una acción sin clase o una clase sin acción pone CI en rojo.
- **SC-007**: Quitar una confirmación declarada, agregar un modal fuera de la
  puerta, o cambiar el id que un call site pasa, pone CI en rojo. Los tres gates
  se prueban **rompiéndolos**.
- **SC-008**: Agregar un `reveals:` a la TUI pone CI en rojo mientras la lista
  declarada siga vacía.
- **SC-009**: El mismo estado renderizado a 80×24 y a 120×40 coincide byte por
  byte con sus archivos de referencia, y un cambio de layout no declarado los
  rompe.
- **SC-010**: Con el color apagado y con el fallback ASCII forzado, las ocho
  situaciones siguen siendo legibles y ninguna línea se desborda en 80 columnas.
- **SC-011**: `git review ui` sin la TUI instalada sale con código distinto de
  cero y un mensaje que contiene el comando de instalación; con la TUI instalada,
  el código de salida que ve la shell es el de la TUI.
- **SC-012**: Un cambio de un string **compartido** del canónico —el comando de
  instalación de la CLI incluido— no puede quedar sólo en tres de los cuatro
  clientes: el gate lo detecta. `min_cli_version` queda deliberadamente fuera de
  este criterio, porque los cuatro valores son independientes por `FR-028` y que
  difieran es el estado esperado.
- **SC-013**: Un release de la TUI no altera qué ref instalan `web-install.sh` y
  `web-install.ps1`, verificable resolviendo `releases/latest` después del tag.
- **SC-014**: La TUI no comparte ningún archivo de código con los otros tres
  clientes, verificable porque su árbol no importa nada de fuera de su propio
  directorio.
- **SC-015**: Cualquiera de las ocho situaciones se opera de punta a punta
  **sólo con el teclado**, sin un control inalcanzable, y **sólo con el mouse**
  para los controles que la situación dibuja.
- **SC-016**: La suite completa pasa con la vigilancia del sistema de archivos
  apagada, y ningún dato que el panel muestra difiere del que muestra con la
  vigilancia encendida.
- **SC-017**: Cambiar un byte del dibujo de cualquiera de las ocho situaciones, a
  cualquiera de los dos tamaños, pone en rojo un archivo de referencia — y no
  existe forma de regenerarlos desde CI.
- **SC-018**: Sacar una confirmación declarada, agregar un modal fuera de la
  puerta única, o darle al cliente una puerta de revelado, pone algo en rojo.

## Assumptions

- **Paridad, ni más ni menos.** La superficie de esta spec es el techo y el piso
  de la v1. Si otro cliente gana superficie después, se enmienda esta feature o
  la siguiente; nunca se «asume paridad» sin actualizar la tabla.
- **La CLI es la única fuente de verdad.** Igual que los otros tres, y sin
  excepciones para este.
- **El `cwd` resuelve el repositorio.** A diferencia de un editor, una terminal
  está parada en un lugar; no hay picker ni ambigüedad multi-root.
- **El mínimo de CLI de la TUI es, como piso, la versión que introduce el verbo
  `ui`**, porque es la que la hace descubrible. Si consume porcelain más nuevo,
  sube con él.
- **Los targets de compilación son los sistemas operativos y arquitecturas que
  cubren la matriz de terminales declarada.** En una plataforma donde la CLI
  corre (es shell POSIX) pero no hay binario de TUI publicado, el verbo se niega
  con el mismo hint accionable: es el comportamiento correcto, no un caso sin
  cubrir.
- **Los archivos de referencia del layout son el equivalente del snapshot que los
  otros tres clientes tienen.** Sin ellos, el cuarto cliente driftea sin que nada
  se ponga rojo.
- **`strings:` del canónico**: la TUI carga todas las cadenas compartidas cuyas
  situaciones puede alcanzar, y **las alcanza todas**. `multi_root_error` no es
  una excepción: en los tres clientes ese string cubre **dos causas** —el
  workspace multi-root y el no-hay-repositorio— y la segunda es perfectamente
  alcanzable desde una terminal, que puede arrancar fuera de un repositorio. Lo
  que no aplica es la mitad accionable del texto: «abrí un workspace de una sola
  carpeta» no significa nada en un pane. Ver `FR-076`.
- **`min_cli_version` pasa a ser un valor por cliente, con los cuatro
  declarados.** Se descartó dejar el escalar como default con overrides porque el
  default significaría «el piso de quien no declaró» —un valor que nadie eligió y
  todos heredan—, que es la forma que driftea en silencio; es el mismo criterio
  con el que las dos filas de guías se emiten exista o no el archivo y con el que
  `not_in:` se verifica en las dos direcciones: se declara, no se implica. Los
  cuatro valores son **totalmente independientes**: pueden diferir
  indefinidamente, y que difieran no es drift sino el estado esperado —cada
  cliente pide lo que realmente necesita—. El cambio no afecta a quien ya tiene una
  CLI **más nueva** que el mínimo: la comparación de los clientes es un piso
  estricto y no hay techo.
- **La configuración del cliente vive en `git config`, namespace `reviewui.*`.**
  Se eligió sobre un archivo propio porque `git config` ya trae los dos alcances
  que la preferencia necesita —global como preferencia del usuario, local como
  override del repositorio— sin reimplementar resolución de precedencia ni un
  formato nuevo, y porque un archivo propio haría de la TUI el único de los cuatro
  clientes con estado en disco que le pertenece. Se eligió sobre variables de
  entorno porque una variable no sabe decir «en este repositorio, otra cosa», y el
  origen preseleccionado del asistente es exactamente una preferencia que quiere
  override por repositorio.
- **La primera impresión no es problema de esta feature.** Eso lo arreglan el
  demo y la landing; ésta arregla la retención.
- **Idioma de la interfaz**: inglés en los strings de producto, igual que los
  otros tres clientes. Los documentos de trabajo siguen en español.

## Dependencies

- **La CLI `git-review-workflow`** instalada y en el `PATH` como `git review`, en
  una versión igual o mayor al mínimo del cliente.
- **git** usable en la máquina: es el ejecutable que la TUI invoca para todo, y el
  que resuelve la ubicación de los datos del repositorio.
- **Un terminal** de la matriz declarada. `$EDITOR`, `diff.tool` y `$PAGER` del
  usuario para las cuatro acciones delegadas; sin ellos, esas cuatro degradan con
  un mensaje que dice qué no pasó.
- **`contracts/client-product-surface.yaml`** y su verificador de CI, que esta
  feature extiende: sin las claves nuevas y sus gates, el cuarto cliente nace
  fuera del régimen anti-drift.
- **Publicación**: la capacidad de crear releases con binarios adjuntos. No hace
  falta ninguna alta en un registro de paquetes: la v1 no publica en ninguno.
