# Feature Specification: Plugin de IntelliJ IDEA con paridad de la extensión VS Code

**Feature Branch**: `009-plugin-intellij`

**Created**: 2026-08-08

**Status**: Draft

**Input**: User description: "Plugin de IntelliJ IDEA en este mismo repo
(`jetbrains-plugin/`), paridad total con la extensión de VS Code, panel nativo
del IDE (no webview), solo IntelliJ IDEA en la última línea de versiones
soportada, multiplataforma Windows/macOS/Linux. La spec se deriva del código
real de la extensión y de la CLI, no de specs de features previas que pueden
haber quedado desactualizadas. Mejor solución técnica y mantenible; detenerse
solo ante decisiones críticas de producto. Spec kit completo en esta sesión."

## Contexto y Motivación *(el porqué)*

### El problema

El revisor que trabaja en **IntelliJ IDEA** hoy tiene la CLI de
`git-review-workflow` y el working tree editable, pero **no** el panel de
walkthrough ni el ciclo de review (start / continue / finish / save / abort /
housekeeping) embebido en el IDE. Eso ya existe en VS Code como extensión
consumidora de la misma CLI. Quien elige IntelliJ vuelve a sostener dos
contextos: terminal + editor.

### Por qué importa ahora

- La CLI ya expone contratos machine-readable (`status` / `list` / `config`
  porcelain, `--why`, `--version`) y es la única fuente de verdad del estado
  de la review.
- La extensión de VS Code demuestra que un **segundo cliente** del mismo
  contrato es viable sin reimplementar el modelo de estado en el editor.
- Hay un riesgo de **drift de producto** si el segundo cliente se define a
  ojo o se copia de documentos de feature enmendados entre sí: la superficie
  real vive en el código de la extensión y en la CLI. Esta feature fija
  paridad contra ese estado acumulado, no contra la última feature de
  `specs/00x`.

### Qué habilita

Que un revisor en IntelliJ IDEA pueda hacer, desde un tool window nativo y
acciones del IDE, **todo lo que hoy hace la extensión de VS Code**: ver el
estado de la review, leer el walkthrough (entrada, posición, *why*, keys),
abrir archivos y diffs, navegar, iniciar / continuar / guardar / abortar /
terminar reviews, housekeeping, compare de solo lectura, preview de edits,
walkthrough init/build, y diagnóstico cuando falta o está vieja la CLI.

### Qué NO es esto

- **No reimplementa la CLI ni el modelo de estado en el plugin.** El plugin
  invoca verbos y relee el estado porcelain; no lee `git config` de review
  por su cuenta, no mueve refs y no toca el working tree salvo lo que la CLI
  hace al ser invocada.
- **No es un port línea a línea del markup HTML/CSS de VS Code.** El panel
  es nativo del IDE; la **lógica de qué se muestra** (proyección del estado
  a un modelo de panel) es la misma; la **pintura** es de la plataforma.
- **No soporta multi-root ambigüo.** Como la extensión y como el `cwd` de la
  CLI: exactamente un repositorio usable; cero o dos o más es “no hay
  target”, no un picker silencioso del primero.
- **No inventa superficie de producto que la extensión no tenga.** Paridad
  significa la superficie **observada en el código de la extensión hoy**
  (comandos, situaciones, flujos, strings de producto relevantes), no una
  lista idealizada de features.
- **No incluye WebStorm / PyCharm / GoLand en la matriz de soporte del
  primer release** (aunque la API de Git del ecosistema JetBrains exista en
  ellos). Solo IntelliJ IDEA.
- **No incluye publicar al Marketplace como bloqueante de la spec de
  comportamiento**; el empaquetado y la publicación son requisitos de
  entrega del plan, no del valor de review.

## Superficie consolidada (estado del producto a parificar)

Fuente: código de `vscode-extension/` y de `bin/` al 2026-08-08 — **no**
`specs/002`…`008` como norma. Los contratos machine-readable de porcelain
siguen siendo los de la CLI; el plugin es un segundo consumidor.

### Situaciones del panel

| Situación | Cuándo (regla de producto) | Qué ve el revisor |
|-----------|----------------------------|-------------------|
| `cli-missing` | No se puede ejecutar o no responde la CLI con versión | Mensaje de instalación, comando npm, enlaces de ayuda; reintento periódico si el panel está visible |
| `cli-outdated` | Versión de CLI inferior a la mínima requerida por el cliente | Mensaje de actualización (mínimo **0.4.0** hoy), comando npm update |
| `no-review` | No hay review activa; inventario opcional | Setup si falta base; si hay base: inventario + Start + acciones auxiliares |
| `finish-pending` | Cierre completo con undo vivo | Banner post-cierre: limpiar conservando fixes / deshacer finish |
| `review` | Review activa legible | Barra de estado, entrada/lista según modo, navegación si aplica, acciones de ciclo |
| `finish-conflict` | Review legible con cierre a medio aplicar | Igual que review legible + banner de conflicto; **sin** next/prev |
| `out-of-range` | Cursor walk fuera del rango vivo | Diagnóstico + stderr de la CLI + cómo corregir |
| `error` | Fallo de lectura, timeout, sin cwd único, etc. | Diagnóstico + stderr o mensaje fijo accionable |

### Modos de review (cuando hay review legible)

| Modo | Lectura principal | Navegación | Diff / abrir |
|------|-------------------|------------|--------------|
| `walk` | Entrada actual + *why* asíncrono + secuencia; badge key; uncovered | next/prev solo en `review` (no en finish-conflict) | Archivo WT o blob si eliminado; diff HEAD↔WT; go-to sin mover cursor CLI |
| `step` | Entrada actual (SHA, subject/author si la CLI los da), banked | next/prev en `review` | Multi-diff del commit |
| `whole` | Lista de archivos del rango; marca “último abierto” local al IDE | Sin cursor CLI | Archivo, diff, open-all del rango |

Notas de producto que el panel debe reflejar cuando la CLI las reporta:
compare **solo lectura** (finish no aplica), walk **solo-keys**, base
movida (`total < recorded` en step/walk), walkthrough **degradado**, base
del rango en whole, fuente y tip de la review.

### Acciones (paridad con la extensión)

Agrupadas por valor; los nombres de acción del IDE pueden localizarse, el
**comportamiento y los verbos CLI** no.

| Grupo | Acciones | Notas de producto |
|-------|----------|-------------------|
| Lectura | Abrir entrada, abrir cambios, abrir todos (solo whole), mostrar why, ir a entrada, refrescar | Why solo con path de walk; next/prev reabren cambios de la nueva entrada |
| Navegación CLI | Siguiente / anterior entrada | Solo situación `review` y no busy |
| Ciclo | Start (asistente), Continue (desde inventario), Save, Abort, Finish, Undo finish, Resume finish | Confirmaciones asimétricas: Abort/Continue fuertes; Finish elige destino sin modal destructivo genérico; Undo puede pedir force solo si la CLI lo indica |
| Setup | Set base, set remote, instalar/actualizar CLI (docs + copiar npm) | Base obligatoria antes de Start útil. Como en la extensión, base/remote se **dibujan** en el panel solo sin review (setup o Settings del pie) pero existen como **acción** en las demás situaciones, degradando con mensaje cuando no hay candidatas |
| Auxiliares | Clean, Forget (saved / delta / stale), Preview edits (+ stat), Compare, Walkthrough init/build, Show CLI log | Housekeeping con confirmaciones y argumentos exactos de la CLI |
| Inventario | Continue / Discard sobre filas | Continue y discard de inventario no se exponen como acciones “globales” engañosas cuando el contexto es solo una fila |

### Asistente de start (paridad)

1. Requiere situación `no-review` o `finish-pending`.
2. Lee config efectiva; si no hay base, obliga a configurar base.
3. Elige rama (candidatas de la CLI).
4. Elige origen: remote / local / offline (preselección configurable; el
   usuario confirma; el plugin no inventa argv).
5. Si hay marcador delta para ese origen, ofrece rango full vs incremental.
6. Ofrece **solo** formas de lectura que la CLI reporta como viables (walk /
   keys / step / whole); walk recomendado cuando aplica; **sin** opción
   “automática” opaca. Fallback step+whole si el informe no trae ofertas.
7. Confirma con resumen y ejecuta `start`; fallos de red ofrecen repetir en
   terminal con la misma invocación resuelta.

### Asistente de compare (paridad)

Compare crea una review de solo lectura entre dos revisiones; finish no
aplica. Confirmación explícita; layouts sin depender de “ofertas de tip”
como start.

### Invariantes de producto (no negociables)

1. **La CLI es la única fuente de verdad del estado de review.** Tras cada
   mutación se relee el estado; no se parsea la prosa de verbos mutativos
   para decidir UI (p. ej. resultado de finish se infiere del inventario /
   porcelain tras refresh).
2. **Un solo repositorio por ventana de producto.** Cero o varios roots
   git → estado de error o vacío accionable, no adivinanza.
3. **Riesgo asimétrico.** Operaciones que descartan trabajo o mueven HEAD
   piden confirmación; las de solo lectura no. Confirmaciones fuera del
   “ocupado” del panel para no bloquear la UI en un modal eterno.
4. **Una mutación a la vez.** Segunda mutación se descarta con aviso, no se
   encola.
5. **Tokens de frescura.** Si el estado cambió entre confirmar y ejecutar,
   no se lanza la mutación sobre datos viejos.
6. **Paths:** lo que se muestra se desescapa para humanos; lo que vuelve a
   la CLI (`--why`) es el path **crudo** del porcelain. Paths con espacios,
   no-ASCII y comillas se comportan igual que en la extensión.
7. **Codificación de procesos:** la captura de stdout/stderr de git y de la
   CLI es UTF-8 explícito en los tres SO; no se confía el charset de
   plataforma (Windows).
8. **Red:** start (y forget de deltas stale) no se cuelgan pidiendo
   credenciales interactivas; fallan con diagnóstico y salida a terminal
   cuando corresponde.
9. **Diffs post-start:** no se confía en un caché SCM del IDE que puede
   ir atrasado tras un start masivo; el inventario de cambios del rango se
   lee de git de forma directa.
10. **Textos de producto duplicados entre clientes** (versión mínima,
    comandos npm, mensajes de empty states críticos, hints de instalación)
    se tratan como **contrato multi-cliente**: un cambio de producto toca
    la fuente canónica compartida o ambos clientes en el mismo cambio —
    no “actualizar después el otro panel”.

## User Scenarios & Testing *(mandatory)*

El actor es el **revisor** en IntelliJ IDEA. Se asume git y (cuando el
flujo lo requiere) la CLI instalada o instalable.

### User Story 1 - Ver el estado de la review en un panel nativo (Priority: P1)

El revisor abre un proyecto con una review activa. Abre el tool window de
git review y ve, sin terminal, el modo, la posición (si hay cursor), la
entrada actual, marcas (key, banked, degradado, solo lectura, solo-keys) y
puede refrescar cuando el working tree o la review cambian.

**Why this priority**: es el valor fundacional; sin lectura de estado no hay
producto.

**Independent Test**: repo sandbox con review walk/step/whole; abrir el
panel y contrastar cada campo con `git review status --porcelain` en
terminal.

**Acceptance Scenarios**:

1. **Given** review walk con cursor en la entrada 2 de 7 y la 3 marcada
   key, **When** abre el panel, **Then** ve entrada 2, posición 2/7 y puede
   listar las 7 con la 3 distinguida.
2. **Given** whole sin walkthrough, **When** abre el panel, **Then** ve
   inventario de archivos del rango sin presentarlo como error.
3. **Given** walkthrough degradado a whole, **When** mira el panel,
   **Then** ve la nota de degradación y la review sigue usable.
4. **Given** compare de solo lectura, **When** mira el panel, **Then**
   finish no se ofrece como acción disponible.
5. **Given** finish en conflicto, **When** mira el panel, **Then** la
   review sigue legible, ve acciones de undo/resume y **no** next/prev.

---

### User Story 2 - Abrir archivo, diff y why (Priority: P1)

Desde el panel o acciones, el revisor abre el archivo de la entrada, el
diff de cambios de la review, todos los cambios en whole, y el *why* en
walk.

**Why this priority**: sin esto el panel es un cartel; con la Historia 1
forma el mínimo instalable.

**Independent Test**: para cada modo, abrir entry/change/all/why y
verificar path y contenido correctos, incluidos paths con espacio y
acento.

**Acceptance Scenarios**:

1. **Given** entrada walk con path con espacios y no-ASCII, **When**
   abre entry y change, **Then** se abre el path correcto y el diff
   corresponde al rango de la review.
2. **Given** archivo eliminado en el rango, **When** abre entry,
   **Then** ve el contenido pre-borrado sin error fatal.
3. **Given** whole con N archivos, **When** open all changes, **Then**
   obtiene la vista multi-archivo del rango (o el equivalente nativo del
   IDE).
4. **Given** walk con why escrito, **When** muestra why, **Then** el
   texto coincide con `status --why` para el path crudo de la entrada.
5. **Given** un start que acaba de stagear el PR entero, **When** abre
   change de un archivo del rango en los segundos siguientes, **Then** el
   diff se abre con datos al día (no “no hace nada” por caché SCM viejo).

---

### User Story 3 - Navegar el walkthrough / step (Priority: P1)

El revisor avanza y retrocede con next/prev; el panel y el diff siguen al
cursor. Puede saltar a una entrada de la lista sin mover el cursor de la
CLI (go-to / pick).

**Why this priority**: es el flujo diario de lectura guiada.

**Independent Test**: review walk y step; next/prev hasta extremos;
go-to a una entrada media.

**Acceptance Scenarios**:

1. **Given** review en posición intermedia, **When** next, **Then** la
   CLI mueve el cursor, el panel muestra la nueva entrada y se abren sus
   cambios.
2. **Given** en la primera o última, **When** prev o next respectivamente,
   **Then** no se inventa movimiento; se informa el extremo.
3. **Given** finish-conflict, **When** intenta next/prev, **Then** no
   están disponibles.
4. **Given** lista de entradas, **When** elige otra con go-to, **Then**
   se abre esa entrada **sin** cambiar el cursor CLI.

---

### User Story 4 - Arrancar y continuar reviews (Priority: P1)

Sin review activa (o con finish-pending), el revisor configura base si
falta, inicia una review con el asistente completo, o continúa una
guardada desde el inventario.

**Why this priority**: sin entrada al ciclo no hay adopción del panel como
reemplazo de la terminal.

**Independent Test**: sandbox sin review; set base; start walk/step/whole;
save; continue.

**Acceptance Scenarios**:

1. **Given** repo sin `reviewworkflow.base`, **When** ve el empty state,
   **Then** solo setup de base/remote, sin Start engañoso.
2. **Given** base configurada y rama con walkthrough y keys, **When**
   completa el asistente, **Then** ve ofertas honestas (sin automático) y
   tras confirmar queda en review con el layout elegido.
3. **Given** fallo de red en start, **When** la CLI/git reportan error de
   red/credenciales, **Then** se ofrece repetir en terminal con la
   invocación exacta; no queda colgado pidiendo password.
4. **Given** review guardada resumible en inventario, **When** Continue
   con confirmación, **Then** retoma esa review.
5. **Given** fila no resumible (huérfana o conflicto con activa), **When**
   mira el inventario, **Then** Continue no se ofrece como viable.

---

### User Story 5 - Finish, undo, abort, save (Priority: P1)

El revisor completa el ciclo de riesgo: guardar para después, abortar,
finish a rama de fixes o onto-source, deshacer finish, reanudar conflicto.

**Why this priority**: paridad del ciclo que ya es producto en VS Code.

**Independent Test**: review con y sin edits; finish; undo; abort; save.

**Acceptance Scenarios**:

1. **Given** review con edits, **When** finish a rama separada, **Then**
   tras refresh ve finish-pending o el toast de listo según estado real
   post-CLI, no según parseo de prosa.
2. **Given** finish-pending, **When** Undo finish, **Then** con
   confirmación revierte; si la CLI exige force, un segundo paso lo pide
   explícitamente (nunca force por defecto).
3. **Given** finish-conflict, **When** Resume finish, **Then** usa el
   flag onto **solo** si el porcelain de la review lo reporta.
4. **Given** review activa, **When** Abort con confirmación destructiva,
   **Then** desaparece la review activa.
5. **Given** review activa, **When** Save, **Then** queda en inventario
   como guardada.

---

### User Story 6 - Housekeeping, compare, preview, walkthrough autor (Priority: P2)

Clean, forget, compare, preview edits, walkthrough init/build y log de
CLI completan la paridad de la paleta/comandos de la extensión.

**Why this priority**: menos frecuente que el ciclo diario, pero está en
la superficie del producto VS Code.

**Independent Test**: cada acción contra CLI en sandbox; verificar
confirmaciones y argv efectivos vía log.

**Acceptance Scenarios**:

1. **Given** reviews viejas, **When** clean one/all/keep-fixes, **Then**
   el efecto coincide con la CLI y pide confirmación acorde.
2. **Given** marcadores delta, **When** forget delta (incl. stale),
   **Then** stale usa la política de red (no colgarse en prompt).
3. **Given** dos revisiones, **When** compare, **Then** obtiene review
   readonly navegable según layout.
4. **Given** edits en review, **When** preview / preview --stat, **Then**
   ve el diff o stat en un editor del IDE.
5. **Given** rama de autor, **When** walkthrough init/build, **Then**
   crea o regenera el sidecar con las mismas confirmaciones que la
   extensión (overwrite si existe).

---

### User Story 7 - CLI ausente, vieja, multi-root, busy (Priority: P1)

El revisor no se queda sin diagnóstico: CLI missing/outdated, workspace
sin un solo root git, operación en curso, y ajuste del path del
dispatcher.

**Why this priority**: es la primera impresión en máquinas sin setup.

**Independent Test**: desinstalar CLI; version vieja simulada; proyecto
multi-módulo con dos repos; mutación larga + segunda acción.

**Acceptance Scenarios**:

1. **Given** CLI ausente, **When** abre el panel, **Then** ve install +
   copiar comando npm y reintenta solo si el panel está a la vista.
2. **Given** CLI &lt; 0.4.0, **When** refresca, **Then** ve outdated y
   update npm.
3. **Given** dos roots git en el proyecto, **When** el plugin resuelve
   target, **Then** no elige el primero en silencio; muestra el error de
   un solo cwd.
4. **Given** finish en curso, **When** lanza abort, **Then** se descarta
   con “another operation in progress” (o equivalente).
5. **Given** path custom al dispatcher, **When** cambia el setting,
   **Then** el próximo refresh re-chequea versión y usa esa invocación.

---

### User Story 8 - Multiplataforma y theming nativo (Priority: P1)

El mismo plugin se comporta de forma correcta en Windows, macOS y Linux:
invocación del dispatcher (incluido script sin extensión en Windows),
UTF-8 en paths, tool window con look-and-feel e HiDPI del IDE.

**Why this priority**: el proyecto ya paga el costo de tres SO en CI de la
CLI; el plugin no puede ser “solo macOS/Linux”.

**Independent Test**: matriz smoke en los tres SO (al menos: version
probe, status porcelain con path acentuado, open entry, start offline o
local).

**Acceptance Scenarios**:

1. **Given** Windows con dispatcher POSIX sin `.exe/.cmd/.bat`, **When**
   invoca la CLI, **Then** usa el mismo workaround de shell que la
   extensión (`sh` + path), no falla con ENOENT opaco.
2. **Given** path con acento en el rango, **When** lista y abre en
   Windows, **Then** el path no se corrompe por charset de consola.
3. **Given** tema claro/oscuro/alto contraste del IDE, **When** mira el
   panel, **Then** hereda colores del LAF; ninguna distinción solo por
   color.
4. **Given** macOS y Linux, **When** timeout de una lectura colgada,
   **Then** el host deja de esperar dentro del presupuesto de la clase de
   invocación.

---

### Edge Cases

- Status timeout: situación de error con mensaje que apunta a log / terminal / CLI lenta, no a “CLI missing”.
- List o config fallan en empty state: no convierten la situación en error global; degradan inventario/config.
- Entrada sin cambios restantes al abrir diff: mensaje informativo, no crash.
- Git del IDE no listo / deshabilitado: mensaje accionable al abrir diffs que lo necesitan; el estado porcelain sigue funcionando si la CLI corre.
- Confirmación y estado que cambió debajo: la mutación no corre; se informa staleness.
- Force undo solo tras stderr de la CLI que lo indica.
- last-opened en whole: persiste por rama de review en estado del IDE; se descarta si el archivo ya no está en el rango; no afecta a la CLI.
- Probe de CLI cada ~10 s solo en missing/outdated y con panel visible.
- Activación perezosa: abrir un proyecto no debe costar un proceso de CLI hasta que el tool window o una acción lo requiera.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El plugin MUST obtener todo el estado de review únicamente
  invocando la CLI (`--version`, `status --porcelain`, y cuando
  corresponda `list --porcelain`, `config --porcelain`, `status --why`);
  MUST NOT derivar situación de lectura de refs o config git propias.
- **FR-002**: El plugin MUST implementar las ocho situaciones de la
  superficie consolidada con las mismas reglas de prioridad (finish-conflict
  sobre review; finish-pending sobre no-review; missing/outdated antes de
  porcelain de estado).
- **FR-003**: El plugin MUST rechazar workspaces sin exactamente un
  repositorio git usable como target (0 o ≥2 → no hay cwd de producto).
- **FR-004**: El plugin MUST exponer un tool window nativo del IDE cuya
  información visible sea la proyección del modelo de panel (misma
  semántica que el panel de VS Code: barra, entrada/lista, why, uncovered,
  banners de finish, empty/setup, errores).
- **FR-005**: El plugin MUST ofrecer paridad de acciones de la superficie
  consolidada (lectura, navegación, ciclo, setup, auxiliares, inventario).
- **FR-006**: El plugin MUST aplicar confirmaciones con la misma asimetría
  de riesgo que la extensión (destructivas / HEAD-moving vs lectura).
- **FR-007**: El plugin MUST serializar mutaciones (una en vuelo; la
  segunda se descarta con aviso) y MUST revalidar frescura del estado antes
  de mutar tras un diálogo.
- **FR-008**: El plugin MUST invocar verbos mutativos con los mismos
  argumentos efectivos que la extensión (tabla de la superficie / contratos
  de plan), incluido el orden de flags de start y el `--` antes de nombres
  de rama.
- **FR-009**: El plugin MUST usar timeouts por clase de invocación
  equivalentes: lectura 15 s, mutación local 120 s, mutación de red 300 s
  (start; forget con stale).
- **FR-010**: El plugin MUST impedir prompts interactivos de credenciales
  en invocaciones de red (fallar rápido) y MUST clasificar fallos de red de
  start para ofrecer “run in terminal”.
- **FR-011**: El plugin MUST resolver el ejecutable de la CLI como la
  extensión: vacío = `git review …`; path directo al dispatcher; en
  Windows, script sin extensión nativa vía `sh`.
- **FR-012**: El plugin MUST capturar stdout/stderr de CLI y de git de
  apoyo en UTF-8 explícito en Windows, macOS y Linux.
- **FR-013**: El plugin MUST preservar PathRef: display para UI y filesystem;
  raw para devolver a la CLI.
- **FR-014**: El plugin MUST abrir archivos y diffs del rango sin depender
  de un índice SCM potencialmente stale tras start; MUST manejar
  altas/bajas/modificaciones y el fallback de archivo eliminado.
- **FR-015**: El plugin MUST tratar la versión mínima de CLI como dato de
  producto versionado con el cliente (hoy **0.4.0**); missing vs outdated
  distinguibles.
- **FR-016**: El plugin MUST reutilizar la lógica de proyección del panel
  (qué se dibuja) de forma testeable sin arrancar el IDE; la capa de
  pintura nativa solo renderiza ese modelo.
- **FR-017**: El plugin MUST activarse de forma perezosa respecto del
  costo de procesos: no correr CLI solo por abrir el proyecto.
- **FR-018**: El plugin MUST limitarse a **IntelliJ IDEA** en el primer
  release; la versión mínima de IDE es la **última línea estable** fijada
  en el plan al implementar (since-build / until-build de esa línea).
- **FR-019**: El plugin MUST vivir en este monorepo bajo `jetbrains-plugin/`
  y versionar el contrato CLI-cliente junto al resto del producto.
- **FR-020**: El proyecto MUST mantener una **fuente canónica anti-drift**
  para textos y reglas de producto compartidos entre la extensión VS Code
  y el plugin (versión mínima, npm install/update, mensajes de empty/error
  críticos, matriz situación×acción). Un cambio de producto que los toque
  MUST actualizar esa fuente (o ambos clientes) en el mismo cambio.
- **FR-021**: El plugin MUST registrar un log de invocaciones CLI
  inspectable por el revisor (equivalente al Output “Git Review CLI”).
- **FR-022**: El plugin MUST exponer settings equivalentes: path al
  dispatcher y default source del asistente (remote/local/offline).
- **FR-023**: El plugin MUST funcionar en Windows, macOS y Linux con la
  misma semántica de producto.
- **FR-024**: Tras mutaciones, el plugin MUST refrescar estado desde
  porcelain; MUST NOT parsear stdout humano de finish/save/abort para
  decidir la situación.
- **FR-025**: El *why* de la entrada actual en walk MUST cargarse de forma
  diferida y cancelable si el cursor se mueve antes de que llegue.

### Key Entities

- **RepositoryTarget**: un root git usable (path + etiqueta); a lo sumo uno
  por sesión de producto.
- **ReviewState**: situación + datos porcelain parseados (state, entries,
  branches, config, finish, flags readonly/keys).
- **PanelModel**: proyección serializable de qué debe mostrar el panel
  (sin detalles de Swing/HTML).
- **PathRef**: par raw/display de un path de entrada.
- **ReviewIntent**: elecciones del asistente de start (rama, source,
  range, layout) antes de materializar argv.
- **StateToken**: huella de frescura (rama/tip/situación) para mutaciones.
- **InvocationClass**: lectura / mutación local / red — define timeout y
  entorno.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un revisor con CLI ≥ mínima y un solo repo puede, sin
  terminal, completar el flujo start → leer (open/diff/why) → next/prev →
  finish en un proyecto de prueba del sandbox del repo.
- **SC-002**: El 100 % de las situaciones de la tabla consolidada son
  alcanzables y distinguibles en el panel con fixtures controladas.
- **SC-003**: El 100 % de las acciones de la superficie consolidada tienen
  un camino de UI o acción del IDE y el mismo efecto observable que la
  extensión. Verificable de forma automatizada: un test table-driven
  `(acción, parámetros) → argv` cubre las 27 acciones contra la tabla de
  `contracts/cli-invocation.md`, y el smoke del quickstart contrasta el log
  de invocaciones contra el de la extensión en el mismo repo.
- **SC-004**: Paths con espacio y no-ASCII del sandbox se listan y abren
  correctamente en Windows, macOS y Linux.
- **SC-005**: Ninguna mutación concurrente se aplica en paralelo; la
  segunda se rechaza de forma visible.
- **SC-006**: Con panel cerrado y sin acciones del usuario, abrir un
  proyecto no lanza procesos de `git review` (activación perezosa
  verificable).
- **SC-007**: La capa de parseo y proyección del modelo tiene tests
  automatizados sin IDE que cubren los mismos casos que la capa pura de la
  extensión. Cierre explícito del alcance: se portan los specs de
  `vscode-extension/test/unit/` **salvo** `panelHtml.spec.ts` (markup de un
  editor ajeno) y `userDataDir.spec.ts` (infraestructura de test de VS Code);
  `repository.spec.ts` se porta como `SoleTarget`. Todo lo demás — porcelain,
  configPorcelain, nameStatus, situation, state, panelModel, reviewIntent,
  layoutOffers, sourcePreference, housekeeping, finishOutcome, startFailure,
  staleGuard, mutationLock, entryArg, cliProbe, cliLog, installCli,
  invokeClass, invokeTimeout, unquote, version — tiene port.
- **SC-008**: Un cambio de versión mínima de CLI o del comando npm de
  install no puede quedar solo en un cliente: la fuente anti-drift o el
  checklist de release lo detecta.
- **SC-009**: El panel nativo respeta el tema del IDE (claro/oscuro) sin
  hojas de estilo hardcodeadas a un editor ajeno.
- **SC-010**: En un start que stagea muchos archivos, abrir “changes” de un
  archivo del rango inmediatamente después del éxito muestra el diff correcto
  y no vacío. Se verifica en el smoke del quickstart (caso #4) abriendo el
  diff apenas termina el start; el criterio es el contenido, no un umbral de
  milisegundos cronometrado.

## Assumptions

- **Paridad total** con la extensión VS Code al momento de implementar:
  la superficie consolidada de esta spec es el techo y el piso del v1 del
  plugin. Si la extensión gana superficie después, se enmienda esta feature
  o una siguiente — no se “asume paridad” sin actualizar la tabla. La regla
  operativa es concreta: antes de cerrar el release se re-verifica la
  superficie contra la extensión (T063a) y lo que aparezca se enmienda acá o
  se declara fuera de v1 por escrito; nunca se resuelve en silencio.
- **Panel nativo del IDE** (implementación prevista: Swing/tool window
  JetBrains), no JCEF/webview reutilizando el HTML de VS Code. Decisión de
  producto ya tomada: theming, a11y e HiDPI del IDE importan más que
  reutilizar markup.
- **Solo IntelliJ IDEA**, última línea estable de IDE al pinnear
  `since-build` en implementación. Otras IDEs de la familia quedan fuera
  del primer release (alcance de testing).
- **Ubicación del código**: `jetbrains-plugin/` en este monorepo.
- **CLI mínima**: 0.4.0 (la que trae el contrato que el cliente actual
  exige). Si la CLI sube de major de contrato, ambos clientes suben juntos.
- **Idioma de UI del plugin**: inglés en strings de producto, igual que la
  extensión (los README del repo siguen siendo EN+ES).
- **Distribución**: empaquetado compatible con JetBrains Marketplace forma
  parte del plan de entrega; la publicación real puede ser un paso
  operativo posterior si faltan secretos/certificados, pero el artefacto
  debe poder construirse en CI.
- **Git del IDE**: se usa solo para descubrir roots, señales de cambio y
  construcción de contenidos de diff nativos — no como fuente del estado
  de review.
- **Tests de integración del IDE**: platform tests headless **acotados** en
  CI Linux (wiring del tool window, activación perezosa de SC-006, una lectura
  de estado real) — no opcionales. Los otros dos SO corren solo los unit de
  dominio; su cobertura de IDE real es la matriz smoke manual del quickstart,
  obligatoria antes de declarar release.
- Las specs `002`–`008` **no** son la norma de paridad; se citan solo como
  historia. Ante conflicto, gana el código de la extensión + CLI.

## Dependencies

- CLI `git-review-workflow` instalable en PATH o vía setting de path.
- Git usable en la máquina (y, para diffs nativos, integración Git del
  IDE / Git4Idea en IDEA).
- JDK y toolchain del plugin fijados en el plan (compatible con la línea
  de IDE elegida).
