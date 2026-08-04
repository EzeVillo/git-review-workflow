# Research — Listado de archivos del rango en modo whole

Fase 0 de [plan.md](./plan.md). Cada decisión responde a un punto donde la spec
deja libertad de implementación, y todas se tomaron leyendo el código vigente, no
por analogía.

---

## Decisión 1 — La lista sale de `changed_paths(HEAD, tip)`, igual que en walk

**Decisión**: en `whole`, los archivos del rango se derivan con
`changed_paths "$(git rev-parse HEAD)" "$tip"` — exactamente el mismo par de
extremos y el mismo helper que `walk_reading_order` ya usa para los archivos sin
anotar (`bin/git-review-lib.sh:493`).

**Rationale**: `HEAD` de una review `whole` queda clavado en el lower bound igual
que en `walk` — el diff del PR vive staged y sin commitear encima. Los dos modos
tienen entonces el mismo rango, y `changed_paths` es el punto único de
normalización del lado git (`git diff --name-only` con `core.quotePath=false`). Que
las dos superficies salgan del mismo helper es lo que hace que SC-002 sea
verificable: no hay dos maneras de responder "qué archivos toca esta review".

Cuesta **una** invocación de git por `status`, que es lo que la restricción de
procesos constantes permite.

**Alternatives considered**:

- *Derivarlo de `reviewbase`* (la clave que guarda contra qué ref se armó el
  rango). Rechazado: `reviewbase` es una ref simbólica (`main`), no el punto fijado;
  puede haberse movido desde que la review empezó, y el rango real es contra `HEAD`.
- *`git diff --name-status`, para marcar A/M/D*. Rechazado por alcance: la spec deja
  el tipo de cambio explícitamente afuera (Assumptions), `walk` tampoco lo emite, y
  agregarlo obligaría a decidir cómo se representa en el porcelain — una decisión
  separable que no hace falta tomar ahora.
- *Cachear la lista en config al iniciar la review*. Rechazado: contradice FR-009 y
  el modelo del proyecto, donde toda secuencia se re-deriva y nada se persiste.

---

## Decisión 2 — Un helper `range_files`, no una llamada suelta

**Decisión**: se agrega a `bin/git-review-lib.sh` un helper de una línea
—`range_files <tip> <lower>`, que envuelve `changed_paths` con el orden de
argumentos que usan los verbos— y lo consumen tanto la rama `whole` de `status`
como `walk_reading_order`.

**Rationale**: el mismo cómputo va a quedar invocado desde cuatro lugares
(`status` humano, `status --porcelain`, `walk_reading_order`, y los dos mensajes de
degradación). Sin un nombre compartido, "los archivos de la review" se convierte en
una expresión repetida que puede divergir de a un argumento por vez — que es
exactamente el modo de fallo que la regla de los dos puntos de normalización existe
para evitar. Con helper, el filtro que hoy se quita se quita en **un** lugar
observable.

**Alternatives considered**:

- *Llamar `changed_paths` directo en cada sitio*. Es menos código, pero deja el
  orden de argumentos invertido a la vista (`changed_paths "$2" "$1"`, como está
  hoy en `walk_reading_order`), que ya es una fuente de confusión.
- *Meter el filtrado dentro de `changed_paths`*. Rechazado: `changed_paths` es el
  punto de normalización, y cargarle una política de qué archivos se muestran lo
  convierte en dos cosas a la vez.

---

## Decisión 3 — Registro `entry` existente, sin campos nuevos, sin versión nueva

**Decisión**: `whole` emite `entry<TAB>position<TAB>path` y nada más. No se crea
una etiqueta nueva, no se agregan campos a `state`, y el formato sigue siendo v1.

**Rationale**: el registro `entry` ya significa "un elemento de la colección que
esta review enumera, en su orden", y su forma ya varía por modo — `walk` agrega dos
campos, `step` uno, y el grupo que no aplica se omite entero. `whole` sin ninguno de
los dos grupos es el caso base del registro, no un caso especial.

La compatibilidad se verificó en el parser real, no se supuso:
`parsePorcelain` (`vscode-extension/src/cli/porcelain.ts:177`) acumula registros
`entry` en cualquier modo y sólo consulta los campos extra cuando el modo es `walk`
o `step`. Un panel construido contra el contrato anterior recibe entonces N entradas
sin flags y no rompe; en `openEntry` caen en el `return` silencioso de la línea 25
porque su `id` llega como string. Se degrada a "no pasa nada", que es FR-014.

**Alternatives considered**:

- *Una etiqueta nueva (`file`)*. Rechazado: dos etiquetas para el mismo concepto
  —un elemento enumerado de la review— obliga a todo consumidor a manejar las dos, y
  el orden de lectura de `walk` y la lista de `whole` son la misma clase de cosa.
- *Subir el formato a v2*. Rechazado explícitamente por el pedido, y sin sustento
  técnico: el cambio es aditivo bajo la misma regla de "ignorá lo que no conocés"
  que el formato declara desde `001`.

---

## Decisión 4 — En `whole` el `id` de una entrada es un path, y el parser lo trata como tal

**Decisión**: `parsePorcelain` construye el `id` con `toPathRef` cuando el modo es
`walk` **o** `whole`, y lo deja como string sólo en `step`.

**Rationale**: hoy la condición es `mode === "walk"`, y es la única línea del parser
que quedaría incorrecta si no se toca: el `id` de `whole` es un path, con las mismas
propiedades hostiles (espacios, bytes no ASCII, y el caso extremo del path citado
por git). Tratarlo como string haría que `openEntry` no lo reconozca como abrible —
justamente el `return` silencioso que salva a los consumidores viejos y que no debe
sobrevivir en el nuevo.

La regla queda enunciable en una línea: **el `id` es un SHA sólo en `step`; en los
otros dos modos es un path**.

**Alternatives considered**:

- *Deducirlo del contenido del campo* (¿parece un SHA?). Rechazado: un archivo puede
  llamarse como un SHA, y adivinar el tipo de un campo por su forma es exactamente lo
  que el contrato evita al hacer que el modo se lea primero y decida la aridad.

---

## Decisión 5 — El panel dibuja la lista, no la esconde detrás de un selector

**Decisión**: en `whole`, el panel reemplaza el estado vacío actual
(`panelHtml.ts:637`, *"This review has no walkthrough…"*) por la lista de archivos
con su conteo. Cada fila abre el archivo con un clic. El modelo gana un array de
archivos; `entryCount` ya existía y se reusa para el conteo.

**Rationale**: el problema que la feature ataca es una vista vacía. Dejar la lista
detrás de un botón que abre un selector mantiene la vista vacía y agrega un clic —
resuelve la mitad visible del problema. Además el panel ya tiene el lugar libre: es
el espacio que en `step` y `walk` ocupa la entrada actual, y `whole` no tiene
entrada actual.

El selector existente (`pickEntry`) se mantiene para lo que ya hace y se le habilita
`whole` como un caso más, sin ser la superficie principal.

**Alternatives considered**:

- *Sólo el conteo en el panel, la lista en el `QuickPick`*. Más barato (no hay que
  llevar N paths al webview) pero no cumple FR-010, y deja el panel casi tan vacío
  como hoy.
- *Un `TreeView` aparte para los archivos*. Rechazado: duplica la superficie del
  panel y obliga a mantener dos vistas sincronizadas contra el mismo `status`.

---

## Decisión 6 — El filtro del sidecar se quita en tres de sus cuatro apariciones

**Decisión**: se quita `grep -v '^\.review/'` de `walk_reading_order`
(`git-review-lib.sh:493`) y de las dos listas de archivos sin cubrir que se imprimen
al degradar un walkthrough (`start:348`, `compare:163`). **Se conserva** en
`walkthrough:177`, el generador de entradas.

**Rationale**: las tres primeras responden "qué archivos tiene esta review para
leer", y ahí el criterio nuevo es uno solo: ninguno se esconde. La cuarta responde
"qué entradas debería escribir el autor", que es otra pregunta — pedirle un *why*
sobre el archivo donde escribe los *why* es circular, y el comentario que ya está en
esa línea (*"a walkthrough never annotates .review/"*) lo dice.

Consecuencia asumida y declarada en la spec: el sidecar aparece **siempre** como
archivo sin anotar, y su `--why` devuelve vacío — el mismo comportamiento que
cualquier otro archivo sin anotar, no un caso especial.

Hay una quinta aparición, `walkthrough:122`, que **no entra**: filtra sobre `git
status --porcelain` para decidir si el working tree está sucio. Mira otra cosa
(estado del working tree, no el rango de la review) y responde otra pregunta.

**Alternatives considered**:

- *Quitarlo en las cuatro*. Rechazado por circular; nadie pidió que el walkthrough
  se anote a sí mismo.
- *Quitarlo sólo en `walk_reading_order`*. Deja las dos listas de degradación
  contradiciendo al orden de lectura sobre el mismo rango, en la superficie donde el
  usuario está justamente tratando de entender qué quedó sin cubrir.

---

## Decisión 7 — La compatibilidad de las reviews `walk` en curso ya está cubierta, y se fija con un test

**Decisión**: no se agrega ninguna migración. Se agrega un test que fija el
comportamiento como requisito (FR-023).

**Rationale**: verificado en el código, no supuesto. El aviso de base movida se
calcula como `total < recorded` (`panelModel.ts:312`), y el comentario de las líneas
104-108 documenta que la comparación es asimétrica **precisamente** porque este
repositorio ya atravesó esta misma migración cuando los archivos sin anotar entraron
a la secuencia. Del lado de la CLI, `walk_range_error` sólo dispara cuando el total
derivado **cae** por debajo del registrado. Una secuencia que crece no activa
ninguno de los dos.

Lo que hoy es una propiedad correcta pero accidental para este caso pasa a ser un
requisito con test propio: si alguien "arregla" la asimetría convirtiéndola en
`!==`, la suite lo dice.

**Alternatives considered**:

- *Reescribir `reviewwalkcount` al detectar la diferencia*. Rechazado: sería
  escritura de config en un verbo de lectura, y el valor registrado tiene sentido
  propio (contra qué se comparó al iniciar).

---

## Decisión 8 — El contrato consolidado vive donde ya está, y el delta se elimina

**Decisión**: `specs/001-contrato-porcelain/contracts/status-porcelain.md` pasa a ser
**el** contrato vigente del verbo: absorbe entero el contenido de
`specs/003-paridad-cli-panel/contracts/status-porcelain-v2.md`, incorpora los
cambios de esta feature, y el archivo `v2` se elimina. Las cuatro referencias que lo
nombran se reapuntan.

**Rationale**: el pedido es un documento por verbo. Crear el consolidado en
`004/contracts/` produciría un tercer documento y dejaría los otros dos como trampas
para el próximo lector — el problema exacto que se quiere cerrar. El de `001` es
además el que todo el código ya referencia.

El rótulo `v2` era engañoso desde el principio: el propio documento dice *"Sigue
siendo formato porcelain v1"*. No se está bajando ninguna versión; se está borrando
una que nunca existió.

Se corrige además la línea que esta feature deja falsa: *"En `whole` no hay
registros `entry` en absoluto"* (`status-porcelain.md:101`).

**Alternatives considered**:

- *Mover el contrato fuera de las carpetas numeradas* (a `docs/` o `contracts/` en
  la raíz). Es probablemente el destino correcto a largo plazo, pero es una
  reorganización del repositorio que nadie pidió y que tocaría más referencias de las
  que esta feature justifica.

---

## Decisión 9 — Formato de la salida humana de `whole`

**Decisión**: bajo la línea de `mode`, una línea por archivo con su posición, y una
línea explícita cuando no hay ninguno. Sin truncar.

**Rationale**: la referencia es `git status`, que lista todo y no esconde nada
detrás de un "y 40 más". El proyecto ya toma esa referencia para justificar por qué
los archivos sin anotar aparecen en el orden de lectura. La posición se imprime
porque es la misma que emite el porcelain, y verlas coincidir es lo que hace
verificable FR-018 a ojo.

El caso vacío se dice con palabras: una lista en blanco sin explicación es
indistinguible de un error.

**Alternatives considered**:

- *Reusar el formato de `banked` de `step`* (todo en una línea, separado por
  espacios). Rechazado: los paths pueden contener espacios, así que una línea sola
  es ambigua justo en el caso hostil.

---

## Decisión 10 — En `whole` no se agrega guard de rango

**Decisión**: si el usuario commitea encima de la base y `HEAD` se mueve, la lista
de `whole` se achica en silencio. No se agrega el exit `3` que `step` y `walk`
tienen.

**Rationale**: el exit `3` existe para un cursor que quedó fuera de rango, y `whole`
no tiene cursor: no hay nada que pueda quedar fuera de nada. Inventar una condición
de error nueva para un modo que no la tenía es agregar comportamiento que nadie
pidió, y contradice el "sin estado persistido" de la spec — para detectar que la
lista se achicó habría que haber registrado su tamaño al iniciar.

**Alternatives considered**:

- *Registrar un `reviewcount` para `whole` y avisar si difiere*. Rechazado: es
  exactamente la clave de configuración nueva que FR-009 prohíbe, y reintroduce por
  la ventana el estado que la Decisión 1 dejó afuera.
