# Feature Specification: Listado de archivos del rango en modo whole

**Feature Branch**: `004-listado-archivos-whole`

**Created**: 2026-08-03

**Status**: Draft

**Input**: User description: "en whole no se muestra nada, pero me gustaría que se
muestren todos los archivos […] vamos con la A entonces, no hace falta respetar los
contratos y subir de versión el porcelain, de hecho si está en una versión que no es
la 1, debería quedar como la 1" / sobre los archivos bajo `.review/`: "yo los
incluiría en ambos, no sabía que walk no los incluía"

## Contexto y Motivación *(el porqué)*

### El problema

Una review en modo `whole` no dice qué archivos toca el PR. `git review status`
imprime la rama, el origen, el tip y la base, y termina en el consejo de editar y
correr `finish`. El panel del editor muestra lo mismo: una cabecera y ningún
elemento. En una review de cuarenta archivos, la superficie que el revisor tiene
para saber qué hay adentro es cero.

Los otros dos modos sí lo dicen. `step` recorre commits y los lista; `walk`
recorre archivos y los lista, incluidos los que el walkthrough no anota — que
aparecen al final del orden de lectura marcados `(uncovered)`, precisamente para
que nadie termine una review con archivos del PR que nunca vio. `whole` es el
único modo donde ese riesgo no está cubierto, y es además el modo por defecto: el
que le toca a todo PR cuyo autor no escribió un walkthrough.

### Por qué importa ahora

Porque el dato ya está calculado y ya tiene un dueño. La lista de archivos del
rango es la segunda mitad de `walk_reading_order`: `changed_paths`, que es el
punto único de normalización del lado git (`git diff --name-only` con
`core.quotePath=false`). Con un walkthrough vacío, ese orden de lectura *es*
exactamente la lista que a `whole` le falta. No hay nada que derivar de nuevo: hay
que exponer, en el modo por defecto, algo que la CLI ya sabe calcular en los otros
dos.

Del otro lado, el panel del editor cerró en `003` el hueco de paridad de `step` y
de la base de `whole`. Queda este, que es el más visible de todos porque no es un
campo que falta sino una vista entera vacía.

### Qué habilita

Que el modo por defecto deje de ser el modo ciego. Un revisor que abre un PR sin
walkthrough ve la lista completa de lo que va a revisar, y en el editor puede
abrir cualquiera de esos archivos con un clic, sin salir a la terminal ni correr
`git diff` por su cuenta.

### Qué NO es esto

- **No es un cursor.** `whole` no gana posición, ni `[k/N]`, ni `next`/`prev`.
  Recorrer un PR archivo por archivo con un cursor ya es `walk`, y duplicarlo acá
  sería un cuarto modo de facto. La lista es un **inventario**, no una secuencia.
- **No es estado persistido.** No se crea ninguna clave de configuración nueva, no
  se registra ningún total al iniciar y no se banca ninguna edición. Nada que
  agregar a los guards de metadata de `finish`.
- **No es una interfaz de diff propia.** Sigue vigente la exclusión de `002`:
  abrir un archivo o ver sus cambios se delega en el editor.
- **No cambia el rango de la review.** Qué entra y qué no lo sigue definiendo la
  CLI exactamente como hoy.
- **No mueve la derivación al editor.** El panel no calcula esta lista: la recibe.
  Un `git diff` propio del lado del editor sería un tercer punto de normalización
  de paths, que es justo lo que el contrato existe para evitar.
- **No sube la versión del formato porcelain.** Lo que hay es aditivo y el formato
  sigue siendo v1 — ver US3.
- **No hace que un walkthrough se anote a sí mismo.** El sidecar entra al orden de
  lectura de `walk` como archivo sin anotar (US4), pero `walkthrough build` sigue
  sin proponerlo como entrada: pedirle al autor un *why* sobre el archivo donde
  escribe los *why* es circular, y nadie lo pidió.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ver los archivos del PR en una review sin walkthrough (Priority: P1)

Un revisor abre un PR cuyo autor no escribió walkthrough, arranca la review y
pregunta desde la terminal qué hay adentro. `git review status` le responde con la
lista completa de archivos que el PR toca, numerados, en el orden de git.

**Why this priority**: es el agujero que la feature existe para tapar, y es
autosuficiente: entrega valor sin que el editor participe. Todo lo demás se apoya
en que la CLI reporte este dato.

**Independent Test**: en un repo con una review `whole` activa sobre un PR de N
archivos, correr `git review status` y verificar que aparecen los N paths y que
coinciden con los de `git diff --name-only` sobre el mismo rango.

**Acceptance Scenarios**:

1. **Given** una review `whole` activa sobre un PR que toca 4 archivos, **When** el
   revisor corre `git review status`, **Then** la salida lista los 4 paths y
   ninguno más.
2. **Given** esa misma review, **When** el revisor corre `git review status
   --porcelain`, **Then** la salida trae 4 registros `entry`, con posiciones 1 a 4
   y el path de cada archivo, y el registro `state` sigue sin campos de cursor.
3. **Given** un PR que toca archivos con espacios, acentos y otros bytes no ASCII,
   **When** el revisor pide el listado por cualquiera de las dos salidas, **Then**
   cada path sale byte a byte igual que en `git diff --name-only` con
   `core.quotePath=false`.
4. **Given** una review `whole` cuyo rango no toca ningún archivo, **When** el
   revisor pide el listado, **Then** no se emite ningún registro `entry`, la salida
   humana lo dice explícitamente y el comando termina con éxito.
5. **Given** una review `whole` activa, **When** el revisor corre `git review next`,
   **Then** falla igual que hoy: la lista no habilita navegación.

---

### User Story 2 - Abrir esos archivos desde el panel del editor (Priority: P2)

El mismo revisor, con el proyecto abierto en el editor, ve en el panel la lista de
archivos del PR y abre cualquiera de ellos con un clic, sin escribir un path a
mano ni volver a la terminal.

**Why this priority**: es donde el dato se vuelve accionable, pero depende
enteramente de US1 — el panel no puede mostrar lo que la CLI no reporta. Recortable
sin dejar US1 a medias.

**Independent Test**: abrir en el editor un repo con una review `whole` activa y
verificar que el panel lista los archivos del rango y que un clic abre el correcto,
incluidos los paths con espacios y con acentos.

**Acceptance Scenarios**:

1. **Given** una review `whole` activa sobre un PR de N archivos, **When** el
   revisor abre el panel, **Then** ve los N archivos listados y un conteo, en lugar
   de una vista vacía.
2. **Given** esa lista, **When** el revisor hace clic en un archivo que existe en su
   working tree, **Then** se abre ese documento, editable.
3. **Given** un archivo que el PR elimina, **When** el revisor hace clic en él,
   **Then** se abre su diff — el archivo no existe en el working tree y el diff es
   la única superficie con contenido.
4. **Given** una review `whole`, **When** el revisor mira el panel, **Then** no
   aparece ninguna posición `[k/N]` ni ningún control de anterior/siguiente.
5. **Given** una versión del editor anterior a esta feature y una CLI que ya emite
   el listado, **When** el revisor abre el panel, **Then** el panel funciona como
   siempre y no muestra ni un error ni una lista rota.

---

### User Story 3 - Un solo contrato de porcelain, sin versiones paralelas (Priority: P3)

Quien lea el contrato del formato porcelain encuentra un único documento por verbo,
describiendo el formato completo y vigente, sin tener que reconstruirlo a partir de
un documento base más un delta rotulado con otra versión.

**Why this priority**: no cambia lo que el usuario final ve, pero es la condición
que el pedido puso sobre las otras dos historias, y hacerlo después significaría
tocar los mismos archivos dos veces.

**Independent Test**: buscar en el repositorio rótulos de versión del formato
porcelain y verificar que el único que aparece es v1, y que ningún documento se
describe a sí mismo como delta sobre otro.

**Acceptance Scenarios**:

1. **Given** el repositorio después del cambio, **When** alguien busca referencias a
   una versión de porcelain distinta de v1, **Then** no encuentra ninguna, ni en los
   documentos ni en los comentarios del código.
2. **Given** el contrato consolidado, **When** alguien lo lee de principio a fin,
   **Then** encuentra descriptos todos los registros vigentes —incluidos los que hoy
   viven en el documento aparte y los que agrega esta feature— sin remitirlo a otro
   archivo.
3. **Given** que el contrato afirma hoy que en `whole` no hay registros `entry`,
   **When** se consolida, **Then** esa afirmación queda reemplazada por la regla
   nueva, no contradicha en dos lugares.

---

### User Story 4 - El walkthrough también es contenido revisable (Priority: P2)

Un revisor recorre un PR con walkthrough. Al llegar al final del orden de lectura
encuentra, entre los archivos que el walkthrough no anota, el propio
`.review/walkthrough.md` que el autor commiteó. Es un archivo que el PR agrega o
modifica, y hasta ahora era el único que ninguna review mostraba nunca.

**Why this priority**: es el mismo principio que US1 aplicado al modo que ya tenía
listado — ningún archivo del PR queda invisible — y es independiente: se puede
implementar y probar sin tocar `whole`. Va después de US1 porque allá el hueco es
una vista entera vacía y acá es un archivo.

**Independent Test**: en una review `walk` sobre un PR que commitea un walkthrough,
verificar que el total del orden de lectura incluye `.review/walkthrough.md` y que
`next` termina parando en él.

**Acceptance Scenarios**:

1. **Given** una review `walk` sobre un PR que commitea un walkthrough y toca otros
   3 archivos, todos anotados, **When** el revisor mira el estado, **Then** el total
   es 4 y la cuarta posición es `.review/walkthrough.md`, marcada como sin anotar.
2. **Given** esa review, **When** el revisor avanza hasta el final, **Then** `next`
   lo lleva al walkthrough antes de decir que no hay más entradas.
3. **Given** un autor que corre `walkthrough build` sobre ese mismo PR, **When**
   mira el archivo generado, **Then** no aparece ninguna entrada para
   `.review/walkthrough.md`: el generador sigue sin proponerlo.
4. **Given** una review `walk` abierta con una versión anterior de la herramienta
   (cuyo total registrado no contaba el walkthrough), **When** el revisor la retoma
   con la versión nueva, **Then** el total derivado es mayor que el registrado y ni
   la CLI ni el panel reportan eso como un error ni como que la base se movió.
5. **Given** un PR cuyo walkthrough degrada por estar roto o stale, **When** la
   herramienta lista los archivos que quedaron sin cubrir, **Then** el walkthrough
   aparece en esa lista, igual que en el orden de lectura.

---

### Edge Cases

- **Rango vacío**: una review cuyo rango no toca archivos. Cero entradas, éxito, y
  la salida humana lo dice — nunca una lista en blanco sin explicación.
- **Paths que git cita**: un path con `"` o `\` sale citado por git, con sus
  comillas y escapes, igual que en el resto del contrato. El listado no desarma esa
  cita.
- **PR muy grande**: cientos de archivos. La salida humana los lista todos (la
  referencia es `git status`, que tampoco trunca) y el panel sigue usable.
- **Archivos eliminados en el rango**: aparecen en la lista aunque no existan en el
  working tree; abrirlos cae en el diff.
- **`whole` por degradación**: una review que pidió `walk` y cayó a `whole` porque
  el walkthrough estaba roto o stale. Lista igual que cualquier otra `whole`, y la
  nota de degradación sigue mostrándose.
- **CLI nueva con editor viejo, y al revés**: ninguna de las dos combinaciones puede
  romper. La primera muestra registros que el editor viejo ignora; la segunda
  muestra una lista vacía donde no hay dato, que es el comportamiento de hoy.
- **El working tree editado durante la review**: la lista se deriva contra el tip
  fijado de la review, así que editar archivos no la altera. Los archivos que el
  revisor cree nuevos no se suman a la lista.
- **Un PR que sólo toca el walkthrough**: sigue degradando a `whole` — ningún
  walkthrough puede anotarse a sí mismo, así que el rango nunca tiene una entrada
  guiada que intersecte, el mismo camino que cualquier otro walkthrough que no
  aplica al rango. La diferencia la hace US1: antes esa degradación dejaba el PR
  entero invisible (`whole` no mostraba nada); ahora la nota nombra el archivo y
  `whole` lo lista. Ver FR-024.
- **Reviews `walk` en curso**: su total registrado no contaba el walkthrough, así
  que el total derivado pasa a ser mayor. Es una secuencia que crece, no una base
  que se movió, y ninguna de las dos superficies debe reportarlo como problema.
- **Otros archivos bajo `.review/`**: la regla es por prefijo, no por nombre. Todo
  lo que cuelgue de ese directorio deja de filtrarse en las dos superficies.

## Requirements *(mandatory)*

### Functional Requirements

**Del listado en la CLI (US1)**

- **FR-001**: En modo `whole`, `git review status` MUST listar los archivos que
  toca el rango de la review, cada uno con su posición 1-based.
- **FR-002**: En modo `whole`, `git review status --porcelain` MUST emitir un
  registro `entry` por archivo del rango, con la posición y el path.
- **FR-003**: Los registros `entry` de `whole` MUST omitir enteros los campos que
  no aplican al modo (los de `walk` y el de `step`) — omitidos, nunca vacíos, la
  misma regla que ya rige por modo.
- **FR-004**: El registro `state` de `whole` MUST seguir sin los campos de cursor
  (posición, total, registrado, actual). La lista no introduce un cursor.
- **FR-005**: El orden del listado MUST ser el que devuelve el punto único de
  normalización de paths del lado git, y MUST ser estable entre invocaciones sobre
  el mismo rango.
- **FR-006**: Los paths MUST emitirse byte a byte tal como los devuelve ese mismo
  punto, siguiendo la regla de paths ya vigente en el contrato.
- **FR-007**: Un rango sin archivos MUST producir cero registros `entry` y terminar
  con éxito, y la salida humana MUST decir explícitamente que no hay archivos.
- **FR-008**: Los verbos de navegación MUST seguir rechazando el modo `whole` con
  el mismo comportamiento y el mismo código de salida que hoy.
- **FR-009**: La feature MUST NOT crear claves de configuración nuevas, mover refs
  ni tocar el índice o el working tree.

**Del panel del editor (US2)**

- **FR-010**: En modo `whole`, el panel MUST mostrar los archivos del rango con un
  conteo, en el mismo orden que reporta la CLI.
- **FR-011**: El panel MUST obtener esa lista de la salida de la CLI y MUST NOT
  derivarla por su cuenta.
- **FR-012**: Un clic en un archivo MUST abrir su documento del working tree, y
  MUST caer en el diff cuando el archivo no existe ahí.
- **FR-013**: El panel MUST NOT mostrar posición ni controles de navegación en modo
  `whole`.
- **FR-014**: Un panel construido contra el contrato anterior MUST seguir
  funcionando frente a una CLI que ya emite estos registros, sin error visible.

**Del contrato (US3)**

- **FR-015**: El formato porcelain MUST seguir identificándose como v1. Esta feature
  MUST NOT introducir una versión nueva del formato.
- **FR-016**: El contrato de `status --porcelain` MUST quedar consolidado en un
  único documento vigente que describa todos sus registros, sin documentos delta ni
  rótulos de versión distintos de v1 en ninguna parte del repositorio.
- **FR-017**: La afirmación vigente de que en `whole` no hay registros `entry` MUST
  ser reemplazada por la regla nueva, no dejada en contradicción.
- **FR-018**: La salida humana y la salida porcelain MUST reportar el mismo conjunto
  de archivos: el panel no puede mostrar nada que la CLI no muestre.
- **FR-019**: Ambos README MUST reflejar el cambio de comportamiento, en el mismo
  cambio.

**Del walkthrough como contenido revisable (US4)**

- **FR-020**: El orden de lectura de `walk` MUST incluir los archivos bajo
  `.review/` que el rango toca, como archivos sin anotar, al final del orden — el
  mismo tratamiento que cualquier otro archivo del rango que el walkthrough no
  cubre.
- **FR-021**: Las listas de archivos sin cubrir que la herramienta imprime al
  degradar un walkthrough MUST incluirlos también: ninguna superficie que enumere
  los archivos de una review puede seguir escondiéndolos.
- **FR-022**: `walkthrough build` MUST seguir sin proponer una entrada para los
  archivos bajo `.review/`. Es la única superficie donde el filtro se conserva, y
  la razón es que genera lo que el autor anota, no lo que el revisor lee.
- **FR-023**: Una review `walk` iniciada antes de este cambio MUST seguir
  funcionando al retomarse: un total derivado mayor que el registrado MUST NOT
  reportarse como error ni como base movida, en ninguna de las dos superficies.
- **FR-024**: Un PR cuyo único archivo cambiado esté bajo `.review/` MUST seguir
  degradando a `whole` con nota (ningún walkthrough puede anotarse a sí mismo, así
  que este caso es indistinguible del resto de "ninguna entrada guiada interseca
  el rango" — el mismo camino que ya existe) — pero la nota de degradación MUST
  nombrar el archivo (FR-021) y el listado de `whole` resultante MUST mostrarlo
  (FR-001), así que el PR nunca queda invisible aunque no entre en modo `walk`.
  **Revisado en la implementación**: la redacción original de esta spec pedía
  forzar modo `walk` acá; se descartó por chocar con el gate existente que decide
  degradar cuando ninguna entrada guiada interseca el rango — ver
  research.md/tasks.md T014 para el razonamiento completo.

### Key Entities

- **Archivo del rango**: un path que el rango de la review toca, con una posición
  1-based dentro del listado. No tiene estado propio, no se marca como visto y no
  persiste entre invocaciones: se re-deriva cada vez, como el resto de las
  secuencias del proyecto.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: En una review sin walkthrough sobre un PR de N archivos, el revisor
  identifica los N archivos con un solo comando, sin invocar ninguna herramienta
  fuera de `git review`.
- **SC-002**: El conjunto de archivos reportado coincide exactamente —mismo conjunto
  y mismos bytes— con el que reporta git para el mismo rango, en el 100% de los
  casos, incluidos paths con espacios y con bytes no ASCII.
- **SC-003**: En el editor, una review sin walkthrough pasa de cero elementos
  accionables a N archivos abribles en un clic.
- **SC-004**: Ningún consumidor construido contra el contrato anterior deja de
  funcionar: 0 errores visibles en las dos combinaciones de versiones cruzadas.
- **SC-005**: El repositorio no contiene ninguna referencia a una versión del
  formato porcelain distinta de v1, y el contrato de cada verbo se lee completo en
  un solo documento.
- **SC-006**: Una review en modo `whole` sigue sin exponer navegación: 0 posiciones,
  0 controles de anterior/siguiente y 0 claves de configuración nuevas.
- **SC-007**: En los dos modos que listan archivos, la cantidad de archivos del
  rango que la herramienta esconde es 0: ningún archivo del PR queda fuera de toda
  superficie de listado.
- **SC-008**: Ninguna review `walk` iniciada antes del cambio produce un error o un
  aviso nuevo al retomarse.

## Assumptions

- **`whole` no gana cursor.** Recorrer archivo por archivo con posición ya es
  `walk`; la opción de darle cursor a `whole` se evaluó y se descartó por duplicar
  un modo existente.
- **El rango se sigue definiendo como hoy.** La lista se deriva contra el tip fijado
  de la review y el lower bound vigente, sin cambiar ninguna de las dos puntas.
- **El listado son paths, nada más.** No incluye el tipo de cambio de cada archivo
  (agregado / modificado / eliminado) ni conteos de líneas: `walk` tampoco los
  emite, y agregarlos es una decisión separable que esta feature no toma.
- **La salida humana lista todo sin truncar**, siguiendo el precedente de `git
  status`.
- **La consolidación del contrato es documental.** No cambia ningún registro ya
  emitido, ningún código de salida ni ninguna invocación: sólo reúne en un documento
  lo que hoy está partido en dos y corrige la línea que esta feature deja obsoleta.
- **El editor sigue sin derivar estado**, y la lista viaja por la invocación de
  `status --porcelain` que el panel ya hace: no se agrega ninguna invocación nueva.
- **El sandbox de pruebas manuales ya cubre el caso**: tiene una rama en modo
  `whole` sin walkthrough, así que no hace falta material nuevo para probarlo a
  mano.
- **El walkthrough se lista pero no se anota.** De las cuatro superficies donde hoy
  se filtra `.review/`, tres son listados de archivos de la review (el orden de
  lectura y las dos listas de degradación) y cambian; la cuarta es el generador de
  entradas, y se queda como está. Consecuencia asumida: el sidecar aparece siempre
  como archivo sin anotar, y pedir su *why* devuelve vacío — igual que cualquier
  otro archivo sin anotar.
- **El chequeo de working tree limpio no entra en el alcance.** Ese filtro mira el
  estado del working tree, no el rango de la review, y responde otra pregunta
  ("¿hay ediciones sin guardar?"). Sale de la regla por ser otra cosa, no por
  excepción.
- **Casi toda review `walk` gana una entrada.** El walkthrough viaja en el PR por
  diseño, así que el total sube en uno en la mayoría de los casos. Es un cambio de
  comportamiento visible y esperado, no un efecto colateral a mitigar.

## Decisiones tomadas

- **Q1 — ¿el listado excluye los archivos bajo `.review/`?** **No, y en los dos
  modos.** El pedido fue explícito: incluirlos en `whole` y también en `walk`, donde
  el filtro existía sin que la decisión estuviera tomada a la vista. El criterio que
  queda es uno solo y vale para toda superficie que enumere los archivos de una
  review: ningún archivo del rango se esconde. La única excepción es el generador de
  entradas del walkthrough (FR-022), que no enumera archivos para leer sino para
  anotar.
