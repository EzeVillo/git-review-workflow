# Research: Extensión de VS Code para revisar con walkthrough

Decisiones técnicas previas al diseño. El principio que ordena casi todas es el
mismo que `CLAUDE.md` fija para la CLI —**espejar los idioms del host**—
trasladado de git a VS Code: cuando el editor ya tiene una forma nativa de
resolver algo, se usa ésa antes que inventar una propia. La otra restricción
transversal es FR-001/SC-005: ningún camino deriva estado de review fuera de la
CLI.

Los datos del lado de la CLI se verificaron contra el código, no contra los
contratos: `bin/git-review-verbs/status`, `bin/git-review-lib.sh` y
`bin/git-review` en el árbol actual (VERSION `0.3.0`).

---

## Decisión 1 — Requisito mínimo de CLI: `0.3.0`

**Decisión**: la extensión exige `git review` ≥ `0.3.0` y trata cualquier
versión anterior como el caso "CLI vieja" de FR-022.

**Rationale**: el contrato porcelain (`status --porcelain`, `status --why`,
`list --porcelain`, exit codes `2`/`3`) entró en el commit `8665e90` y la
primera versión que lo contiene es `0.3.0` — la publicada al escribirse el spec
era `0.2.1`. El sondeo es `git review --version`, que imprime la versión pelada
en una línea (`bin/git-review:62`, `echo "$VERSION"`), sin prefijo ni nombre:
comparar es partir en `.` y comparar tres enteros.

**Alternativas consideradas**:

- *Sondear la capacidad en vez de la versión* (correr `status --porcelain` y ver
  si falla por uso inválido). Se descartó: en un repo sin review, una CLI vieja
  y una nueva son indistinguibles por su salida, y FR-022 pide justamente
  distinguir "vieja" de "ausente".
- *Exigir la versión en la que se publique la extensión*. Se descartó: acopla
  las dos cadencias, que el spec asume independientes.

**Nota de dependencia**: `0.3.0` tiene que estar *publicada* para que la
extensión sea instalable por alguien que no compile la CLI. El spec ya lo
registra como bloqueante fuera de alcance.

---

## Decisión 2 — Parseo del porcelain: tokenizador propio de ~30 líneas

**Decisión**: parsear a mano — `split('\n')`, `split('\t')`, primer campo =
etiqueta, `switch` sobre la etiqueta, campos posicionales por índice. Sin
dependencias.

**Rationale**: el formato es deliberadamente trivial (líneas etiquetadas,
campos separados por tab, ningún campo puede contener un tab porque git cita
incondicionalmente los bytes de control). Las dos reglas de compatibilidad de
FR-003 caen solas: un `default:` en el `switch` ignora etiquetas desconocidas, y
leer por índice ignora campos extra al final. Meter un parser genérico (CSV/TSV)
para esto agregaría superficie de dependencia sin resolver nada.

**Sutileza que sí requiere cuidado**: el registro `state` tiene **aridad
variable** y los campos son posicionales, no nombrados:

| `mode`  | Campos                                                         |
|---------|----------------------------------------------------------------|
| `whole` | `branch source tip mode walkthrough` (6 con la etiqueta)       |
| `step`  | `… walkthrough position total recorded current` (10)           |
| `walk`  | `… walkthrough position total recorded current essential` (11) |

El parser lee `mode` **primero** y recién entonces decide cuántos campos
esperar; nunca al revés. Lo mismo con `entry`, cuyo último campo es `essential`
en walk y `banked` en step: lo interpreta el modo del `state`, que siempre llega
en la primera línea.

---

## Decisión 3 — Invocación: `execFile('git', ['review', …])`, sin shell

**Decisión**: invocar el binario `git` con `review` como primer argumento, con
`cwd` en la raíz del repositorio, `shell: false`, y un ajuste
`gitReview.path` para apuntar al dispatcher directamente cuando el
descubrimiento falle.

**Rationale**:

- Invocar `git review` (y no el dispatcher) es exactamente lo que escribe el
  usuario en la terminal: hereda el mismo mecanismo de descubrimiento de
  subcomandos de git y, por lo tanto, el mismo resultado. Cualquier
  instalación que funcione en la terminal funciona en el panel.
- `shell: false` evita entero el problema de citado de Windows: los paths con
  espacios y los caracteres que `cmd.exe` interpreta viajan como argv, no como
  una línea de comandos a re-parsear. Es la contracara de FR-012: los paths
  vuelven a la CLI **verbatim**.
- El ajuste de escape cubre las instalaciones donde `git` no descubre el
  dispatcher (PATH del editor distinto del de la shell — típico en macOS al
  lanzar VS Code desde el Dock, donde no se carga el perfil de la shell).

**Alternativas consideradas**:

- *`exec` con la línea armada como string*. Se descartó: reintroduce el citado
  y hace que un path con `"` —el mismo caso extremo que el contrato deja citado
  a propósito— pueda cambiar de significado en el camino.
- *Resolver y ejecutar el dispatcher directamente*. Se descartó como camino
  primario: obligaría a replicar la lógica de descubrimiento (npm global,
  Homebrew, `web-install`), que es precisamente lo que git ya hace.

**Riesgo registrado**: en Windows con la CLI instalada por npm, el ejecutable
que git descubre es un shim; que ese descubrimiento funcione al invocar `git`
desde el extension host (sin shell interactiva) es un supuesto a **verificar en
el primer entregable ejecutable**, no al final. Si falla, el ajuste
`gitReview.path` deja de ser escape y pasa a ser el camino documentado en
Windows.

---

## Decisión 4 — La vista es un `TreeView` nativo, no un webview

**Decisión**: un `TreeDataProvider` en un view container propio de la Activity
Bar. Nada de HTML propio.

**Rationale**: es el mismo razonamiento que la regla "espejar los idioms de
git" del proyecto. Un `TreeView` hereda gratis, y de forma correcta, todo lo que
un webview obligaría a reimplementar mal: el tema del usuario (incluidos los de
alto contraste), la navegación por teclado y sus keybindings, los lectores de
pantalla, el filtrado con `type-to-search`, los `inline actions` en hover, el
menú contextual y la integración con la paleta de comandos. Un panel de review
es una lista ordenada de ítems con un ícono y un estado — la forma canónica de
un árbol.

Consecuencias directas sobre requisitos concretos:

- FR-006 (entrada actual) y FR-007 (esenciales) se resuelven con `ThemeIcon` +
  `iconPath`/`description`, no con CSS: se ven bien en cualquier tema y no
  dependen del color como único canal.
- FR-009 (posición y total) va en `TreeView.description` — el subtítulo del
  panel, exactamente donde el usuario espera un contador.
- FR-008 (archivos sin cobertura) es un nodo colapsable hermano, no una segunda
  vista.

**Alternativa considerada**: un webview con control visual total. Se descartó:
el costo es re-implementar accesibilidad y theming, y el beneficio (layout
libre) no compra nada que esta feature necesite. Se deja anotado que un webview
sí sería el camino si en el futuro se quisiera mostrar el diff dentro del panel
— algo que el spec excluye explícitamente ("No es una interfaz de diff propia").

---

## Decisión 5 — Los estados vacíos son `viewsWelcome`, no ítems del árbol

**Decisión**: los cinco estados de la Historia 5 (sin review, sin CLI, CLI
vieja, cursor fuera de rango, error/no-repo) se muestran con contribuciones
`viewsWelcome` del manifiesto, seleccionadas por `when` sobre una context key
`gitReview.situation`.

**Rationale**: es el mecanismo que VS Code inventó para esto y el que usan sus
propias vistas ("no hay carpeta abierta → *Open Folder*"). Da lo que FR-021 y
FR-023 piden —texto explicativo *más un botón que ejecuta la acción*— sin
inventar un widget, y el usuario ya lo reconoce como "acá no hay nada, y esto es
normal", que es literalmente lo que FR-004 exige para el caso "no hay review".

El mapeo queda uno a uno:

| `situation`    | Origen                               | Botón de la bienvenida                 |
|----------------|--------------------------------------|----------------------------------------|
| `no-review`    | exit `2`                             | *Iniciar una review* (docs)            |
| `out-of-range` | exit `3`                             | *Cómo arreglarlo* (`git reset --soft`) |
| `cli-missing`  | `ENOENT` / git no encuentra el verbo | *Instalar la CLI*                      |
| `cli-outdated` | Decisión 1                           | *Actualizar la CLI*                    |
| `error`        | exit `1`                             | (sin botón: diagnóstico de stderr)     |

Nótese la asimetría deliberada, heredada del contrato: `error` es el único sin
acción ofrecida, porque el exit `1` no tiene arreglo del lado del usuario. Es la
regla de FR-024 (preservar el diagnóstico de la CLI) y de la Historia 5,
escenario 5 ("un diagnóstico que no promete una solución que no existe").

---

## Decisión 6 — El *why* se sirve por `TextDocumentContentProvider`, y en hover por
`resolveTreeItem`

**Decisión**: dos superficies para el mismo dato, ambas perezosas:

1. **Hover**: `TreeDataProvider.resolveTreeItem` devuelve un `MarkdownString`
   con el *why*. VS Code sólo lo llama cuando el usuario apunta a la entrada.
2. **Lectura completa**: un `TextDocumentContentProvider` con esquema propio
   (`git-review-why:`) que expone el texto como documento Markdown de sólo
   lectura, abierto con la vista previa nativa.

**Rationale**: preserva el formato y los saltos de línea (FR-017) sin tocarlos,
porque el payload de `status --why` es Markdown y el host ya sabe renderizarlo.
Que sea perezoso no es un detalle de performance sino una obligación del
contrato: la feature 001 separó el *why* de la secuencia (su FR-014) justamente
para que listar el recorrido no transfiera prosa, y SC-002 acota la vista
completa a 3 invocaciones. Pedir el *why* de las N entradas al construir el
árbol rompería las dos cosas.

FR-018 (distinguir "sin texto" de "falló") sale del contrato tal cual: cuerpo
vacío con exit `0` es "no tiene explicación"; exit `1` es fallo. Se muestran
distinto.

---

## Decisión 7 — Descubrimiento del repositorio y detección de cambios externos: la API de la extensión
`vscode.git`

**Decisión**: usar la extensión git incorporada
(`extensions.getExtension('vscode.git').exports.getAPI(1)`) para dos cosas —
enumerar repositorios del workspace (FR-029) y suscribirse a
`Repository.state.onDidChange` como señal de refresco (FR-019). Fallback si está
deshabilitada: `FileSystemWatcher` sobre `HEAD` y `config` del directorio git,
más `window.onDidChangeWindowState`. Y en todos los casos, refresco propio
inmediatamente después de cada invocación mutante nuestra.

**Rationale**: el estado de una review vive en `HEAD` (la rama `review/*`), en
las claves `branch.review/<x>.review*` de `config` y en refs — o sea, en
exactamente lo que esa API observa. Reusarla nos da el mismo momento de
actualización que el panel de Source Control, resuelve la ambigüedad multi-root
con el mismo criterio que el editor (el repositorio que contiene el archivo
activo) y evita mantener un watcher propio sobre el layout de `.git`, que varía
con worktrees y submódulos.

**Sobre FR-001/SC-005, que se revisan leyendo el código**: esto **no** es
derivar estado de review por fuera de la CLI. De la API de git se toman dos
cosas y sólo dos: *dónde* está el repositorio y *cuándo* algo cambió. Qué hay
adentro —si hay review, en qué modo, en qué posición, cuál es la secuencia— se
responde siempre re-invocando la CLI. La frontera es explícita para que la
revisión de SC-005 pueda verificarla: la API de git no alimenta ningún campo del
view-model.

**Alternativa considerada**: *polling* cada N segundos. Se descartó por lo
obvio (invoca la CLI sin motivo en el 99% de los ticks) y por lo menos obvio:
elegir el intervalo es elegir entre latencia visible y ruido, y el evento
existe.

---

## Decisión 8 — Paths: se guarda el crudo, se muestra el des-citado

**Decisión**: cada path se representa con **dos** valores — `raw`, el campo tal
como salió del porcelain, y `display`, el resultado de deshacer el citado estilo
C de git cuando el campo empieza con `"`. `raw` es el único que vuelve a la CLI;
`display` es el único que ve el usuario; el URI del archivo se construye desde
`display`.

**Rationale**: es la conciliación de dos requisitos que tiran para lados
opuestos. FR-012 exige mostrar paths legibles y no la cita cruda; el contrato de
001 (FR-015) exige que los paths que se le pasan de vuelta a la CLI sean
idénticos byte a byte, y el código lo confirma —`status --why` matchea con
`grep -Fxq` contra la secuencia derivada de `changed_paths`
(`bin/git-review-verbs/status:93`). Un solo valor obligaría a elegir entre
mostrar basura o romper el round-trip.

**Alcance real del des-citado**: con `core.quotePath=false`, git deja literales
los bytes no ASCII; sólo cita cuando el path contiene `"` o `\` (ambos ilegales
en Windows, y el contrato lo documenta como caso extremo). Aun así el decodificador
se implementa completo —`\\`, `\"`, los escapes de control y los octales
`\nnn` reensamblados como bytes y decodificados como UTF-8— porque es una
función pura de veinte líneas, se testea sola en unitarios, y la alternativa es
una rama de código que sólo se ejerce en producción.

**No se hace lo simétrico**: la extensión **no** re-implementa el *citado* de
git. Nada de lo que produce se compara contra salida de git; sólo se devuelve lo
que se recibió.

---

## Decisión 9 — Concurrencia: mutex para lo que muta, coalescencia para lo que lee

**Decisión**: dos políticas distintas según el tipo de invocación.

- **Mutantes** (`next`, `prev`): cola serializada de profundidad 1 y context key
  `gitReview.busy` que deshabilita los comandos mientras corre. Un segundo
  avance disparado antes de que termine el primero no se encola: se descarta.
- **Lecturas** (`status --porcelain`): si llega un pedido de refresco mientras
  hay uno en vuelo, se marca *sucio* y se re-corre **una** vez al terminar.

**Rationale**: FR-020 pide que no se solapen las que cambian estado, y el edge
case del spec ("el revisor avanza dos veces seguidas") describe justo eso.
Descartar en vez de encolar es lo correcto acá porque el segundo avance se
decidió mirando una posición que ya no es la vigente — encolarlo ejecutaría una
intención basada en información caduca. Del lado de las lecturas el problema es
el opuesto: los eventos del watcher llegan en ráfaga (un `git config` toca el
archivo varias veces) y encolarlas todas sería una estampida de invocaciones
para converger al mismo resultado; coalescer da el mismo estado final con una
sola.

Todas las invocaciones llevan `timeout` y `AbortSignal`, y la vista muestra que
está trabajando (`TreeView.message`) en lugar de quedarse en blanco — es el edge
case de la CLI lenta y FR-030.

---

## Decisión 10 — Abrir la entrada: documento del working tree, diff delegado al host

**Decisión**: el clic abre el **archivo del working tree**. Ver los cambios como
diff es una acción aparte que delega en el comando incorporado
`git.openChange`. Para una entrada cuyo archivo no existe en el working tree
(archivo eliminado en el rango), se abre directamente el diff.

**Rationale**: FR-013 pide que los cambios estén "visibles y editables", y en
una review de `git review` el working tree **ya es** el PR aplicado: abrir el
archivo tal cual cumple las dos mitades, y es lo único que las mantiene juntas
—un editor de diff contra el índice no es editable del mismo modo—. El diff como
acción secundaria delega en el host en vez de construir URIs `git:` a mano, que
sería acoplarse a los internos de otra extensión. El caso del archivo eliminado
(Historia 2, escenario 3) es la única excepción, y ahí el diff no es una
comodidad sino la única superficie que tiene contenido para mostrar.

---

## Decisión 11 — Tests: unitarios puros en los tres SO, integración con VS Code real

**Decisión**: dos suites.

- **Unitarios** (`mocha` + `node:assert`), sin host de VS Code, sobre las
  funciones puras: parser porcelain (incluida la aridad variable y el descarte
  de etiquetas/campos desconocidos, que es la prueba de FR-003/SC-006),
  des-citado de paths, comparación de versiones, mapeo de exit code a situación.
- **Integración** (`@vscode/test-electron`), levantando un VS Code real sobre
  repos fixture construidos con la CLI del propio repositorio.

**Rationale**: la lógica que puede romperse en silencio es toda pura y no
necesita un editor para probarse — que es lo que la hace barata de correr en la
matriz de tres SO que SC-007 exige. La integración cubre lo que los unitarios no
pueden afirmar (que el árbol lista lo que debe, que el comando mueve el cursor
de verdad) y por eso construye sus fixtures **con la CLI real**: un fixture de
salida porcelain escrita a mano probaría el parser contra sí mismo.

El proyecto ya tiene la matriz ubuntu/macOS/windows en `.github/workflows/ci.yml`
para shellcheck y bats; se agrega un job análogo. En Ubuntu la integración
necesita `xvfb-run`, que es la práctica estándar para VS Code headless.

**Deuda anotada**: los fixtures necesitan la CLI en el `PATH` del job. Se resuelve
apuntando `gitReview.path` (Decisión 3) al `bin/git-review` del propio
checkout, que además ejercita ese ajuste en CI en vez de dejarlo sin cobertura.

---

## Decisión 12 — Motor mínimo de VS Code: `^1.75.0`

**Decisión**: `engines.vscode: ^1.75.0` (enero 2023).

**Rationale**: es el piso que hace estables a todas las APIs que las decisiones
anteriores necesitan —`resolveTreeItem` (1.68), `viewsWelcome` con `when`
(1.44+), `TreeView.message`/`description` (1.42+), la API v1 de `vscode.git`—
con margen de varias versiones sobre la más nueva de ellas. Bajar de ahí
obligaría a rutas alternativas para el hover perezoso (Decisión 6); subir no
compra ninguna API que se use, y sólo dejaría afuera instalaciones ancladas.

---

## Decisión 13 — Ubicación y aislamiento: `vscode-extension/`, fuera del tarball

**Decisión**: subdirectorio `vscode-extension/` con su propio `package.json`,
`tsconfig.json` y cadena de build. No se toca la raíz salvo por el job de CI.

**Rationale**: el spec ya fija el *por qué* (versionar el contrato junto a su
consumidor, como los dos README). Lo que la investigación agrega es que el
aislamiento **ya está garantizado sin hacer nada**: el `package.json` de la raíz
declara `files` como allowlist (`bin/`, `completions/`, `VERSION`, `LICENSE`,
`README.md`), así que cualquier directorio nuevo queda fuera del tarball de npm
por omisión — el mismo mecanismo por el que `docs/` no viaja. No hace falta
agregar exclusiones ni tocar la publicación de la CLI.
