# Contract: La superficie de la TUI

**Consumidor normativo**: `tui/internal/domain/{layout,actions,keymap,icons,confirms,usercopy}.go` +
`tui/internal/ui/`
**Fuente canónica**: `contracts/client-product-surface.yaml`

La matriz situación × acción **no se redefine acá**: sólo el YAML es normativo. Este documento fija
qué forma toma esa matriz cuando el host es un pane de terminal, y qué se verifica.

---

## Las ocho situaciones, más la espera

Las mismas ocho con las mismas reglas de prioridad. La **superficie de espera** no es una situación:
se dibuja `waiting_text` hasta que hay un veredicto, y las tres situaciones que son respuestas sobre
el entorno (`cli-missing`, `cli-outdated`, `error`) **no se repintan de memoria**.

`cli-missing` y `cli-outdated` **no son un renglón: son dos situaciones de panel completas**, con los
mismos seis bloques que en los otros tres. Al bajarlas a una terminal aparecen dos choques, y los
dos se resuelven:

1. **Copiar el comando de instalación.** Por SSH o dentro de un multiplexor no hay portapapeles del
   sistema. La vía es **OSC 52** —el portapapeles mediado por el terminal—, que no tiene acuse: el
   terminal no contesta si copió. Por eso el control **nunca afirma haber copiado** y la degradación
   es una elección de diseño, no una detección: la línea con el comando queda dibujada limpia y
   seleccionable, y el panel dice cómo seleccionarla (FR-068).
2. **La selección nativa necesita el mouse apagado.** Con el reporte de mouse activo el terminal deja
   de hacer selección por arrastre. Por eso **el control de copiar y el toggle de mouse son la misma
   conversación**: la tecla que apaga el mouse es la que hace seleccionable esa línea, y el estado
   del mouse es visible en el panel.
3. **`reload_or_wait` no se dibuja.** Dice que se recargue la ventana o se espere *«porque el panel
   vuelve a chequear cada pocos segundos»*: en una terminal no hay ventana que recargar, y volver a
   chequear cada pocos segundos **es un poll**, que FR-032 prohíbe hacer y FR-069 prohíbe **decir**.
   La clave sale de `strings:` y pasa a `per_client_strings.after_install`; ver el contrato del
   canónico.

---

## Las 27 acciones, clasificadas

**La clasificación es el alcance.** SC-006 la verifica automáticamente contra el canónico: una acción
sin clase o una clase sin acción pone CI en rojo.

### Nativas — 22

`showWhy`, `next`, `prev`, `goToEntry`, `refresh`, `installCli`, `continueReview`, `startReview`,
`setBase`, `setRemote`, `abortReview`, `saveReview`, `finishReview`, `undoFinish`, `resumeFinish`,
`discardInventory`, `cleanReview`, `forgetReview`, `previewEditsStat`, `walkthroughInit`,
`walkthroughBuild`, `showCliLog`

Las cuatro que se clasifican mal fácil, y por qué caen acá:

- **`showCliLog` no es una acción de editor.** Es la **tercera capa** de la regla de copy —el detalle
  técnico siempre a un gesto—. En la TUI es un overlay o `$PAGER`.
- **`previewEditsStat` es `--stat`**, o sea texto: nativa. (`previewEdits` sin `--stat` es un diff, y
  ahí sí gana el difftool del usuario.)
- **`goToEntry` es un picker**, y es la superficie que mejor le queda a una TUI.
- **`walkthroughInit` y `walkthroughBuild` son mutaciones nativas.** Lo único que se delega es la cola
  de «y después abre el archivo».

### Delegadas — 4

| Acción | Herramienta |
|---|---|
| `openEntry`, `openChange` | `$EDITOR` |
| `previewEdits`, `compareReview` | `git difftool` / `$PAGER`, con el color de git |

**Delegar es la respuesta correcta y no una renuncia**: quien vive en un multiplexor ya tiene
`$EDITOR`, `diff.tool` y `$PAGER` configurados mejor de lo que esta TUI los va a resolver.
Reimplementar un visor de diffs adentro del pane sería peor que lo que el revisor ya eligió, y sería
la primera cosa de este cliente que no respeta lo que la máquina ya sabe. FR-018 lo prohíbe
explícitamente.

### `not_in: [tui]` — 1

`openAllChanges`. Abrir N diffs de golpe no existe como gesto en un multiplexor. Va al canónico con
el motivo al lado, exactamente como está la divergencia de Visual Studio, y **se verifica en las dos
direcciones**: la TUI no la declara en ninguna de sus superficies, y los otros dos que sí la tienen
la siguen teniendo.

### Los tres mapas de controles de fila

`draft_controls:`, `guide_rows.controls:` y `fixes_rows.controls:` existen los tres, completos, más
`walkthrough_row.controls:`. **No tocan el conteo de 27**: su sujeto es una **fila**, no el producto.
No van a ninguna lista de acciones de la TUI, igual que no van a `contributes.commands`, al menú
*Tools* ni al `.vsct`. Colar uno como acción falla CI.

---

## El problema de las dos superficies, y su equivalente

El canónico declara `surface: panel | action | both`, donde `action` significa paleta de comandos
(VS Code), menú *Tools* (JetBrains) o `.vsct` (Visual Studio). **La TUI tiene una sola superficie
visible**, así que sin un equivalente las cuatro de
`panel_excluded: [goToEntry, forgetReview, previewEditsStat, showCliLog]` se quedarían sin ninguna.

El equivalente es **una tecla que abre la lista completa de acciones**: un overlay filtrable que
enumera **lo que la situación actual habilita**, con su tecla al lado donde la tenga. Es la paleta de
comandos de este cliente, y las cuatro excluidas del cuerpo viven **sólo** ahí, igual que en los
otros tres.

**No es un segundo modal.** FR-024 prohíbe otro modal hablando de **confirmaciones**, y esta lista no
confirma: elige. Una acción destructiva elegida desde acá pasa por **la misma** puerta
(`ConfirmMutation`) que si se hubiera activado en el cuerpo (User Story 7, escenario 3), y el gate 2
de `confirms:` lo verifica solo, porque el call site está en el mismo despachador.

**`goToEntry` es un picker aparte**, no la misma lista: enumera **entradas**, no acciones, y abre la
elegida **sin mover el cursor de la CLI** (User Story 3, escenario 5). O sea: abre y punto — no
invoca `next`/`prev` N veces.

---

## Controles, no atajos

El panel dibuja **controles**: botones con su etiqueta, filas con su botonera, secciones plegables —
el mismo `panel_layout:` que los otros tres, en caracteres, con la misma jerarquía de énfasis
(`primary | secondary | link | icon`). **Si el resultado es `git review status` con cajas y bordes,
está mal**: eso ya es `watch`.

FR-065 lo dice al revés y es lo mismo: la TUI **no** puede reducirse a una lista de teclas.

### Teclado — completo y primario

- **vim-first, flechas como alias.** `j`/`k` mueven la fila enfocada; letras mnemónicas activan; las
  flechas hacen lo mismo.
- **`n`/`p` están reservadas para el cursor de la review** (`git review next` / `prev`), que es un
  concepto distinto de navegar la lista. La reserva se declara en `keymap:` y tiene gate.
- **La barra de teclas está visible**, y es el equivalente exacto del botón: **si la tecla está en
  pantalla, la tecla ES el texto**. La regla de copy —el próximo paso sólo se dice si está *fuera*
  del panel— aplica igual acá: nombrar en prosa un comando que una tecla en pantalla corre está
  prohibido.
- **El teclado alcanza y activa TODOS los controles, en las ocho situaciones** (FR-066). Nunca hay
  uno que sólo responda al mouse. Es lo que hace que agregar mouse no le saque nada a nadie.
- La barra se dibuja **del mismo mapa** que resuelve las teclas, así que una tecla que existe y no se
  muestra es imposible por construcción.
- En `finish-conflict` las teclas del cursor **no están disponibles y la barra no las ofrece** (User
  Story 3, escenario 4): la barra refleja la situación, no un set fijo.

### Mouse — encendido por default, con toggle

- El reporte de mouse va **encendido por default**, como en lazygit, gitui, k9s y btop. Un panel
  cuyos botones parecen botones y no se pueden activar es peor que uno sin botones.
- **Una tecla lo apaga** y devuelve la selección nativa por arrastre, con su estado visible en el
  panel (FR-067). Es la misma tecla que hace seleccionable el comando de instalación.
- Un clic hace **exactamente lo mismo** que su tecla, y el control bajo el cursor se distingue del
  resto (User Story 3, escenario 8).
- En un multiplexor el usuario necesita habilitar el mouse para que los eventos lleguen al pane. La
  TUI **no lo configura ni lo exige**: sin mouse, el teclado ya alcanza todo, y no hay mensaje de
  error ni degradación visible (User Story 8, escenario 7).

**La `HitMap`** es lo que hace esto verificable: `View` devuelve `(frame, HitMap)`, cada control
dibujado deja su rectángulo, y `MouseMsg` se resuelve contra eso. Sin ella no hay forma honesta de
escribir el test "sólo con el mouse" de SC-015 — habría que adivinar coordenadas.

---

## Iconos: el nombre lo fija el canónico, el ancho lo fija el test

Los cinco de `icon_vocabulary:` —`prev`, `next`, `file`, `trash`, `diff`— se contestan desde **un
solo mapa** (`domain/icons.go`), cada entrada con **dos** glifos: Unicode y ASCII.

Dos gates, y ninguno es una lista de codepoints escrita a mano:

1. cada glifo Unicode mide **exactamente una celda** —East Asian Width `Narrow` o `Neutral`, nunca
   `Wide` ni `Ambiguous`—, pasado por la **misma** tabla de ancho que usa el renderer;
2. cada glifo ASCII está en `U+0020..U+007E`.

`Ambiguous` es el modo de falla real: se dibuja en una celda en un terminal y en dos en otro, y ahí
las columnas de todas las filas se desalinean. Prohibir emoji (FR-043) no alcanza — `≡`, `▶` y media
Geometric Shapes son `Ambiguous` sin ser emoji.

**Cuándo cae al ASCII**: no lo decide `NO_COLOR` (eso es color, no dibujo). Lo dispara el
locale/codepage — `LC_ALL`/`LC_CTYPE`/`LANG` sin UTF-8, o un codepage de consola de Windows distinto
de 65001 — y es una decisión de arranque. `GIT_REVIEW_UI_ASCII=1` la fuerza, que es lo que hace
posible el juego de golden `-ascii`.

---

## El pie, y la review que no lo tiene

`panel_layout:` aplica entero, incluido el **tope del 55% del alto para el pie** y **una sola barra
de scroll** (FR-022). En un pane de 40 filas eso importa más que en un IDE, no menos: sin el tope, el
pie *es* el panel.

Y la barra es **una sola**: cada sección abierta pide el alto de su contenido y ninguna scrollea por
dentro. Repartir el alto entre las abiertas da una barra por sección, ninguna capaz de mostrar la
suya entera.

**Una review no tiene pie: ninguna `tools_section`** (FR-023). Todo lo que cuelga de `walkthrough` es
de quien está parado en **su** PR, y adentro de una review estás parado en el de otro. En la TUI eso
se afirma en el **proyector**: dentro de una review el `PanelModel` no *proyecta* las secciones del
pie — no es que no se dibujen. Los registros ni llegan: son de `config --porcelain`, que adentro de
una review no se invoca.

---

## El pane real

- **Dos tamaños de referencia, 80×24 y 120×40** (FR-057), y ninguna línea se desborda ni se corta a
  mitad de columna.
- **`NO_COLOR`** respetado: sin secuencias de color, y todo sigue legible sin ellas.
- **Resize en vivo**: `tea.WindowSizeMsg` rehace el layout sin corromperlo.
- **Pane más chico que el mínimo dibujable**: degrada a algo legible en vez de romper el layout.
- **Terminal restaurado ante un fallo inesperado** (FR-044): sin alt-screen colgada ni cursor
  escondido. Bubble Tea lo hace en su `recover`; el gate es un test que provoca un panic en `Update`
  y afirma que el programa salió con el terminal restaurado.

---

## Qué se verifica, y dónde

| Requisito | Gate | Dónde corre |
|---|---|---|
| Las ocho situaciones alcanzables y distinguibles (SC-005) | fixtures porcelain → `PanelModel`, una por situación | `go test` |
| Las 27 clasificadas (SC-006) | el verificador del canónico contra `actions.go` | CI, job `client-product-surface` |
| Layout byte a byte (SC-009, SC-017) | golden files, 2 tamaños × 3 modos, **no regenerables desde CI** | `go test` |
| Layout contra el canónico (FR-047) | test de contrato propio, equivalente de `PanelLayoutContractTest` | `go test` |
| Tope del 55% y una sola barra | asserts estructurales sobre el layout, no sobre pixeles | `go test` |
| Todo alcanzable **sólo con teclado** (FR-073, SC-015) | recorrer las ocho situaciones con `KeyMsg` sintéticos y afirmar que cada control declarado se alcanza y se activa | `go test` |
| Sólo con mouse | ídem con `MouseMsg` contra la `HitMap` | `go test` |
| `confirms:` — los tres gates (SC-007, SC-018) | tabla, argumento del call site, ningún otro modal. **Se prueban rompiéndolos** | CI + `go test` |
| `reveals: []` (SC-008) | la clave vacía + el barrido de secuencias de "traer al frente" | CI |
| Cada `tooltip*:` del canónico (FR-027) | el barrido por texto que ya existe suma la cuarta punta | CI |
| Sin ruta hacia otro cliente (FR-075, SC-014) | `go.mod` declara exactamente las cuatro deps; ningún import nombra otro cliente | `go test` |
| Dominio puro (FR-045) | ningún import de bubbletea/lipgloss/bubbles/fsnotify/`os/exec` bajo `internal/domain/` | `go test` |

---

## Copy: las siete reglas, aplicadas

| Regla de §15 | Cómo cae en la TUI |
|---|---|
| El próximo paso sólo si está **fuera** del panel | si hay una tecla en pantalla que lo corre, **la tecla es el texto** |
| Tres capas, mecanismo nunca en la primera | etiqueta → contexto (una oración) → detalle técnico a un gesto (`showCliLog`). **Un tooltip no es lugar para un argv**: dice qué le pasa al objeto de su fila, en imperativo, y en la TUI es el detalle de la fila enfocada (FR-027) |
| Se confirma lo que no se puede deshacer | `startReview` **no** confirma, y vale para los **dos** caminos: el asistente y `startFromDraft` |
| Un diálogo se abre en **un solo lugar** | `ConfirmMutation`. Excepción declarada única: `walkthroughInit` |
| Lo que el panel muestra no se notifica | en un pane no hay toasts: el panel **es** la superficie. Lo que en los otros tres se notifica —el `update` de borrador, el copiado, el residual de `finish` sin banner— acá va a una línea de estado del propio panel, y **cuál de los dos es se decide por lo que se pidió, nunca leyendo la salida de la CLI** |
| El panel se revela, no se notifica | **no aplica**: `reveals: []`. Un pane lo abriste vos, y robarle el foco a alguien en un multiplexor es agresión |
| Advice: un cliente no reenvía lo que ya tiene | `GIT_REVIEW_ADVICE=0` en **un solo lugar** del invocador (FR-009) |
| Un solo aviso de estado obsoleto | `STALE`, sin nombrar el verbo que no corrió: ese verbo es la tecla que el revisor acaba de apretar |
| Los fallbacks de error dicen **qué no pasó** | y sólo aparecen cuando la CLI muere *sin* `stderr`; con `stderr`, no se toca nada |
| Un nombre por concepto, ninguno prestado de git | `broken`, `details are gone`, `not covered`, `saved edits`, `last review point`; un solo verbo para borrar. *Walkthrough* y *reading order* sí son dos cosas distintas |
| Todo texto al `UserCopy` del cliente | `tui/internal/domain/usercopy.go`, nunca embebido en un comando (FR-030) |

Idioma: **inglés en los strings de producto**, igual que los otros tres. Los documentos de trabajo
siguen en español.

**Y ninguna superficie que le llegue a quien instala nombra a los otros tres clientes ni dice
«paridad con X»** (FR-031). Eso se cuenta en `CONTRIBUTING.md` y en `../../../AGENTS.md`.
