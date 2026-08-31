# Research: 015-cliente-tui

**Date**: 2026-08-30

**Fuente de verdad del comportamiento**: `contracts/client-product-surface.yaml`,
`scripts/check-client-product-surface.mjs`, el código de `bin/` y los tres clientes existentes.
No las specs viejas.

La spec ya decidió el lenguaje, la frontera de código, la forma de invocar la CLI, el mecanismo de
refresco, las vías de distribución, dónde vive la configuración, la copy por cliente y la
independencia de `min_cli_version`. Nada de eso se reabre acá. Lo que sigue son las decisiones que
la spec **no** resuelve porque son del *cómo*.

---

## Decisión 1 — Dónde vive el código y cómo se llama el cliente

**Decision**: módulo Go propio en **`tui/`**, con `go.mod` propio; id de cliente en el canónico
**`tui`**.

**Rationale**: el id ya está escrito en la spec (`not_in: [tui]`), y que el directorio se llame
igual borra la traducción mental que los otros tres sí piden. Un `go.mod` propio (en vez de un
módulo raíz con un paquete adentro) es el mismo patrón que ya usan los otros tres clientes: proyecto
npm aparte, módulo Gradle aparte, solución .NET aparte. Además acota `go test ./...` y hace que la
frontera de FR-075 sea verificable leyendo un solo archivo.

**Alternatives considered**:
- `terminal-ui/` o `tui-client/` → nombra la misma cosa con más letras y desalinea el id.
- Módulo Go en la raíz del repo → mete `go.mod`/`go.sum` en la raíz de un repo cuyo producto
  principal es shell, y arrastra `go test ./...` a todo el árbol.

---

## Decisión 2 — El verbo `ui`: forma exacta y sus trampas

**Decision**: `bin/git-review-verbs/ui`, shell POSIX, `set -eu`, `prog="git review ui"`. Orden de
resolución `${GIT_REVIEW_UI:-}` → `command -v git-review-ui`. `exec` en los dos casos. Sin
`A && B || C`. `-h` imprime usage y sale 0; el resto de los argumentos se pasan tal cual.

Forma del cuerpo (el `if` invertido es obligatorio: `command -v x && exec x || die` corre `die`
también cuando el `exec` falla):

```sh
ui="${GIT_REVIEW_UI:-}"
if [ -z "$ui" ]; then
	ui="$(command -v git-review-ui || true)"
fi
if [ -z "$ui" ]; then
	cat >&2 <<EOF
error: the git review terminal UI is not installed.
...
EOF
	exit 1
fi
exec "$ui" "$@"
```

**Rationale**: `command -v` es POSIX y respeta el `PATH` del usuario; `exec` es lo que hace que
señales y exit code lleguen a la shell sin intermediarios (FR-002, SC-011). Con `$GIT_REVIEW_UI`
apuntando a algo inexistente el `exec` falla y la shell imprime su propio error — correcto: la
variable la puso el usuario, y esconder ese error detrás del hint de instalación sería mentir sobre
qué pasó.

**Trampas del repo que el verbo dispara y que hay que atender en el mismo cambio**:

| Dónde | Qué pasa si se olvida |
|---|---|
| `bin/git-review` § `Commands:` | el verbo existe pero `git review -h` no lo lista (FR-005) |
| `completions/git-review-workflow.{bash,zsh,fish}` | tres archivos, FR-005 pide los tres |
| `tests/dispatcher-only.bats:12` | `VERBS=` es una **lista hardcodeada**; sin `ui` el test queda tautológico para el verbo nuevo |
| bit de ejecución 100755 | `tests/packaging.bats` y el job `lint` de CI lo afirman; un archivo agregado desde Windows llega 100644 |
| `shellcheck` de `ci.yml` y `release.yml` | `find bin -type f` ya lo cubre solo; **`tui/bump-version.sh` no**, y hay que agregarlo a las dos listas |

**Alternatives considered**:
- Que el verbo busque el binario en el libexec de la CLI → imposible: la TUI la instala otro gestor
  de paquetes en otro prefijo, y por eso el ejecutable va al `PATH` (FR-006).
- Que el verbo ofrezca instalar → contra la regla del proyecto (*negarse, no preguntar ni actuar por
  el usuario*).

---

## Decisión 3 — La arquitectura Elm, y qué entra a `Update`

**Decision**: un solo `Update` con seis clases de mensaje, y **ningún** estado derivado fuera del
modelo:

```text
tea.KeyMsg / tea.MouseMsg      -> intent tipado (nunca una acción directa)
tea.WindowSizeMsg              -> Viewport
tea.FocusMsg / tea.BlurMsg     -> disparador 3
watchMsg{}                     -> disparador 2 (sin payload, FR-062)
readDoneMsg{ReviewState,err}   -> resultado de una lectura
mutationDoneMsg{id,Result}     -> resultado de una mutación
```

Las invocaciones salen como `tea.Cmd` (goroutine + `Program.Send`), nunca en línea: un `Update` que
bloquea es un pane congelado.

**Rationale**: es literalmente el modelo del problema, y es lo que hace que "exactamente un
repintado" (SC-004) sea una propiedad y no una coincidencia de timing — ver Decisión 4.

---

## Decisión 4 — `PanelModel` comparable por valor, y por qué SC-004 depende de eso

**Decision**: `PanelModel` es un `struct` **comparable por valor** en Go: sin mapas, sin slices y
sin punteros. Las listas (entradas, ramas, filas de borradores, guías, fixes) son **strings ya
proyectados** o arreglos de tamaño fijo con su largo, y todo lo variable se guarda en un campo
`Rows string` construido por el proyector. `View` es **puro**: `PanelModel + Viewport -> (frame, HitMap)`.

**Rationale**: es lo que permite afirmar SC-004 sin cronometrar nada. Una mutación produce una
lectura al terminar y, si la ventana de silencio se comió disparos, **una segunda lectura** cuando
la ventana cierra (ver `contracts/refresh.md`). La segunda devuelve el mismo estado, el
`PanelModel` es igual al anterior, y `Update` no marca el modelo como cambiado: **no hay frame**.
SC-004 se afirma sobre el repintado, no sobre el número de lecturas, y así la corrección no depende
de adivinar cuánto tarda inotify en callarse. De yapa: dos `PanelModel` comparables hacen que los
golden files tengan un antecedente exacto —si el modelo es igual, el frame es igual— y que el test
de contrato de layout compare estructuras y no pantallas.

**Alternatives considered**:
- Comparar los frames renderizados en vez de los modelos → funciona, pero renderiza dos veces para
  descubrir que no hacía falta, y ata el "no repintó" al ancho del pane.
- Suprimir la segunda lectura y confiar en que la ventana alcanza → deja un agujero real: un cambio
  externo que aterriza dentro de la ventana se pierde hasta el próximo disparador.

---

## Decisión 5 — El apagado total de la vigilancia es una *interface*, no un `if`

**Decision**: `internal/host/watch.go` declara

```go
type Watcher interface {
    Start(ctx context.Context, set WatchSet, out chan<- struct{}) error
    Rebuild(set WatchSet) error
    Stop() error
}
```

con dos implementaciones: `fsnotifyWatcher` (el único lugar del árbol que importa `fsnotify`) y
`nopWatcher`. La elección se hace **una sola vez**, en `cmd/git-review-ui/main.go`, desde
`GIT_REVIEW_UI_WATCH`. **La suite corre con `nopWatcher` por default**, así que FR-063 y SC-016 se
prueban por construcción en todos los tests, y `watch_fsnotify_test.go` es el único paquete que
instancia el real.

**Rationale**: un flag chequeado en veinte lugares deja veinte formas de que la corrección dependa
del watcher. Una interface con un no-op deja **cero**: si algún camino necesitara que el watcher
disparara, todos los tests estarían rojos, no uno.

**Por qué `GIT_REVIEW_UI_WATCH` y no `reviewui.watch`**: FR-061 dice que las **preferencias** viven
en `reviewui.*`. Apagar el motor no es una preferencia del revisor: es una palanca de soporte y de
suite. Meterla en `reviewui.*` la volvería superficie de producto, y entonces habría que dibujarla,
declararla y documentarla en un README. Va a `tui/CONTRIBUTING.md`, que es donde vive el desarrollo.

**Alternatives considered**:
- Un flag `--no-watch` en el binario → superficie de producto no declarada en el canónico.
- Compilar dos binarios con build tags → un binario de release distinto del que testeás.

---

## Decisión 6 — El conjunto vigilado: seis raíces, cierre por directorios, presupuesto

**Decision**: las **seis raíces** que la spec fija (FR-033, FR-080) son las semillas. El conjunto real es
su **cierre sobre directorios**, con una allowlist de prefijos y un presupuesto de profundidad y de
cantidad. Nunca se vigila un archivo de ref. Todo el detalle está en
[contracts/refresh.md](./contracts/refresh.md); lo que sigue es el porqué.

El cierre **no es opcional**, y lo prueban dos hechos del repo que no se ven desde la spec:

1. **Los borradores anidan.** `walk_draft_path` compone
   `<git-dir>/review-walkthrough/<src>.md`, y `<src>` es un nombre de rama: para `feature/foo` el
   archivo es `review-walkthrough/feature/foo.md`, o sea un subdirectorio. `walk_draft_list`
   **recursiona** (`_walk_draft_list_dir`) justamente por eso. Vigilar
   `review-walkthrough/` sin descender deja mudo el escenario 3 de la User Story 1 —el agente
   escribiendo el borrador— para toda rama con barra en el nombre, que son la mayoría.
2. **La creación de un borrador no escribe config.** `branch.<rb>.reviewdraft` la escriben `start` y
   `compare`, no `walkthrough draft`: un borrador nacido fuera de una review no toca `config`. Así
   que la hipótesis cómoda —"todo cambio de estado pasa por `config`, y `config` está vigilado"— es
   **falsa**, y el cierre sobre los dos directorios de borradores es la única cobertura.

Lo mismo del lado de los refs: `refs/heads/review/<branch>` y `refs/review-edits/<src>/<step>` están
dos y tres niveles adentro, y sus directorios intermedios **nacen y mueren** con las reviews.

**Rationale de que esto no contradice FR-033**: la exigencia es *contenedores, no refs finos*, y
"MUST NOT depender de la existencia de un ref concreto como archivo". Cada entrada agregada por el
cierre es un **directorio**; ninguna es un ref. Las seis raíces siguen siendo las declaradas: lo
que el plan define es cómo se descubren sus contenedores hijos.

**La sexta raíz no mueve el presupuesto.** `<git-dir>` filtrada a `HEAD` es de profundidad 0, como la
del directorio común: suma **una** entrada en un worktree enlazado y **cero** fuera de él, donde se
funde con la del común por el dedup. `max_dirs` sigue en 512 y la allowlist de prefijos de `refs/` no
cambia — la raíz nueva no descuelga ningún subárbol, y los dos directorios de borradores siguen
siendo raíces propias con su profundidad 3 aunque vivan adentro del mismo `<git-dir>`, porque el
filtro `{HEAD}` no los alcanza.

**Alternatives considered**:
- Vigilancia recursiva a secas → en `refs/remotes/` de un repo grande son miles de watches y una
  tormenta en cada `fetch`, y fsnotify no recursiona solo en Linux de todos modos.
- No descender y aceptar el agujero → deja fuera el caso que la spec pone como escenario de
  aceptación, no como borde.

---

## Decisión 7 — La sexta raíz: `<git-dir>` filtrada a `HEAD`

*(Revisada. Una versión anterior de este plan declaraba el cambio de rama como punto ciego, porque
tomaba las cinco raíces como una ley. No lo eran: FR-033 ahora fija **seis** y FR-080 declara la
nueva.)*

**Decision**: se vigila `<git-dir>/` filtrada a **`HEAD`**. Sobre `<git-dir>` y no sobre el común,
porque cada worktree tiene el suyo y el que le importa al panel es el del worktree donde estás
parado. Cuando los dos resuelven al mismo directorio, la raíz se cuenta **una sola vez**.

**Rationale**: `git checkout` en otro pane no escribe `config`, no escribe bajo `refs/` y no toca los
borradores — escribe `HEAD` y el índice. Y es el evento que **más** cambia lo que el panel muestra,
porque toda la sesión de review es por rama: sin esta raíz, cambiar de rama dejaba el panel entero
describiendo otra cosa hasta el próximo focus-in.

**No agrega fragilidad**, y el argumento es el que la spec ya fijó: es la **misma forma** que
`config` y `packed-refs` —directorio vigilado, filtrado por nombre de archivo—, no un mecanismo
nuevo; y `HEAD`, como `config`, es parte de la disposición **documentada** del repositorio
(`gitrepository-layout`), o sea de lo menos frágil que hay para mirar. Lo frágil de verdad es el
empaquetado de refs y el backend alternativo, que el diseño ya trata como best-effort. Las cotas no
se mueven: FR-062 (no lee contenido), FR-063 (correcta con la vigilancia apagada), FR-064 (ruta
ausente se ignora).

**Dos consecuencias concretas de implementación**:

1. **El dedup deja de ser trivialidad y pasa a ser una regla**: el conjunto está indexado por
   directorio y el filtro de un directorio repetido es la **unión** de sus filtros. Fuera de un
   worktree enlazado eso da una entrada con `{config, packed-refs, HEAD}`. Tiene su test, porque es
   una propiedad fácil de romper sin que nada se note.
2. **`HEAD` es la única raíz con una ráfaga plausible** — un `rebase` lo reescribe una vez por commit
   —, y lo que la acota es el **techo de 1 s del debounce** que ya existía por otro motivo (Decisión
   6). Es la segunda razón por la que ese techo no es opcional.

**Lo que queda afuera después de esto**: sólo el agujero 5 (inotify que no dispara), que falla en
silencio y se compensa con los otros tres disparadores, y el índice/working tree, que el panel no
reporta. Todo lo que mueve lo que el panel muestra tiene ahora un camino.

---

## Decisión 8 — Las dos migraciones del canónico son *value-preserving*

**Decision**: en el commit que cambia la **forma**, ningún valor cambia y ningún archivo de los tres
clientes publicados se toca.

- `min_cli_version` pasa de escalar a mapa con **los cuatro** declarados, y los cuatro se siembran
  en `"0.8.0"` —el valor de hoy—. `vscode-extension/src/cli/version.ts`, `Version.kt` y `Version.cs`
  quedan intactos.
- `multi_root_error` sale de `strings:` y aterriza en `per_client_strings.no_single_root` con los
  **tres textos actuales copiados verbatim**. Los tres state managers quedan intactos.

Recién después, en commits separados e independientes, la TUI declara su propio mínimo (la versión
que introduce el verbo `ui`) y su propia copy de "no hay un único root".

**Rationale**: es lo único que hace que "sin dejar CI roja en el medio" sea verdad y no una promesa.
La forma y su lector viven en el mismo repo, así que se cambian en el **mismo commit** —partirlos es
precisamente lo que pone CI roja— y como los valores no se mueven, ese commit no tiene ningún efecto
de producto que revisar. El diff es legible: YAML + verificador, nada más.

**Consecuencia que hay que decir en voz alta**: la copy de "no hay un único root" **no cambia** para
los tres clientes publicados. FR-076 exige que se **declare** por cliente, no que se reescriba; los
tres IDEs comparten el próximo paso ("abrí un workspace de una sola carpeta") y por eso hoy sus
bytes coinciden. Que tres valores de un mapa por cliente sean iguales no es drift, por la misma
razón que no lo es en `min_cli_version`: cada uno es la única fuente de su cliente y ninguno hereda
del otro.

**Alternatives considered**:
- `min_cli_version` escalar como default con overrides → es exactamente lo que las Assumptions de la
  spec descartan: un default es "el piso de quien no declaró", un valor que nadie eligió y todos
  heredan.
- Dejar `multi_root_error` en `strings:` con una excepción anotada → rompe la única cosa que
  `strings:` significa. Sale del mapa o el mapa deja de querer decir algo.
- Un `shared:` con los tres IDEs y un `tui:` aparte → reintroduce el default por la ventana: el día
  que un IDE necesite decir otra cosa hay que romper el grupo, y hasta ese día nadie sabe si el
  valor compartido es una decisión o una inercia.

---

## Decisión 9 — Cómo el verificador aprende a leer un cuarto lenguaje

**Decision**: sin parser nuevo. El verificador ya compara **constantes entrecomilladas**, y Go
escribe sus literales igual que los otros tres: `"..."` o `` `...` ``. Dos hallazgos concretos:

- El helper `squash` existente —`s.replace(/["`+]/g, " ").replace(/\s+/g, " ")`— ya normaliza
  backticks y `+`, así que **cubre los raw strings de Go y su concatenación sin tocarlo**.
- El idiom `existsSync(archivo) && includes("valor")` con el que entraron IntelliJ y Visual Studio
  es el mismo con el que entra la TUI, y sirve de andamio mientras el árbol no existe.

Lo que sí cambia es la **forma de preguntar**: donde hoy hay un escalar global (`min`) y una lista de
tres superficies, pasa a haber `minFor(client)` / `perClientString(name, client)` y una lista de
**cuatro**. El detalle de cada punto está en
[contracts/client-product-surface.md](./contracts/client-product-surface.md).

**Andamio con fecha de vencimiento**: `existsSync` hace que un cliente sin archivos pase en silencio
—que es cómo un cuarto cliente podría "entrar" al canónico y nunca verificarse—. La regla: **la
guarda de la TUI se borra en la misma tarea que crea el archivo que protege**, y hay un chequeo que
falla si `tui/` existe y alguna de sus rutas declaradas no.

---

## Decisión 10 — Glifos: la regla es el ancho, no el dibujo

**Decision**: `internal/domain/icons.go` responde los cinco nombres de `icon_vocabulary:` desde **un
solo mapa**, y cada entrada trae **dos** glifos: el Unicode y el ASCII. El gate no es una lista de
codepoints elegidos a mano sino dos tests:

1. cada glifo Unicode del mapa mide **exactamente una celda** —East Asian Width `Narrow` o
   `Neutral`, nunca `Wide` ni `Ambiguous`— pasado por la misma tabla de ancho que usa el renderer;
2. cada glifo ASCII está en `U+0020..U+007E`.

La selección se hace **con el test corriendo**, no en este documento: un codepoint fijado acá y otro
en el código es el drift que el mapa único existe para evitar.

**Rationale**: `Ambiguous` es el modo de falla real —se dibuja en una celda en un terminal y en dos
en otro, y ahí las columnas de todas las filas se desalinean— y no lo detecta ningún ojo humano en
la máquina donde se escribió. Emoji queda prohibido por FR-043, pero prohibir emoji no alcanza:
`≡`, `▶` y media Geometric Shapes son `Ambiguous` sin ser emoji.

**Cuándo cae al ASCII**: `NO_COLOR` no lo decide (eso es color, no dibujo). El fallback lo dispara
el locale/codepage: `LC_ALL`/`LC_CTYPE`/`LANG` sin UTF-8, o un codepage de consola de Windows que no
sea 65001. Es una decisión de arranque, y hay un override de soporte para forzarla en los tests
(`GIT_REVIEW_UI_ASCII=1`), que es lo que hace posible el juego de golden `-ascii`.

---

## Decisión 11 — Portapapeles: OSC 52, y qué se dice cuando no se puede

**Decision**: `internal/host/clipboard.go` emite **OSC 52** al terminal. No se shellea a `pbcopy`,
`xclip`, `wl-copy` ni `clip.exe`: por SSH y dentro de un multiplexor esas herramientas copian al
portapapeles de la máquina equivocada o no existen, que es el escenario que la spec pone primero.

OSC 52 **no tiene acuse**: el terminal no contesta si copió. Por eso la degradación no se detecta,
se **elige**: la TUI conoce los casos en los que OSC 52 no llega —tmux/screen sin `set-clipboard on`,
terminales con la secuencia deshabilitada— sólo por lo que el usuario reporta, no por lo que el
terminal dice. Consecuencia de diseño, y es lo que FR-068 pide:

- El control de copiar **nunca afirma haber copiado**. Su acuse dice lo que sí es verdad, y la línea
  con el comando queda dibujada limpia y seleccionable al lado, junto con el estado del mouse.
- El toggle de mouse y el control de copiar son **la misma conversación**, como dice la spec: con el
  reporte de mouse activo el terminal no hace selección nativa por arrastre, así que la línea
  seleccionable no se puede seleccionar. La tecla que apaga el mouse es la que la habilita, y el
  panel muestra ese estado.

**Alternatives considered**:
- Sondear el soporte de OSC 52 con una consulta y esperar respuesta → agrega un timeout al arranque
  para una respuesta que la mayoría de los terminales no manda.
- Afirmar "Copied" y listo → es exactamente lo que FR-068 prohíbe.

---

## Decisión 12 — Las cuatro delegadas, y cómo se recupera la pantalla

**Decision**: `openEntry`/`openChange` → `$EDITOR`; `previewEdits`/`compareReview` → `git difftool`
o `$PAGER` con el color de git. Se lanzan con `tea.ExecProcess`, que suspende el programa, entrega
el TTY al hijo y lo recupera al volver — y **al volver dispara un refresco** (el revisor pudo haber
editado y guardado adentro del editor).

Detalles que no son opcionales:
- El path que va al editor es el **mostrable**; el que vuelve a la CLI es el **crudo** (`PathRef`).
- Un `$EDITOR` con argumentos (`"code -w"`, `"nvim -R"`) se parte con reglas de shell POSIX, no con
  `strings.Fields`. Sin eso, `EDITOR="code -w"` busca un ejecutable llamado `code -w`.
- `$EDITOR` ausente o inexistente: el mensaje dice **qué no pasó**, no qué comando falló (FR-024 de
  la extensión, § copy). Lo mismo con `diff.tool` sin configurar → cae a `$PAGER`, y sin `$PAGER` a
  `less`, y sin nada dice qué no pasó.
- Un archivo borrado en el rango: `openEntry` no es fatal; el resultado es informativo, como en los
  otros tres.

**Rationale**: quien vive en un multiplexor ya tiene esas tres cosas configuradas mejor de lo que
esta TUI las va a resolver, y un visor propio sería lo primero de este cliente que no respeta lo que
la máquina ya sabe.

---

## Decisión 13 — Credenciales: el centinela de askpass sin script embebido

**Decision**: para la clase **red** (hoy sólo `start` y `forget --delta --stale`) el entorno lleva
`GIT_TERMINAL_PROMPT=0` y `GIT_ASKPASS`/`SSH_ASKPASS` apuntando **al propio ejecutable de la TUI**,
con `GIT_REVIEW_UI_ASKPASS=1` en el entorno. `main` detecta ese centinela como primera cosa que hace
y sale con código distinto de cero sin imprimir nada.

**Rationale**: los otros clientes documentan "un no-op multiplataforma embebido" y eso, en la
práctica, es un script que hay que escribir, empaquetar, chmodear y encontrar en disco — en Windows,
dos. La TUI ya tiene un ejecutable en una ruta conocida (`os.Executable()`), estático y presente en
las siete plataformas. Cero archivos nuevos, cero rutas que resolver, y el centinela es una rama de
tres líneas en `main`.

**Cuidado que hay que tomar**: el centinela va **antes** de cualquier inicialización de terminal. Un
askpass que abre alt-screen le arruina la pantalla al `git` que lo llamó.

---

## Decisión 14 — npm queda afuera de la v1

*(Revisada. Este plan propuso primero el patrón de un envoltorio más siete paquetes por plataforma, y
después un paquete único con los binarios adentro. FR-049 descarta la vía entera.)*

**Decision**: la TUI **no se publica en npm**, ni como paquete único ni como envoltorio con paquetes
por plataforma. Las vías son Homebrew, los dos one-liner y el binario del GitHub Release.

**Rationale**: `bin` en un `package.json` mapea a **un** archivo. Un paquete con varios binarios
necesita algo que elija cuál correr, y ese algo no puede ser el binario: tiene que ser un shim.
En npm ese shim es JavaScript —o `sh`, que en Windows cae en el problema del `sh` en el `PATH`—.
O sea que instalar la TUI por npm **pediría Node para correr un binario estático de Go**: exactamente
la dependencia de runtime que motivó elegir el lenguaje, reintroducida en una sola de las vías, más
dos o cuatro procesos extra en cada arranque. A eso se suma que el tarball llevaría todas las
plataformas y que vendorear ejecutables en npm rompe el bit de ejecución en silencio y sólo en POSIX.

**Y nadie queda bloqueado**, que es lo que hace barata la decisión: el binario del Release es un
archivo. Se obtiene con `curl`, con `wget`, con el navegador o con un `COPY` en un Dockerfile, sin
registro, sin runtime y sin gestor de paquetes — es el artefacto más portable que publica el
proyecto. Lo que cambia es la ergonomía de quien busca `npm i -g` por costumbre, y a ése le contesta
el hint del verbo (Decisión 15).

**Alternatives considered**:

- *Envoltorio + siete paquetes por plataforma* (el patrón de esbuild, swc, biome): es el estándar,
  pero cuesta una organización nueva en el registro, ocho publicaciones y un orden de publicación que
  **falla en silencio** si se invierte, y no elimina el shim JS.
- *Paquete único con los binarios adentro*: quita la ceremonia pero conserva lo que de verdad
  molesta —el shim JS, o sea Node— y suma un tarball con todas las plataformas.
- *`postinstall` que baja el binario*: lo prohíbe FR-049, y con razón — se rompe con
  `--ignore-scripts`, pide red durante el install y es la línea donde `npm i` deja de ser
  reproducible.
- *Publicar igual y documentar el requisito de Node*: es pedirle al usuario que cargue con un runtime
  para no cambiar de comando. La asimetría manda: **agregar npm después es gratis; sacarlo después es
  una deprecación** con un nombre publicado que hay que mantener o retirar.

---

## Decisión 15 — La matriz del Release, y el hint por plataforma

*(Revisada. Antes fijaba qué cuatro binarios viajaban en el tarball de npm y su presupuesto de
tamaño; sin esa vía no hay segunda matriz y lo que queda es cómo el verbo apunta a la vía correcta.)*

**Decision**: las **siete** plataformas van al Release y no hay una segunda matriz más chica. El hint
de `git review ui` **no es uno solo genérico**: nombra la vía que corresponde a dónde corre (FR-081).

| Dónde | Qué nombra el hint |
|---|---|
| macOS | `brew install` desde el tap del proyecto |
| Linux con `brew` en el `PATH` | lo mismo |
| Linux sin `brew` | `web-install.sh` con su flag |
| Windows | `web-install.ps1` con `-WithUi` |
| Cualquier otro caso | la página del Release |

**Rationale**: con cuatro vías y sin npm, un hint genérico obliga al usuario a averiguar cuál le toca
—que es trabajo que la máquina ya puede hacer—. Se decide con lo que la shell sabe sin salir a la
red: `uname` y si `brew` está en el `PATH`. Y una plataforma fuera de la matriz sigue sin bloquear a
nadie: el hint cae a la página del Release, que es un archivo descargable.

**Restricción de implementación**: el verbo es shell POSIX con `set -eu` y **no puede usar
`A && B || C`** (SC2015 falla en Ubuntu y en Windows en CI). La forma es un `case` sobre `uname` con
un `if` invertido para la prueba de `brew`.

**Alternatives considered**: un hint único que liste las cuatro vías —más corto de escribir, y le
pasa al usuario el trabajo de descartar tres—; y detectar la vía consultando la red para ver qué
assets existen, descartado porque un verbo que se niega no debería necesitar red para explicar por
qué.

---

## Decisión 16 — Homebrew: fórmula propia, y qué depende de qué

**Decision**: `Formula/git-review-ui.rb`, con `url`/`sha256` por plataforma (`on_macos`/`on_linux` ×
`on_arm`/`on_intel`) apuntando a los assets del Release de `tui-v*`. `depends_on "git"` y **nada
más**. La fórmula de la CLI no se toca (FR-050).

**La decisión que no es obvia**: la fórmula **no** declara `depends_on "git-review-workflow"`. La
TUI necesita la CLI, pero la CLI llega por cuatro vías y Homebrew sólo ve una; una dependencia dura
le instalaría una segunda copia a quien ya la tiene por npm o por un one-liner. Y `cli-missing` no es
un error: es una **situación de panel completa**, con su copy y su comando copiable, diseñada
justamente para este momento.

---

## Decisión 17 — Los dos one-liner: un flag **apagado**, y cómo encuentran el release

*(Revisada. Esta decisión proponía instalar la TUI por default con opt-out; FR-079 lo prohíbe. Lo
demás —cómo resuelven el ref, la verificación y el modo de falla— sigue en pie sin cambios.)*

**Decision**: **instalar la CLI deja exactamente lo que deja hoy.** La vía one-liner de la TUI es un
flag **explícito y apagado** del mismo instalador: `GIT_REVIEW_WITH_UI=1` en `web-install.sh` (la misma
forma que ya tienen `PREFIX` y `REF`) y `-WithUi` en `web-install.ps1`. Sin el flag no se descarga ni
se escribe nada de la TUI —ni siquiera una consulta a la API—, y el instalador **no prompt-ea** por
él: el proyecto se niega con un hint, no pregunta, y eso vale también para un instalador.
`web-uninstall.*` sí la borran si está.

**Rationale**: que la TUI esté disponible por una vía no autoriza a esa vía a entregarla sin que se la
pidan. Un one-liner que instala la CLI y de paso baja ~10 MB de binario que nadie pidió es una
sorpresa — y una que además cambia lo que hay en el `PATH`. El argumento que sostenía el opt-out
("FR-048 dice las mismas cuatro vías, y una vía a medias no es una vía") confundía *ofrecer* con
*entregar*: la vía existe y está documentada; lo que no hace es actuar sola.

**Gate**: un test que corre el instalador **sin** el flag y afirma que no quedó ningún archivo de la
TUI y que no se pidió ninguna URL de la TUI. Es la mitad que se rompe en silencio — agregar el paso
«por comodidad» no falla nada por sí solo.

Tres detalles que el diseño del release impone al camino del flag:

- **No pueden usar `releases/latest`**, porque el Release de la TUI se crea con `--latest=false`
  (FR-052) exactamente para no robarle ese endpoint al instalador de la CLI. Resuelven el ref
  listando `releases?per_page=100` y quedándose con el primer tag que empieza con `tui-v`.
- **Verifican el `sha256`** del asset contra el `SHA256SUMS` publicado en el mismo Release, y si no
  coincide **no instalan**. Un instalador que baja un binario y no lo verifica es peor que no tener
  esa vía.
- Sin asset para la plataforma (la Assumption de la spec: la CLI corre donde no hay binario), el
  instalador **salta el paso con una nota** y la CLI queda instalada igual. `git review ui` se niega
  después con el mismo hint accionable, que es el comportamiento correcto y no un caso sin cubrir.
  La matriz es la del Release —las siete—, que desde que npm quedó afuera es la única que hay
  (Decisión 14).

---

## Decisión 18 — Golden files: cuáles, y cómo se garantiza que CI no los regenera

**Decision**: un golden por **clave de layout** (no por situación: `no-review` y `no-review-setup`
son dos, y `review` son tres —walk, step, whole—) × 2 tamaños × 3 modos de dibujo
(default, `NO_COLOR`, ASCII forzado). Se rinden desde una `PanelModel` fija construida en
`testdata/porcelain/`, no desde un repo real: un golden que depende de un sandbox es un golden que
cambia solo.

**FR-070 —"MUST NOT regenerarse automáticamente en CI"— se cumple con un build tag, no con un `if`**:
la bandera `-update` sólo se **compila** bajo `//go:build goldenupdate`. En el binario que CI
construye la bandera no existe, así que pasarla es un error de flag desconocido, no un no-op
silencioso. Se regeneran a mano con `go test -tags goldenupdate ./internal/ui -update` y se revisan
como diff.

**Alternatives considered**:
- `-update` guardado por `os.Getenv("CI")` → depende de que el ejecutor setee `CI`, y hay runners que
  no. Un guard que se puede olvidar no es un guard.

---

## Decisión 19 — La lista completa de acciones: qué superficie es exactamente

**Decision**: una tecla abre un **overlay de lista filtrable** (`bubbles/list` + `textinput`) que
enumera **las acciones que la situación actual habilita**, con su tecla al lado donde la tengan. Es
el equivalente de `surface: action` de los otros tres, y las cuatro de
`panel_excluded: [goToEntry, forgetReview, previewEditsStat, showCliLog]` viven **sólo** ahí.

**Lo que no es**: no es un segundo modal. La regla de FR-024 dice "ningún otro modal" hablando de
**confirmaciones**, y esta lista no confirma nada: elige. Una acción destructiva elegida desde acá
pasa por **la misma** puerta (`ConfirmMutation`) que si se hubiera apretado en el cuerpo — es el
escenario 3 de la User Story 7, y es lo que hace que la puerta única sea única de verdad. El gate lo
verifica leyendo el argumento en el call site, no buscando el nombre suelto.

**`goToEntry` es un picker aparte**, no la misma lista: enumera **entradas**, no acciones. Salta a
una entrada **sin mover el cursor de la CLI** (User Story 3, escenario 5), lo que significa que abre
la entrada y punto — no invoca `next`/`prev` N veces.

---

## Decisión 20 — Orden de implementación (por capas, como el plugin de JetBrains)

Aunque el release es paridad completa, el orden de merge es por capas y cada una deja la TUI usable:

1. **Canónico primero, y solo.** Las dos migraciones de forma *value-preserving* (Decisión 8) + el
   verificador enseñado a preguntar por cliente. **No toca ningún cliente.** Se mergea y CI queda
   verde con los tres de siempre.
2. **El verbo y su bats.** `bin/git-review-verbs/ui`, usage, tres completions, `dispatcher-only`,
   `tests/ui.bats`. La TUI todavía no existe: el verbo se niega, que es la mitad de la User Story 2.
3. **Scaffold Go + dominio + golden vacíos.** `go.mod`, parsers, situación, `PanelModel`, `UserCopy`,
   iconos, keymap, tabla de confirmaciones. Todo unit, sin terminal.
4. **Host + lectura + dibujo read-only.** Invocador, clases, `GIT_REVIEW_ADVICE=0`, `PanelModel` a
   pantalla, las ocho situaciones, golden completos, `waiting_text`. **Sin vigilancia**: los
   disparadores 1, 3 y 4. Acá la TUI ya es útil y FR-063 está probado antes de existir el watcher.
5. **La vigilancia.** `Watcher`, `WatchSet`, cierre, debounce, ventana de silencio, y sus cinco tests
   sobre repo real. El disparador 2 se agrega a algo que ya andaba sin él.
6. **Mutaciones y el ciclo de riesgo.** Puerta única, asistente de inicio, `finish`/`undo`/`resume`,
   lock de profundidad 1.
7. **El pie y los tres mapas de fila.** Walkthrough, guías, borradores, fixes, settings, support.
8. **Overlay de acciones, picker, delegadas, mouse, portapapeles.**
9. **Empaquetado y release.** La fórmula, los dos one-liner, `release-tui.yml`,
   `version-consistency.bats`, los dos README, la landing, `tui/CONTRIBUTING.md`.

El paso 1 va primero **a propósito**: es el único que toca a los tres clientes ya publicados, y
mezclarlo con código nuevo del cuarto es lo que haría imposible revisar si un cliente publicado
cambió de comportamiento.

---

## Open items resueltos por default (sin preguntar)

| Item | Default | Dónde |
|---|---|---|
| Nombre del directorio y del id de cliente | `tui/` y `tui` | Decisión 1 |
| Versión de Go y dónde vive el pin | última estable, `tui/go.mod` | Technical Context |
| Cómo se apaga la vigilancia | interface + `nopWatcher`, `GIT_REVIEW_UI_WATCH` | Decisión 5 |
| Dónde va la raíz de `HEAD`, y el dedup | `<git-dir>`, filtro `{HEAD}`, unión de filtros al repetirse | Decisión 7 |
| Si la copy de "no hay un único root" cambia para los tres IDEs | **no**: cambia dónde se declara | Decisión 8 |
| Si la TUI se publica en npm | **no**, en ninguna forma; la vía pediría Node para un binario de Go | Decisión 14 |
| Matriz del Release y hint por plataforma | las siete; el hint nombra la vía según `uname` y `brew` | Decisión 15 |
| Si la fórmula depende de la CLI | no | Decisión 16 |
| Cómo se pide la TUI desde un one-liner | flag apagado: `GIT_REVIEW_WITH_UI=1` / `-WithUi`, sin prompt | Decisión 17 |
| Por qué el flag no se llama `GIT_REVIEW_UI` | esa variable ya es la **ruta al ejecutable** que lee el verbo; reusarla rompe `git review ui` si queda exportada | Decisión 17 |
| Cómo se impide regenerar golden en CI | build tag, no `if` | Decisión 18 |
| Portapapeles | OSC 52, sin acuse, sin shellear | Decisión 11 |
| No-op de askpass | el propio ejecutable, con centinela | Decisión 13 |
