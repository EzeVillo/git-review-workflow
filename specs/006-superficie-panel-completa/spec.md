# Feature Specification: Superficie completa del panel (housekeeping, utilidades, autoría)

**Feature Branch**: `006-superficie-panel-completa`

**Created**: 2026-08-06

**Status**: Draft

**Input**: User description: "avancemos con housekeeping (forget, clean, borrar
orphans con un clic), autoría (walkthrough), utilidades (compare, preview);
simplemente con una confirmación ya está ok, avisando qué se va a hacer, como
pasa hoy con start"

## Contexto y Motivación *(el porqué)*

### El problema

Con [`005-ciclo-review-panel`](../005-ciclo-review-panel/spec.md) el revisor
abre, lee, pausa, retoma y cierra una review sin terminal. Quedan fuera, a
propósito, tres franjas que la CLI ya resuelve y el panel no:

1. **Housekeeping** — `clean` y `forget` (y las filas *orphan* del inventario,
   que hoy solo muestran un comando a copiar).
2. **Utilidades de lectura** — `preview` (qué ediciones tengo ahora) y
   `compare` (montar un rango arbitrario como review de solo lectura).
3. **Autoría del walkthrough** — `walkthrough init` / `build`, el flujo del
   autor del PR.

La exclusión de `005` no era “nunca”: era “no entran al ciclo con el criterio
de admisión de entonces”. Ese criterio pedía **inversa en el panel**. Los
destructivos no la tienen; la autoría no es del revisor; compare/preview no
abren ni cierran un PR. Con el ciclo cerrado, el hueco molesta: el inventario
muestra basura que no se puede limpiar, el revisor no puede mirar sus ediciones
sin `finish`, y el autor del walkthrough sigue en la terminal aunque ya edita
en el mismo editor.

### Por qué importa ahora

Porque la confirmación modal que `005` ya fijó para `abort`/`save`/`start` es
exactamente la traducción del riesgo asimétrico que faltaba para admitir
`clean`/`forget`. No hace falta inventar un “undo de clean”: hace falta decir
en el diálogo **qué se borra**, igual que el abort dice que se descartan las
ediciones. Con eso, el criterio de admisión se enmienda una sola vez y la
lista cerrada de invocaciones puede cubrir el resto de la CLI que el producto
ya publica.

### Qué habilita

Que, sin salir del editor, se pueda:

- limpiar leftovers y reviews guardadas (incluida una fila orphan con un clic);
- ver las ediciones actuales sin cerrar la review;
- montar una comparación entre dos puntas como review de solo lectura;
- inicializar y validar el walkthrough del PR en la rama de trabajo.

### Qué NO es esto

- **No mueve estado a la extensión.** Sigue la premisa de `002`/`005`: todo
  cambio de estado es un verbo; el panel relee porcelain.
- **No inventa flags.** Sólo los que ya expone cada verbo.
- **No es un cliente de GitHub** ni publica al Marketplace.
- **No reescribe el walkthrough en la UI.** El autor edita el markdown en el
  editor; el panel solo dispara `init`/`build` y abre el archivo.
- **No incluye `--dry-run` en la UI** (la CLI lo tiene; el panel confirma en
  prosa antes de mutar).
- **No expone `git branch -D`.** Los leftovers se borran con `clean` /
  `forget`, nunca con un comando git crudo.

### Criterio de admisión enmendado

Un verbo puede ofrecerse desde el panel si cumple **las tres**:

1. **Es representable.** El resultado se lee por porcelain, o es una
   operación de solo lectura cuyo efecto es mostrar un artefacto al usuario
   (p. ej. un diff), sin alimentar el view-model de estado de review.
2. **Es seguro de disparar.** O tiene inversa en el panel, **o** va detrás de
   una confirmación modal que nombra el efecto concreto (y revalida el estado
   si muta). Las de solo lectura pueden omitir confirmación.
3. **Tiene hogar en el producto.** Ciclo de review, housekeeping del
   inventario/repositorio, utilidad de lectura ya expuesta por la CLI, o
   autoría del walkthrough.

Esta feature enmienda el criterio de `005` (que exigía inversa) y levanta la
prohibición de `clean`, `forget`, `walkthrough`, `compare` y `preview` en el
contrato de invocación, con la lista cerrada de argumentos.

## User Scenarios & Testing *(mandatory)*

El actor principal es el **revisor**; en la historia de walkthrough es el
**autor del PR** (puede ser la misma persona).

### User Story 1 - Limpiar basura de reviews sin terminal (Priority: P1)

El revisor ve en el inventario reviews guardadas, leftovers en otras ramas o
filas *orphan* (rama de review sin metadata). En lugar de copiar un comando,
confirma una acción que nombra qué se borra y el inventario se actualiza.

**Why this priority**: cierra el único hueco del inventario que `005` dejó a
medias (texto de recovery sin acción) y cubre el housekeeping diario.

**Independent Test**: con una review `saved`, un leftover `review/<src>` no
checked-out y un orphan, ejecutar cada acción desde el panel y verificar con
la CLI que el efecto es el del verbo equivalente y que el panel ya no lista lo
borrado.

**Acceptance Scenarios**:

1. **Given** una review guardada en el inventario, **When** el revisor elige
   descartarla y confirma, **Then** se invoca el equivalente a
   `git review forget --saved <src>` y la fila desaparece del inventario.
2. **Given** leftovers `review/<src>` / `review-fixes/<src>` sin estar en esa
   rama, **When** el revisor limpia esa fuente y confirma, **Then** se invoca
   `git review clean <src>` y esas ramas dejan de existir.
3. **Given** una fila orphan `saved`, **When** el revisor pide descartarla y
   confirma, **Then** se usa `forget --saved <src>` (no un borrado git crudo).
4. **Given** una fila orphan no guardada (`review/…` sin metadata), **When**
   confirma el descarte, **Then** se usa `clean <src>`.
5. **Given** el Command Palette, **When** el revisor elige limpiar todos los
   leftovers o olvidar todos los saved / todos los deltas / deltas stale, y
   confirma el texto que nombra el alcance, **Then** se invoca el verbo con
   el target correspondiente (`clean` sin arg; `forget --saved --all`;
   `forget --delta --all`; `forget --delta --stale`).
6. **Given** un diálogo de confirmación abierto, **When** el revisor lo
   descarta, **Then** no se invoca ningún verbo y el estado no cambia.
7. **Given** que el estado cambió entre abrir el diálogo y confirmar,
   **When** confirma, **Then** la acción no se ejecuta sobre la premisa
   caduca y se avisa.

---

### User Story 2 - Ver mis ediciones sin cerrar la review (Priority: P2)

En medio de una review activa, el revisor quiere saber qué ediciones llevaría
`finish` ahora, sin cambiar de rama ni tocar el working tree.

**Why this priority**: es la utilidad más pedida del “medio” del ciclo y no
muta estado; alto valor, bajo riesgo.

**Independent Test**: con ediciones en una review activa, disparar preview
desde el panel y comprobar que el working tree / HEAD no cambiaron y que el
contenido mostrado coincide con lo que imprimiría `git review preview`.

**Acceptance Scenarios**:

1. **Given** una review activa con ediciones, **When** el revisor pide
   preview, **Then** ve el diff de sus ediciones (equivalente a
   `git review preview`) sin confirmación modal (no muta).
2. **Given** la misma situación, **When** pide un resumen, **Then** ve el
   equivalente a `git review preview --stat`.
3. **Given** un cierre mid-conflict o un estado en el que la CLI rechaza
   preview, **When** lo pide, **Then** ve el diagnóstico de la CLI y el
   repositorio no se altera.
4. **Given** que no hay review activa, **When** se intenta preview,
   **Then** no se inventa un diff: la acción no aplica o muestra el rechazo
   de la CLI.

---

### User Story 3 - Comparar dos puntas como review de solo lectura (Priority: P3)

El revisor quiere montar el diff entre dos commit-ish (ramas, tags o SHAs)
como una review legible con el panel, sabiendo que no hay `finish` hacia un
PR.

**Why this priority**: completa la paridad con `compare`; depende del mismo
molde de asistente que `start` pero con dos puntas.

**Independent Test**: elegir dos candidatas (o commit-ish), confirmar el
resumen, y verificar que queda una review activa indistinguible de
`git review compare <a> <b>` con el layout elegido.

**Acceptance Scenarios**:

1. **Given** un repo sin review activa (o en condiciones que la CLI acepta),
   **When** el revisor elige lower bound, upper bound y forma de lectura
   (auto / step / no-walk), confirma el resumen, **Then** queda en la review
   que dejaría `git review compare <a> <b> [flags]`.
2. **Given** que descarta la confirmación, **Then** no se crea review.
3. **Given** que la CLI rechaza (working tree sucio, mismos commits, etc.),
   **When** confirma igual, **Then** ve el stderr de la CLI y no se finge
   éxito.

---

### User Story 4 - Autorar el walkthrough desde el editor (Priority: P4)

El autor del PR quiere generar el esqueleto del walkthrough, editarlo en el
editor y validarlo/reordenarlo con `build`, sin recordar los subcomandos.

**Why this priority**: es el flujo de **autor**, no del revisor del ciclo;
entra al final para no bloquear housekeeping ni utilidades.

**Independent Test**: en una rama con cambios vs base, `init` crea
`.review/walkthrough.md` y lo abre; tras rellenar, `build` reescribe como la
CLI; con archivo ya existente, `init` pide confirmación antes de `--force`.

**Acceptance Scenarios**:

1. **Given** una rama con cambios vs la base y sin walkthrough, **When** el
   autor inicia walkthrough, **Then** se corre `walkthrough init`, se crea el
   sidecar y se abre en el editor.
2. **Given** un walkthrough existente, **When** pide init de nuevo,
   **Then** una confirmación nombra que se va a sobrescribir y, si confirma,
   se invoca con `--force`.
3. **Given** un walkthrough rellenado, **When** pide build, **Then** se
   invoca `walkthrough build` y el archivo queda como lo dejaría la CLI (o
   se muestra el error de validación sin reescribir en fallo).
4. **Given** que falta la base o no hay cambios, **When** init/build fallan,
   **Then** el diagnóstico de la CLI se muestra tal cual.

---

### Edge Cases

- Confirmación abierta mientras otra pestaña corre `clean`/`forget`/`abort`.
- `clean` de la review actualmente checked-out: la CLI salta esa rama; el
  panel no anticipa, muestra el resultado.
- `forget --delta --stale` necesita red (fetch); mismo tratamiento de red que
  `start` en `005`.
- `compare` con nombres que empiezan con `-`: siempre se pasan con la forma
  que el verbo ya soporta (`--` cuando aplica).
- `preview` con ediciones que conflictuarían en finish: la CLI omite y
  advierte; se muestra, no se reinterpreta.
- Walkthrough `init` con working tree sucio fuera de `.review/`: la CLI
  decide; el panel no anticipa.
- CLI demasiado vieja: no ofrecer acciones cuyo resultado el panel no sepa
  representar (misma política de mínimo de versión / degradación de `002`).

## Requirements *(mandatory)*

Los de `002`–`005` siguen vigentes salvo enmiendas explícitas de esta feature.

### Functional Requirements

#### Enmienda del criterio y de la lista cerrada

- **FR-001**: Esta feature MUST enmendar de forma trazable el criterio de
  admisión de `005` (inversa → confirmación o inversa) y la fila de
  prohibiciones de `clean`/`forget`/`walkthrough`/`compare`/`preview` en el
  contrato de invocación. MUST NOT quedar dos documentos vigentes que se
  contradigan.
- **FR-002**: La lista de invocaciones permitidas MUST seguir siendo cerrada
  **también en argumentos**. Cada verbo nuevo enumera flags y targets
  admitidos; ningún otro puede aparecer en el código.
- **FR-003**: Toda mutación (clean, forget, compare, walkthrough init/build
  con efecto de escritura) MUST ir detrás de confirmación modal que nombre el
  efecto, salvo que el verbo sea de solo lectura (`preview`). Descartar la
  confirmación MUST no tener efecto.
- **FR-004**: Tras cada mutación (éxito o fallo) el panel MUST refrescar el
  estado desde el contrato sin acción manual del usuario.
- **FR-005**: La extensión MUST NOT parsear la salida humana de estos verbos
  para derivar estado de review. Mostrar un diff o un mensaje al usuario no
  cuenta como alimentar el view-model de modo/posición/inventario.
- **FR-006**: La extensión MUST NOT invocar `git branch -D` ni tocar refs a
  mano: orphans y leftovers solo vía `clean` / `forget`.

#### Housekeeping (P1)

- **FR-007**: Los revisores MUST poder descartar una review guardada desde el
  inventario o la palette (`forget --saved <src>`).
- **FR-008**: Los revisores MUST poder limpiar leftovers de una fuente
  (`clean <src>`) y de todas (`clean` sin argumento) desde la palette; y
  limpiar una fuente desde el inventario cuando la fila lo permita (no es la
  review actual checked-out si la CLI la saltaría — el panel no tiene que
  predecir el skip; puede ofrecer y dejar el mensaje de la CLI).
- **FR-009**: Las filas orphan MUST ofrecer una acción de descarte a un clic
  (con confirmación): `forget --saved <src>` si es saved; `clean <src>` si es
  una review no guardada.
- **FR-010**: Los revisores MUST poder olvidar markers delta de una rama, de
  todas, o solo stale (`forget --delta <branch|--all|--stale>`), desde la
  palette, con confirmación que nombre el alcance. `--dry-run` no se expone.
- **FR-011**: `forget --saved --all` MUST estar disponible desde la palette
  con confirmación más fuerte que el descarte de una sola.
- **FR-012**: Mutaciones de housekeeping MUST revalidar un testigo de estado
  cuando la acción se eligió sobre una fila concreta del inventario (stale
  guard), igual que `abort` en `005`.

#### Preview (P2)

- **FR-013**: Con review activa (o en el estado en que la CLI lo permite), el
  revisor MUST poder ver el diff de ediciones actuales (`preview`) y el
  resumen (`preview --stat`) sin confirmación modal.
- **FR-014**: El contenido mostrado MUST corresponder a la salida del verbo;
  el working tree, el índice y la rama MUST quedar intactos.
- **FR-015**: Un rechazo de la CLI MUST mostrarse con su diagnóstico, sin
  inventar un diff vacío como éxito.

#### Compare (P3)

- **FR-016**: Los revisores MUST poder iniciar `compare` eligiendo lower y
  upper bound. Las ramas candidatas MUST salir del contrato de configuración
  (`candidate`); también MUST poder indicar un commit-ish que no esté en esa
  lista (entrada libre), porque `compare` acepta cualquier commit-ish.
- **FR-017**: MUST ofrecer las mismas formas de lectura que `start` en lo
  aplicable: automático, `--step`, `--no-walk`.
- **FR-018**: Antes de ejecutar, MUST resumir en una frase qué se va a montar
  (a, b, layout) y pedir confirmación.
- **FR-019**: Tras éxito, el panel MUST mostrar la review resultante como
  cualquier otra (porcelain). El registro `readonly` de `status --porcelain`
  MUST ocultar Finish (y MUST NOT inventar el flag leyendo git config). Abort,
  Save, Preview y la navegación siguen disponibles; la CLI sigue rechazando
  `finish` si se invoca por otro camino.

#### Walkthrough (P4)

- **FR-020**: El autor MUST poder ejecutar `walkthrough init` desde el
  editor; tras éxito, el sidecar MUST abrirse para editar.
- **FR-021**: Si el sidecar ya existe, `init` MUST pedir confirmación antes
  de invocar con `--force`.
- **FR-022**: El autor MUST poder ejecutar `walkthrough build` (escritura) y
  ver éxito o el error de validación de la CLI.
- **FR-023**: `--base` en init y `--check` en build **no** son obligatorios
  en la UI de esta feature; si se exponen, siguen la lista cerrada. Default:
  init sin `--base` (usa la config del repo); build sin `--check`.

#### Riesgo, red, docs (heredados aplicados)

- **FR-024**: Operaciones con red (`forget --delta --stale`) MUST usar el
  mismo tratamiento no interactivo de credenciales que `start` en `005`.
- **FR-025**: Operaciones largas MUST indicar progreso y MUST NOT ser
  cancelables a mitad si ya mutan el repo.
- **FR-026**: Las acciones nuevas MUST documentarse en el README de la
  extensión (inglés). Cambios de superficie CLI, si los hubiera, en ambos
  README raíz; esta feature no exige cambios de CLI salvo que un contrato
  nuevo demuestre un hueco (ver Assumptions).

### Key Entities

- **Acción de housekeeping**: descarte o limpieza con target (una fuente, all,
  stale) y modo (saved / delta / clean).
- **Intención de compare**: lower bound, upper bound, layout de lectura;
  existe entre la elección y la confirmación.
- **Vista de preview**: artefacto de solo lectura (diff o stat) mostrado al
  usuario; no es estado de review.
- **Sidecar de walkthrough**: `.review/walkthrough.md` en la rama de trabajo
  del autor; la extensión no lo parsea para el panel de review.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un revisor limpia una review guardada, un leftover y un orphan
  desde el panel, sin terminal, y el inventario/CLI reflejan la ausencia.
- **SC-002**: Ninguna mutación de esta feature ocurre sin confirmación que
  nombre el efecto; `preview` es la única acción nueva sin modal de
  confirmación.
- **SC-003**: Un revisor ve el diff de sus ediciones actuales y vuelve al
  mismo working tree / misma rama / mismo cursor de review.
- **SC-004**: Un `compare` desde el panel deja el mismo estado que el comando
  equivalente (misma rama de review, mismo modo).
- **SC-005**: Un autor genera el walkthrough, lo edita en el editor y lo
  valida con build sin escribir los subcomandos a mano.
- **SC-006**: Ningún dato de decisión del panel sale de leer config/refs a
  mano; no hay `git branch -D` en el código de la extensión.
- **SC-007**: Descartar cualquier confirmación deja el repo intacto.
- **SC-008**: Los tres OS de CI ejercitan automáticamente las mutaciones
  locales (forget/clean/compare/walkthrough/preview) que no requieren red;
  `forget --delta --stale` se cubre en lo posible con fixture local o queda
  enumerado como validación manual si el fetch es imprescindible.

## Assumptions

- **No hace falta porcelain nuevo para P1–P4** si el inventario y
  `config --porcelain` ya dan saved/orphan/candidatas y el estado post-mutación
  se relee con `status`/`list`. Si al implementar aparece un hueco (p. ej.
  listar todos los delta markers para un picker), se agrega al contrato CLI en
  el mismo cambio; no se lee config a mano.
- **Confirmación sustituye a la inversa** para housekeeping; el usuario aceptó
  ese nivel de riesgo explícitamente.
- **Preview se muestra como documento/diff en el editor**, no se parsea para
  el view-model.
- **Compare usa candidatas del contrato + entrada libre de commit-ish** para
  no limitar a ramas.
- **Walkthrough no agrega un editor visual** de entradas: markdown + init/build.
- **Marketplace y GitHub siguen fuera.**
- **`--dry-run` de forget no se expone** en UI.
