# Feature Specification: Submodo walk solo-keys

**Feature Branch**: `007-walk-keys-only`

**Created**: 2026-08-06

**Status**: Draft

**Input**: User description: "agregar un modo para solo ver los archivos que son
keys; primero en la CLI como submodo de walk donde solo muestre esas keys y
next/prev se adhieran; luego la extensión debe dar la misma posibilidad"

## Contexto y Motivación *(el porqué)*

### El problema

El walkthrough ya permite marcar entradas esenciales con `> key`: son los pocos
archivos que “llevan” el cambio y que un revisor no debería leer por arriba.
Hoy ese marcador es **pasivo**: etiqueta `(key)`, badge en el panel y contador
al entrar. `next`/`prev` (y el cursor del panel) siguen recorriendo **todas**
las entradas del orden de lectura — incluidas las no esenciales, los
`uncovered` y el propio sidecar.

Para un PR grande donde el autor marcó bien (tres o cuatro keys entre
decenas de archivos), el revisor que quiere un primer pase crítico no tiene
forma nativa de restringir la secuencia a esas entradas. Tiene que saltar a
mano, o confiar en memoria y en el badge.

### Por qué importa ahora

Porque el marcador ya está en el producto, en porcelain (`essential`) y en el
panel; falta la acción que lo justifique. Sin un submodo de lectura, `> key`
es cosmético. Con él, el autor invierte en marcar sabiendo que el revisor
puede usarlo.

### Qué habilita

- En CLI: iniciar (o comparar en walk) con un filtro **solo-keys** de forma
  que la secuencia efectiva, `next`/`prev`, `status` humano y porcelain
  muestren únicamente las entradas esenciales, en el mismo orden relativo
  del walkthrough.
- En la extensión: la misma opción al abrir una review walk y la misma
  navegación restringida (vía CLI; el panel no deriva el filtro solo).

### Qué NO es esto

- **No es un modo nuevo paralelo a whole/step/walk.** Sigue siendo `mode =
  walk` con un filtro de secuencia activo.
- **No cambia el working tree.** En walk el PR completo sigue materializado;
  solo se acorta el cursor de lectura.
- **No reescribe el walkthrough** ni inventa keys automáticas.
- **No obliga a marcar keys** para usar walk normal.
- **No bloquea `finish`** por no haber “visitado” entradas no-key: el revisor
  eligió un pase acotado; el árbol sigue teniendo el PR entero.
- **No es un filtro cosmético del panel** que deje `next` en la secuencia
  completa: CLI y extensión comparten la misma secuencia efectiva.

## User Scenarios & Testing *(mandatory)*

El actor principal es el **revisor**. El autor del PR solo entra de forma
indirecta (sus marcadores `> key` habilitan el submodo).

### User Story 1 - Primer pase solo por las keys desde la CLI (Priority: P1)

El revisor arranca una review walk pidiendo solo las entradas esenciales.
Ve el heads-up como siempre, pero el orden de lectura, el contador y
`next`/`prev` recorren únicamente las keys, en el orden en que aparecen en el
walkthrough.

**Why this priority**: es el valor completo del submodo; sin esto no hay
producto.

**Independent Test**: con un walkthrough de N entradas de las cuales K son
key (K ≥ 1, K < N), iniciar con el filtro solo-keys y verificar que el
cursor visita exactamente esas K rutas, en orden, y que `next` al final de
la última key no avanza a no-keys.

**Acceptance Scenarios**:

1. **Given** un PR con walkthrough válido y al menos una entrada `> key`,
   **When** el revisor inicia la review en modo walk con el filtro solo-keys,
   **Then** la secuencia efectiva tiene solo esas entradas, en el mismo orden
   relativo del walkthrough, renumeradas 1..K, y el estado reporta el filtro
   activo.
2. **Given** esa review, **When** el revisor usa avanzar / retroceder,
   **Then** el cursor solo se mueve entre las K keys; no aparece ninguna
   entrada no-key ni uncovered en la secuencia.
3. **Given** el revisor está en la última key, **When** pide avanzar,
   **Then** el comportamiento es el de “fin de secuencia” del walk normal
   (no salta a archivos fuera del filtro).
4. **Given** la review solo-keys, **When** consulta el estado humano o
   machine-readable, **Then** el total y las entradas listadas coinciden con
   las K keys (no con el orden completo del walkthrough).
5. **Given** un `start`/`compare` que pediría walk pero se combina el filtro
   solo-keys con un modo incompatible (p. ej. commit-a-commit o sin walk),
   **When** se invoca, **Then** la operación falla con un mensaje claro y no
   deja review a medias.

---

### User Story 2 - Persistencia del filtro en el ciclo de review (Priority: P2)

El revisor pausa, retoma o cierra la review sin que el filtro solo-keys se
pierda ni cambie el significado de `finish`/`abort`/`preview`.

**Why this priority**: sin persistencia, save/continue rompe el submodo; es
parte del ciclo real, no del demo de `next`.

**Independent Test**: iniciar solo-keys, `save`, `continue`, y comprobar que
la secuencia y el contador siguen siendo solo-keys; `finish`/`abort` con el
mismo efecto que en walk normal.

**Acceptance Scenarios**:

1. **Given** una review walk con solo-keys, **When** el revisor la guarda y
   luego la retoma, **Then** el filtro sigue activo y el cursor está en la
   misma posición relativa dentro de las keys.
2. **Given** una review solo-keys con ediciones en el working tree, **When**
   hace `finish` (o el equivalente del panel), **Then** se extraen las
   ediciones como en walk normal; no se exige haber “visitado” no-keys.
3. **Given** una review solo-keys, **When** hace `abort`, **Then** se
   descarta igual que cualquier walk.
4. **Given** una review solo-keys, **When** pide `preview`, **Then** ve las
   ediciones actuales sin mutar el filtro ni la secuencia.

---

### User Story 3 - Misma opción desde la extensión (Priority: P3)

Al iniciar una review walk desde el panel, el revisor puede elegir “solo
keys”. Con la review ya en solo-keys (abierta desde CLI o panel), el panel
muestra el filtro, lista solo esas entradas y `next`/`prev` del panel
respetan la misma secuencia.

**Why this priority**: paridad CLI↔panel; depende de que P1 exista y del
contrato machine-readable.

**Independent Test**: iniciar walk con solo-keys desde el panel en un repo
con keys; el panel muestra K entradas, todas esenciales, y avanzar no abre
no-keys.

**Acceptance Scenarios**:

1. **Given** un repo con walkthrough y keys, sin review activa, **When** el
   revisor inicia walk desde el panel y activa solo-keys, **Then** la CLI
   recibe el equivalente al inicio solo-keys y el panel refleja el filtro.
2. **Given** una review ya en solo-keys (abierta por CLI), **When** el panel
   refresca, **Then** muestra el filtro activo, total = K y solo entradas
   key en el listado / jump.
3. **Given** solo-keys activo, **When** el revisor usa next/prev del panel,
   **Then** el comportamiento coincide con la CLI (misma secuencia).
4. **Given** un walkthrough sin ninguna key, **When** el revisor intenta
   iniciar solo-keys desde el panel, **Then** ve el mismo rechazo que en
   CLI (no se crea una review vacía engañosa).

---

### Edge Cases

- **Cero keys** en el walkthrough (o ninguna key en el rango vigente): el
  inicio con solo-keys **falla** con mensaje accionable (marcar `> key` o
  iniciar walk normal); no crea review con secuencia vacía.
- **Todas las entradas son key**: solo-keys es equivalente en secuencia al
  walk completo (mismo orden); el filtro sigue reportándose activo.
- **Walkthrough degradado / ausente**: no hay walk; solo-keys no aplica (mismo
  rechazo que “no es walk” / incompatibilidad).
- **Base se movió** y alguna key sale del rango: la secuencia se re-deriva
  como en walk; si el cursor queda fuera de rango, mismos códigos/recuperación
  que walk hoy. Si tras re-derivar no queda ninguna key, el estado es el de
  secuencia vacía / fuera de rango que ya usa el producto — no se inventa un
  modo especial.
- **Uncovered** (paths en el rango sin entrada en el walkthrough): **nunca**
  entran en la secuencia solo-keys (no pueden ser key).
- **`--why` / abrir el why**: solo válido para paths que están en la
  secuencia efectiva (las keys filtradas).
- **Consumidores viejos del contrato machine-readable**: ignoran el indicador
  aditivo del filtro; siguen viendo `mode=walk` y las `entry` (ya filtradas).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El revisor MUST poder iniciar una review en modo walk con un
  filtro **solo-keys** desde la CLI, de forma simétrica a cómo elige hoy
  walk vs step vs whole (flag de inicio, no un verbo distinto de ciclo).
- **FR-002**: Con solo-keys activo, la secuencia efectiva de lectura MUST
  contener únicamente las entradas del walkthrough que llevan el marcador
  esencial y cuyo path está en el rango de la review, en el orden relativo
  del walkthrough, con posiciones 1..K.
- **FR-003**: `next` y `prev` MUST mover el cursor solo dentro de esa
  secuencia filtrada.
- **FR-004**: El estado humano de la review MUST indicar que el filtro
  solo-keys está activo y MUST mostrar contadores y entrada actual
  coherentes con la secuencia filtrada.
- **FR-005**: El estado machine-readable MUST exponer de forma aditiva que el
  filtro solo-keys está activo, y MUST listar solo las entradas de la
  secuencia filtrada (con `total` igual al número de esas entradas).
- **FR-006**: Solo-keys MUST ser incompatible con el modo commit-a-commit y
  con el forzado de whole sin walk; la CLI MUST rechazar la combinación
  sin dejar estado parcial.
- **FR-007**: Si al aplicar el filtro no queda ninguna entrada esencial en
  rango, el inicio MUST fallar con diagnóstico claro (no secuencia vacía).
- **FR-008**: `save` / `continue` MUST preservar el filtro solo-keys y la
  posición del cursor dentro de la secuencia filtrada.
- **FR-009**: `finish`, `abort` y `preview` MUST comportarse como en walk
  normal respecto al working tree y a las ediciones; no exigen recorrer
  entradas fuera del filtro.
- **FR-010**: `compare` en modo walk MUST aceptar el mismo filtro solo-keys
  con las mismas reglas de secuencia y de rechazo.
- **FR-011**: La extensión MUST ofrecer la opción solo-keys al iniciar una
  review walk (y al comparar en walk, si el panel expone compare), y MUST
  reflejar el filtro activo leyendo solo el estado machine-readable (sin
  leer config git cruda).
- **FR-012**: Documentación de producto (README EN/ES; landing solo si el
  cambio toca su superficie ya listada) MUST describir el submodo y su
  límite (pase acotado, no “review completa por omisión”).

### Key Entities

- **Filtro solo-keys**: preferencia de la sesión de review walk que restringe
  la secuencia efectiva a entradas esenciales. Se enciende al iniciar (o
  compare) y vive con la metadata de la review hasta abort/finish/forget.
- **Secuencia efectiva**: lista ordenada de paths que `next`/`prev` y el
  estado enumeran. En walk normal = orden de lectura completo (curadas +
  uncovered). En solo-keys = solo keys en rango.
- **Entrada esencial**: entrada del walkthrough con marcador `> key` (ya
  existente); no se redefine el marcador.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: En un PR de juguete con ≥ 5 entradas de walkthrough y ≥ 2 keys,
  un revisor completa el recorrido solo-keys (primera a última key con
  next) sin encontrar ninguna entrada no-key en estado o en el cursor.
- **SC-002**: El 100 % de los intentos de solo-keys sin keys en rango
  producen error claro y cero ramas `review/*` nuevas.
- **SC-003**: Tras `save` + `continue`, el revisor recupera el mismo índice
  dentro de las keys y el mismo total K en ≥ 95 % de las corridas de la
  suite automatizada del feature (sin flakiness de carrera).
- **SC-004**: Un consumidor que solo habla el contrato machine-readable
  anterior puede seguir parseando `state`/`entry` de una review solo-keys
  (campos desconocidos al final o registros nuevos ignorables) y ve un
  listado consistente (solo keys).
- **SC-005**: Desde el panel, un revisor puede iniciar walk solo-keys y
  avanzar entre keys sin abrir la terminal, con el mismo K que reporta la
  CLI.

## Assumptions

- El filtro se elige **al iniciar** la review (`start` / `compare`), no se
  exige un verbo nuevo de ciclo para v1; no hay toggle mid-session en el
  alcance inicial (se puede ampliar después sin romper el contrato si el
  indicador porcelain ya existe).
- Solo-keys **no** es el default: el default sigue siendo walk completo
  cuando hay walkthrough.
- `finish` no advierte por no-keys no visitados: el working tree ya tiene el
  PR completo; el filtro es una elección de lectura, no un checklist de
  cobertura.
- Los uncovered nunca son keys; excluirlos del filtro es consecuencia del
  modelo actual, no una regla nueva de uncovered.
- La extensión no implementa el filtro en cliente: invoca la CLI y relee
  porcelain (filosofía de `002`/`005`).
- La numeración 1..K de la secuencia filtrada es la que ven humano,
  porcelain y panel; no se conservan los índices del walk completo en el
  cursor (el orden relativo de keys sí se conserva).
- Si en el futuro se quisiera “expandir a walk completo” mid-review, sería
  otra feature; v1 es sticky desde el start.
- Feature `006` (superficie panel completa) es ortogonal; esta feature no
  depende de que `006` esté mergeada, salvo reutilizar patrones de start en
  el panel ya existentes en `005`.
