# Contract: Lo que el canónico gana con el cuarto cliente

**Fuente normativa**: `contracts/client-product-surface.yaml`
**Verificador**: `scripts/check-client-product-surface.mjs` (job `client-product-surface` de `ci.yml`)

Este documento **no** redefine el canónico: fija qué cambia de forma, qué se agrega, y cómo migra el
verificador sin dejar CI roja en el medio. La regla que gobierna todo: **una tabla sin gate nace
decorativa**. Nada de lo que sigue entra sin su chequeo.

Dos de los cambios tocan a los **tres clientes ya publicados**. Los dos se hacen
**preservando bytes**: cambia la forma, no los valores.

---

## 1. `min_cli_version`: de escalar a valor por cliente (FR-028)

### Hoy

```yaml
min_cli_version: "0.8.0" # verified: vscode-extension/src/cli/version.ts
```

Leído con `scalar("min_cli_version")` (línea 39) y comparado contra las constantes de los tres
clientes en las líneas **94** (`vscode version.ts`), **109** (`intellij Version.kt`) y **943**
(`visualstudio Version.cs`). El escalar **no es un piso compartido: es una igualdad forzada**.
Subirlo por lo que necesita un cliente le muestra *CLI desactualizada* a los usuarios de los otros
tres por una función que no pueden usar.

### Forma nueva

```yaml
# EL PISO DE CADA CLIENTE, Y NADA MÁS QUE ESO.
#
# No es un escalar y no tiene default. Un default sería "el piso de quien no
# declaró" — un valor que nadie eligió y todos heredan —, que es la forma que
# driftea en silencio; el mismo criterio con el que las dos filas de guías se
# emiten exista o no el archivo y con el que not_in: se verifica en las dos
# direcciones: se declara, no se implica.
#
# QUE LOS CUATRO DIFIERAN NO ES DRIFT: es el estado esperado. Cada cliente pide
# lo que realmente necesita, y ningún gate —presente ni futuro— puede exigir que
# sean iguales. La comparación de cada cliente es un piso estricto: no hay techo,
# así que una CLI más nueva que el mínimo nunca se reporta desactualizada.
min_cli_version:
  vscode: "0.8.0"        # verified: vscode-extension/src/cli/version.ts
  intellij: "0.8.0"      # verified: jetbrains-plugin/.../domain/Version.kt
  visualstudio: "0.8.0"  # verified: visualstudio-extension/src/GitReview.Domain/Version.cs
  tui: "0.8.0"           # sube a la versión que introduce el verbo `ui`, en su propio commit
```

### Qué cambia en el verificador

| Hoy | Después |
|---|---|
| `const min = scalar("min_cli_version")` (39) | `minFor(client)` — falla si **el cliente pedido** no está declarado |
| `versionTs.includes(`"${min}"`)` (94) | `versionTs.includes(`"${minFor("vscode")}"`)` |
| `v.includes(`"${min}"`)` (109) | `minFor("intellij")` |
| `v.includes(`"${min}"`)` (943) | `minFor("visualstudio")` |
| — | `minFor("tui")` contra `tui/internal/domain/version.go` |

**No queda ningún `min` global en scope.** Eso no es estilo: es lo que hace que una comparación
entre dos clientes no se pueda escribir por accidente. Un helper que devuelve el valor de *un*
cliente no tiene los cuatro a mano.

Además, `minFor` **exige los cuatro declarados**: un cliente ausente del mapa es un `fail`, no un
default silencioso.

### El gate de "ningún gate exige que sean iguales"

Dos capas, y la primera es gratis:

1. **La divergencia real.** Desde el día que la TUI publica, su valor difiere del de los otros tres
   en `main`. Cualquier chequeo que exigiera igualdad estaría **rojo en `main`**, no en un caso
   hipotético.
2. **Una fixture que no puede volverse tautológica.** Si algún día los cuatro convergen al mismo
   número, la capa 1 deja de probar nada. Por eso el verificador acepta
   `--yaml <path>` y hay un test que lo corre contra
   `specs/015-cliente-tui/contracts/fixtures/divergent-min.yaml` —cuatro valores maximalmente
   distintos— afirmando **exit 0**. Ese archivo es la única fixture del contrato y existe para esto.

---

## 2. `multi_root_error`: sale de `strings:` (FR-076)

### Hoy

```yaml
strings:
  # verified: review/state.ts multi-root message
  multi_root_error: >-
    Open a single-folder workspace that is a git repository. git review uses
    one root (like the CLI cwd); multi-root is not supported.
```

Verificado con un **fragmento tipeado a mano en JavaScript** —`const multi = "multi-root is not
supported"` (118)— buscado en los tres state managers (**120**, **124**, **957**). El fragmento no se
compara contra el YAML: si alguien cambiara el texto del canónico, el chequeo seguiría verde.

### Forma nueva

`strings:` tiene que seguir significando **exactamente una cosa**: copy compartida byte por byte, sin
excepciones adentro. Así que la clave **sale del mapa**, no se le anota una exención.

```yaml
# COPY QUE CONTESTA LA MISMA SITUACIÓN EN LOS CUATRO CLIENTES Y NO SE COMPARTE.
#
# strings: significa una sola cosa —copy compartida byte por byte— y una
# excepción anotada adentro le sacaría ese significado. Lo que vive acá es lo
# contrario: la misma situación, y el próximo paso distinto por cliente. En los
# dos casos el próximo paso está FUERA del panel, que es por lo que hay que
# decirlo: en un IDE es abrir un workspace de una sola carpeta; en una terminal
# es pararse dentro de un repositorio.
#
# Que tres valores coincidan hoy NO es drift, por el mismo motivo que en
# min_cli_version: cada uno es la única fuente de su cliente y ninguno hereda.
per_client_strings:
  # Se llamaba multi_root_error. El nombre nuevo dice la situación y no una de
  # sus dos causas: en una terminal no hay multi-root, y la causa alcanzable es
  # la otra —arrancar fuera de un repositorio—.
  no_single_root:
    vscode: >-
      Open a single-folder workspace that is a git repository. git review uses
      one root (like the CLI cwd); multi-root is not supported.
    intellij: >-
      Open a single-folder workspace that is a git repository. git review uses
      one root (like the CLI cwd); multi-root is not supported.
    visualstudio: >-
      Open a single-folder workspace that is a git repository. git review uses
      one root (like the CLI cwd); multi-root is not supported.
    tui: >-
      … (copy propia de la TUI, escrita en la tarea que crea su UserCopy)
```

**Los tres valores de los IDEs son los de hoy, verbatim.** FR-076 exige que la copy se **declare**
por cliente, no que se reescriba: los tres IDEs comparten el próximo paso, y por eso sus bytes
coinciden. Ningún archivo de los tres clientes publicados cambia.

### Qué cambia en el verificador

| Hoy | Después |
|---|---|
| `const multi = "multi-root is not supported"` (118) — literal en JS | `perClientString("no_single_root", client)` — **leído del YAML** |
| `includes(multi)` en tres archivos (120, 124, 957) | comparación de la **cadena entera**, plegada y normalizada con el helper `squash` que ya existe |
| — | cuarta entrada: `tui/internal/domain/usercopy.go` |

El chequeo **sube de calidad al migrar**: hoy verifica cinco palabras contra un literal de JS;
después verifica la oración completa contra el valor declarado, con la misma técnica de plegado que
ya usa `draft_agent_prompt` (bloque `>-`, `squash` de comillas y `+`, colapso de espacios).

---

## 3. `reveals:`: de lista plana a mapa por cliente (FR-025, FR-072, SC-008)

### Hoy

```yaml
reveals:
  - startReview
  - startFromDraft
  - continueReview
  - finishReview
```

Lista plana, gateada **sólo contra VS Code** (líneas 1630-1690): `REVEALING_IDS`, los call sites de
`revealPanel`, y "ningún archivo revela el panel por su cuenta".

### Forma nueva

```yaml
reveals:
  vscode: [startReview, startFromDraft, continueReview, finishReview]
  intellij: [startReview, startFromDraft, continueReview, finishReview]
  visualstudio: [startReview, startFromDraft, continueReview, finishReview]
  # VACÍA, Y DECLARADA. No es una ausencia: es la respuesta.
  #
  # Un pane lo abriste vos y ya está a la vista, así que no hay nada que
  # revelar; y robarle el foco a alguien en un multiplexor es agresión, no un
  # acuse. Si esto quedara como hueco, en seis meses alguien agrega un reveal y
  # nada se pone rojo — que es exactamente lo que le pasó a confirms:.
  tui: []
```

### El gate de la lista vacía

Dos mitades, y las dos tienen que estar:

1. **`reveals.tui` debe existir y estar vacía.** Que la clave falte es un `fail`, igual que un
   cliente ausente de `min_cli_version`.
2. **El árbol de la TUI no puede tener una puerta de revelado.** Un id declarado exige un call site
   que pase por la puerta única del cliente; como la lista está vacía, no hay ninguno que exigir. Lo
   que sí se verifica es lo simétrico: `tui/` **no emite** ninguna de las secuencias con las que un
   programa de terminal se trae al frente — BEL (`\a`), OSC 9 y OSC 777 (notificaciones), `ESC [5t`
   (raise window) — ni shellea a `tmux`, `wezterm` o `kitty`. Es una lista corta y nombrable, que es
   lo que la hace gateable.

Con eso, SC-008 se cumple en las dos direcciones: agregar un id a `reveals.tui` pide un call site
que no existe (rojo), y darle al cliente una puerta de revelado dispara el barrido de secuencias
(rojo).

---

## 4. `listing:` no aplica a la TUI, **declarado** (FR-029)

```yaml
listing:
  # Los clientes que tienen ficha de tienda. La TUI no está y eso es la
  # respuesta, no un hueco: se distribuye por Homebrew, los dos one-liner y
  # el binario del Release, y ninguna de esas vías tiene tagline ni keywords.
  applies_to: [vscode, intellij, visualstudio]
  tagline: "…"      # sin cambios
  keywords: [ … ]   # sin cambios
```

**El gate sale gratis y es real**: el verificador itera `applies_to` en vez de tener los tres
clientes escritos a mano. Agregar `tui` a esa lista lo manda a buscar un artefacto de tienda en
`tui/`, no lo encuentra, y falla. Y `applies_to` sin `tui` es la declaración explícita que FR-029
pide.

---

## 5. `keymap:`: el mapa de teclas, en el canónico (FR-041)

Hoy no existe: los otros tres clientes no tienen teclas propias (sus atajos son del IDE). La TUI sí,
y FR-041 dice que **se declaran en el canónico con gate, no sólo en el código del cliente**.

```yaml
# EL MAPA DE TECLAS DE LA TUI. Vive acá y no sólo en el cliente por lo mismo que
# icon_vocabulary: es lo último de un control que nadie declaraba, y un cliente
# que lo deriva solo se olvida de la mitad. `only_in: [tui]` porque los otros
# tres reciben sus atajos del IDE.
#
# LA BARRA DE TECLAS SE DIBUJA DE ESTE MISMO MAPA, así que una tecla que existe
# y no se muestra es imposible por construcción. Y la regla de copy se aplica
# igual: si la tecla está en pantalla, la tecla ES el texto.
keymap:
  only_in: [tui]
  # Movimiento de la LISTA. No mueve el cursor de la review.
  movement:
    - {keys: [j, down], does: focus_next_row}
    - {keys: [k, up], does: focus_prev_row}
  # El cursor de la REVIEW. n/p están RESERVADAS para esto y para nada más:
  # es un concepto distinto de navegar la lista, y confundirlos es el error que
  # esta reserva existe para impedir.
  cursor:
    - {keys: [n], action: next}
    - {keys: [p], action: prev}
  actions:
    - {keys: [r], action: refresh}    # en las OCHO situaciones (FR-038)
    # … un renglón por acción con tecla
  overlays:
    - {keys: [":"], opens: action_list}   # el equivalente de surface: action
    - {keys: [g], opens: entry_picker}    # goToEntry
  toggles:
    - {keys: [m], toggles: mouse_reporting}
```

**Gates**: (a) todo id que aparezca en `keymap.actions` existe en `actions:`; (b) ninguna tecla se
declara dos veces en el mismo contexto; (c) `n` y `p` no aparecen fuera de `cursor:`; (d) el mapa del
cliente (`tui/internal/domain/keymap.go`) declara exactamente estos pares; (e) toda acción de
`panel_excluded:` está alcanzable desde `overlays.action_list` y **no** tiene tecla propia.

---

## 6. `not_in: [tui]` en `openAllChanges` (FR-019)

Se agrega el cliente a la lista que ya existe, con su motivo al lado, exactamente como está la
divergencia de Visual Studio:

```yaml
  openAllChanges:
    surface: both
    situations: [review, finish-conflict]
    mode: whole
    # Visual Studio no la ofrece. … (comentario existente, sin cambios)
    #
    # La TUI tampoco. Abrir N diffs de golpe no existe como gesto en un
    # multiplexor: no hay una superficie que sostenga N ventanas, y N
    # invocaciones seguidas del difftool del usuario es una avalancha, no una
    # acción. Las filas del inventario abren cada diff de a uno — la misma
    # información, en la única forma que este cliente puede darla bien.
    not_in: [visualstudio, tui]
```

`actionsNotIn(client)` (líneas 58-74) ya soporta varios clientes por lista: parte por coma y
`includes`. **No hay que tocarla.** Lo que sí hay que agregar es el lado TUI de la verificación en
las dos direcciones: las 26 que sí ofrece están en `tui/internal/domain/actions.go`, y
`openAllChanges` **no**.

---

## 7. Lo que aplica sin cambio de forma

| Clave | Qué exige de la TUI | Gate |
|---|---|---|
| `situations:` | las ocho, con la misma prioridad, más la superficie de espera | fixtures + golden, uno por situación |
| `actions:` | las 26 que ofrece en `actions.go`; `openAllChanges` ausente | mismo par de bucles que el de Visual Studio (964-977) |
| `panel_layout:` | secuencia de controles por situación, tope del **55%** del pie, **una sola barra** | test de contrato de layout propio (FR-047), equivalente de `PanelLayoutContractTest` |
| `icon_vocabulary:` | los cinco nombres, desde **un solo mapa**, ancho no ambiguo, fallback ASCII | el barrido de pares (control, icono) suma la cuarta punta |
| `confirms:` | la tabla + la puerta única + ningún otro modal | los **tres** gates, ver abajo |
| `title_actions:` | las cinco, en la barra de título del panel | secuencia en el layout |
| `draft_controls:` / `guide_rows:` / `fixes_rows:` / `walkthrough_row:` | los cuatro mapas completos; **no cuentan contra las 27** | `rowControlIds` suma la cuarta punta |
| `strings:` | todas las compartidas que la TUI alcanza — y **las alcanza todas** | `requireUserCopy` suma `usercopy.go` |
| `row_shape:` | badge cerrando la línea, iconos antes, botonera abajo | test de contrato de layout |
| `panel_excluded:` | las cuatro **sólo** en el overlay de acciones | gate (e) de `keymap:` |

### `reload_or_wait`: la única string compartida que la TUI no dibuja

El texto dice que se recargue la ventana o se espere, *«porque el panel vuelve a chequear cada pocos
segundos»*. En una terminal no hay ventana que recargar, y volver a chequear cada pocos segundos **es
un poll**, que FR-032 prohíbe y FR-069 prohíbe **decir**.

Resolución, y es la misma forma que las otras dos: la clave **sale de `strings:`** y pasa a
`per_client_strings.after_install`, con los tres valores de hoy verbatim y el cuarto propio de la
TUI, que nombra el próximo paso que sí existe en un pane. No es una exención dentro de `strings:`:
es la misma situación con próximo paso distinto por cliente, exactamente el criterio de FR-076.

---

## 8. Los tres gates de `confirms:` para la TUI (FR-024, FR-071, SC-007, SC-018)

La puerta única del cliente se llama **`domain.ConfirmMutation(id, …)`**, cuarto equivalente de
`confirmMutation` / `UiMessages.confirm` / `GitReviewDialogs.Confirm`. En una TUI, un modal es un
**overlay**; que haya **uno solo**.

| # | Gate | Cómo |
|---|---|---|
| 1 | **La tabla == el canónico** | `collectConfirmingIds(yaml)` (1528) contra la tabla de `tui/internal/domain/confirms.go`, en las dos direcciones |
| 2 | **Todo id declarado pasa por la puerta, leyendo el argumento** | regex sobre el **primer argumento** de `ConfirmMutation(...)` en todo `tui/`. **No** un `includes` del nombre: un id aparece como nombre de función, de constante y de campo, así que un `includes` da verde con el call site cambiado — está probado que daba verde |
| 3 | **No hay ningún otro modal** | sólo `internal/ui/confirm.go` construye el tipo de overlay que bloquea input; ningún otro archivo lo asigna. Es el equivalente del barrido de `showWarningMessage` sueltos que destapó el agujero original |

**La excepción declarada sigue siendo una sola**: `walkthroughInit`, que elige entre dos cursos
("Update" / "Start over") en vez de confirmar con sí/no. Sigue siendo `confirms: true` porque hay un
modal entre el gesto y la mutación, que es lo que la clave dice. El comentario que la exime lo lee
CI: **reformularlo rompe el check**.

**Y lo que el overlay de acciones NO es**: no es un segundo modal. No confirma: elige. Una acción
destructiva elegida ahí pasa por **la misma** puerta que si se hubiera apretado en el cuerpo —User
Story 7, escenario 3—, que es lo que hace que la puerta única sea única de verdad. El gate 2 lo
verifica solo, porque el call site está en el mismo archivo que despacha la elección.

---

## 9. Cómo el verificador aprende a leer el cuarto lenguaje (FR-046)

Hoy parsea TypeScript (regex sobre `.ts`), Kotlin (`includes`) y C# (`includes`). Para Go **no hace
falta un parser nuevo**, y hay dos hallazgos concretos que lo explican:

1. Go escribe sus literales `"..."` o `` `...` ``, así que el idiom `includes(`"${valor}"`)` que ya
   usan Kotlin y C# funciona igual.
2. El helper `squash` existente —`s.replace(/["`+]/g, " ").replace(/\s+/g, " ")`— **ya normaliza
   backticks y `+`**, o sea que cubre los raw strings de Go y su concatenación **sin tocarlo**. Es
   la misma normalización con la que hoy se compara `draft_agent_prompt` en tres lenguajes.

### Rutas del cuarto cliente

| Qué | Archivo | Espejo de |
|---|---|---|
| mínimo de CLI | `tui/internal/domain/version.go` | `version.ts` / `Version.kt` / `Version.cs` |
| comandos npm | `tui/internal/domain/installhint.go` | `installHint.ts` / `InstallHint.kt` / `InstallHint.cs` |
| copy compartida | `tui/internal/domain/usercopy.go` | `userCopy.ts` / `UserCopy.kt` / `UserCopy.cs` |
| copy propia de "no hay un único root" | `tui/internal/domain/usercopy.go` | `state.ts` / `ReviewStateManager.{kt,cs}` |
| `waiting_text` | `tui/internal/domain/usercopy.go` | `panelHtml.ts` / `ReviewPanel.kt` / `PanelView.cs` |
| las 26 acciones | `tui/internal/domain/actions.go` | `package.json` / menú Tools / `ActionArgv.cs` |
| controles de fila | `tui/internal/domain/layout.go` | `panelHtml.ts` / builders de layout |
| iconos | `tui/internal/domain/icons.go` | `ICON_OF` / `IconOf` / la llamada literal |
| confirmaciones | `tui/internal/domain/confirms.go` | `confirmMutation` / `UiMessages` / `GitReviewDialogs` |
| teclas | `tui/internal/domain/keymap.go` | — (sólo TUI) |
| URLs de soporte | `tui/internal/domain/usercopy.go` | `SupportLinks.{kt,cs}` |

### El andamio y su fecha de vencimiento

Las entradas de IntelliJ y Visual Studio entraron con `existsSync(archivo) && …`, que es lo que
permite declarar un cliente antes de que su árbol exista. Es el mismo andamio que usa la TUI **y
tiene el mismo problema**: un archivo ausente pasa en silencio, que es exactamente cómo un cuarto
cliente podría entrar al canónico y no verificarse nunca.

La regla: **la guarda de una ruta se borra en la misma tarea que crea el archivo que protege**, y se
agrega un chequeo de cierre — *si `tui/go.mod` existe, todas las rutas declaradas de la TUI tienen
que existir* —, que convierte el andamio en un error apenas el cliente es real.

---

## 10. La secuencia, y por qué CI no se pone roja en el medio

El riesgo no está en el cambio: está en partirlo mal. La forma y su lector viven en el mismo repo, y
el verificador lee el YAML **de disco en la misma corrida**, así que un commit que cambia uno sin el
otro es rojo garantizado.

| Paso | Qué entra | Toca clientes | CI |
|---|---|---|---|
| **1** | `min_cli_version` → mapa con los cuatro en `"0.8.0"`; `minFor()`; se borra el `min` global | **no** | verde |
| **2** | `multi_root_error` sale de `strings:` → `per_client_strings.no_single_root` con los tres textos verbatim; `perClientString()`; se borra el literal `multi` de JS | **no** | verde |
| **3** | `reload_or_wait` sale de `strings:` → `per_client_strings.after_install`, ídem | **no** | verde |
| **4** | `reveals:` → mapa; los tres clientes con sus cuatro ids de hoy; `tui: []` con su motivo | **no** | verde |
| **5** | `listing.applies_to`; `not_in: [visualstudio, tui]`; `keymap:` con su bloque | **no** | verde |
| **6** | la fixture `divergent-min.yaml` y su test | **no** | verde |
| **7…** | el árbol `tui/` va llegando; cada ruta declarada pierde su `existsSync` en la tarea que la crea | sólo TUI | verde |
| **último** | `min_cli_version.tui` sube a la versión que trae el verbo `ui`; `per_client_strings.*.tui` toman su copy propia | sólo TUI | verde |

Los pasos 1 a 6 son **una sola tarea de "cambio de forma"** en la que **ningún valor se mueve y
ningún archivo de cliente se toca**. El diff es YAML + verificador y nada más, que es lo que lo hace
revisable: si un cliente publicado hubiera cambiado de comportamiento, se vería.

Y la propiedad que queda instalada al final: **subir el mínimo de un cliente es editar una línea del
YAML y una constante de ese cliente.** Ni el canónico ni el código ni el release de los otros tres
se enteran (FR-028).

---

## Qué NO vive en el canónico

- El dibujo concreto de cada glifo (el canónico fija el **nombre** y la regla de ancho; el codepoint
  lo elige el cliente y lo verifica su test).
- El layout carácter por carácter (eso son los golden files del cliente).
- El texto largo del cuerpo de un diálogo (va a `UserCopy`, como en los otros tres).
- La implementación de la vigilancia, los timeouts y el registro de invocaciones.
