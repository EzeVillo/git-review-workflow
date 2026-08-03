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

## Decisión 4 — La vista es un `WebviewView`, con la secuencia en un `QuickPick`

**Decisión**: un `WebviewViewProvider` en un view container propio de la Activity
Bar, que muestra **una entrada por vez** —la actual— con su *why* como cuerpo. La
secuencia completa y los archivos sin cobertura no se dibujan en el panel: se
alcanzan por `QuickPick`, la superficie nativa del editor para elegir de una
lista.

**Rationale**: la forma canónica de un árbol es una lista de ítems donde el ítem
*es* la información. Acá no lo es: el ítem es un path, y lo que el walkthrough
aporta —el *why*— no entra en un `TreeItem`. Un árbol lo empuja a un hover o a un
documento aparte, y deja el panel gastando su ancho en repetir paths que el
revisor ya puede ver en el explorador. Dedicar el panel a la entrada actual
invierte esa proporción: el contenido del autor pasa a ser el cuerpo (FR-017), y
la lista —que se consulta de a ratos, no continuamente— pasa a un `QuickPick`,
que además da búsqueda incremental sobre cientos de entradas (el edge case de la
review grande) sin ocupar nada mientras no se usa.

Consecuencias directas sobre requisitos concretos:

- FR-005 (entrada actual como contenido principal) y FR-017 (*why* sin pedirlo)
  sólo son satisfacibles con layout propio: son la razón del cambio.
- FR-005a/FR-008 (secuencia y sin cobertura accesibles pero no permanentes) son
  dos `QuickPick`, uno por colección — separados, que es lo que FR-008 pide.
- FR-009 (posición y total) va en la barra superior del propio panel.

**Esta decisión revierte la original**, que era un `TreeDataProvider` sin HTML
propio, y se registra el motivo porque el costo que aquella evitaba es real y
ahora hay que pagarlo a mano: un webview no hereda el tema, la navegación por
teclado ni el foco. Se paga así, y por eso el spec suma FR-031/SC-010 en vez de
dejarlo implícito:

- **Tema**: nada de colores literales. Todo sale de las variables CSS que el host
  inyecta (`--vscode-foreground`, `--vscode-panel-border`,
  `--vscode-descriptionForeground`, `--vscode-textLink-foreground`,
  `--vscode-button-*`, `--vscode-editor-font-family`), que ya contemplan los
  temas de alto contraste. Un color hardcodeado es un bug de tema.
- **Teclado y foco**: los controles son `<button>` reales en orden de tab, no
  `<div>` con `onclick`; los marcadores (`key`, ediciones guardadas) van con
  texto además de color (FR-007).
- **Seguridad**: `Content-Security-Policy` restrictiva con `nonce` para el único
  script inline, sin origen remoto de ningún tipo. Todo el contenido variable
  —paths, *why*, `stderr`— se inserta con `textContent`, nunca con `innerHTML`.

**Alternativa considerada**: mantener el árbol y sumarle un webview aparte. Se
descartó: son dos superficies que muestran lo mismo y hay que mantener
sincronizadas, y el árbol seguiría ocupando el ancho que el rediseño quiere
liberar.

**Anotado para más adelante**: el mismo view-model puede montarse en un
`WebviewPanel` del área del editor, donde hay ancho para el *why* largo. No entra
acá; lo que esta decisión garantiza es que el modelo (`panelModel.ts`) no sepa
nada del host que lo dibuja, así que agregarlo después no reabre el diseño.

---

## Decisión 5 — Los estados vacíos los dibuja el propio panel, con la forma de un `viewsWelcome`

**Decisión**: los cinco estados de la Historia 5 (sin review, sin CLI, CLI
vieja, cursor fuera de rango, error/no-repo) se renderizan dentro del webview,
manteniendo exactamente la forma que tenían como `viewsWelcome`: un párrafo
explicativo y, salvo `error`, un botón que ejecuta la acción.

**Rationale**: no es una preferencia, es una restricción del host —
**`viewsWelcome` sólo se renderiza en vistas de tipo `tree`**. Al cambiar la
vista a `webview` (Decisión 4) esas contribuciones dejarían de mostrarse: no
fallan ruidosamente, simplemente no aparecen, y el revisor sin CLI se queda
mirando un panel vacío. Por eso se sacan del manifiesto en lugar de dejarlas
como código muerto que aparenta cubrir el caso.

Lo que se conserva es lo que importaba de la decisión original: que el mapeo
`situation` → texto + acción sea uno a uno, que "no hay review" se vea como
estado normal y no como falla (FR-004), y que el botón sea el mismo comando que
ejecutaba la bienvenida (`gitReview.installCli`,
`gitReview.showOutOfRangeHelp`). Lo que se pierde es la familiaridad del widget
nativo; se compensa reproduciendo su forma —texto centrado, botón de ancho
completo con `--vscode-button-*`— en vez de inventar una propia.

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

## Decisión 6 — El *why* se muestra en el panel, y se lee completo por `TextDocumentContentProvider`

**Decisión**: dos superficies para el mismo dato, las dos alimentadas por una
invocación de a una entrada por vez:

1. **En el panel**: el *why* de la **entrada actual** es el cuerpo de la vista
   (FR-017). Se pide una sola vez por refresco, para una sola entrada, y se
   muestra como texto con `white-space: pre-wrap` — no se pasa por un renderer
   de Markdown, porque meter un parser en el webview sería superficie nueva para
   un panel angosto donde el texto plano ya preserva lo que FR-017 exige (los
   saltos de línea y el formato del autor, tal cual los escribió).
2. **Lectura completa**: un `TextDocumentContentProvider` con esquema propio
   (`git-review-why:`) que expone el texto como documento Markdown de sólo
   lectura, abierto con la vista previa nativa (FR-017a). Es la superficie donde
   el Markdown sí se renderiza, y la que sirve cuando el *why* no entra en el
   panel.

**Rationale**: que sea de a una no es un detalle de performance sino una
obligación del contrato: la feature 001 separó el *why* de la secuencia (su
FR-014) justamente para que listar el recorrido no transfiera prosa, y su SC-002
acota la vista completa a 3 invocaciones. Mostrar el *why* de la actual cuesta
**una** invocación por refresco, independiente del largo de la secuencia — que
es exactamente lo que mide SC-009, y lo que FR-018a prohíbe convertir en N.

**Reemplaza al hover** de `resolveTreeItem` de la decisión original, que
desaparece con el árbol. No es una pérdida: el hover mostraba bajo demanda lo
que ahora está a la vista sin pedirlo.

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
  des-citado de paths, comparación de versiones, mapeo de exit code a situación,
  y la derivación del view-model del panel (`panelModel.ts`).
- **Integración** (`@vscode/test-electron`), levantando un VS Code real sobre
  repos fixture construidos con la CLI del propio repositorio.

**Rationale**: la lógica que puede romperse en silencio es toda pura y no
necesita un editor para probarse — que es lo que la hace barata de correr en la
matriz de tres SO que SC-007 exige. La integración cubre lo que los unitarios no
pueden afirmar (que el panel muestra lo que debe, que el comando mueve el cursor
de verdad) y por eso construye sus fixtures **con la CLI real**: un fixture de
salida porcelain escrita a mano probaría el parser contra sí mismo.

**Dónde se corta la integración**: en el view-model, no en el DOM del webview.
Un webview corre en su propio contexto y no hay API pública para inspeccionarlo
desde el host, así que la integración afirma sobre el `PanelModel` que se le
postea (expuesto por la API de test) y sobre los efectos reales en git. Esto es
lo mismo que ya pasaba con el `TreeView` —tampoco tenía API de lectura—, por eso
la API de test existía desde antes.

Lo que queda del otro lado de ese corte —el HTML— no se deja sin red por eso.
Vive en `panelHtml.ts`, una función pura sin `vscode`, y eso habilita dos cosas
baratas: unitarios sobre sus propiedades **estructurales** (la CSP con su
`nonce`, cero colores literales, cero `innerHTML`, controles que son `<button>`)
y montarlo en un navegador con un `PanelModel` de ejemplo para mirar el layout.
Cómo se ve exactamente sigue siendo validación a ojo (`quickstart.md` §8); lo
que puede romperse en silencio —un color hardcodeado que desaparece en alto
contraste, un script que la CSP bloquea— no.

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
anteriores necesitan —`WebviewViewProvider` y `Webview.cspSource` (1.50),
`QuickPick` (estable desde siempre), `TabInputWebview` para los tests (1.67), la
API v1 de `vscode.git`— con margen de varias versiones sobre la más nueva de
ellas. Subir no compra ninguna API que se use, y sólo dejaría afuera
instalaciones ancladas.

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
