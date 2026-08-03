# Research: Paridad de información entre la CLI y el panel del editor

El spec dejó resueltas las tres preguntas de alcance (Q1 sin custodia, Q2 el
diffstat como exclusión, Q3 sólo el asunto). Este documento resuelve las
decisiones técnicas que quedan, todas de diseño interno: no se agrega ninguna
dependencia ni herramienta nueva. Se resolvieron leyendo el código existente
(`bin/git-review-verbs/status`, `bin/git-review-lib.sh`,
`vscode-extension/src/cli/porcelain.ts`, `views/panelHtml.ts`), los contratos de
`001` y `002`, y **midiendo el comportamiento de git** donde el diseño dependía
de una garantía que no estaba escrita en ninguna parte.

## Decisión 0 — Qué falta, exactamente

Antes de decidir nada hubo que establecer el inventario del gap, porque el spec
lo describe en prosa. Se corrieron los tres modos contra un repositorio de
juguete y se comparó la salida humana con la porcelain.

| Modo  | Dato que la CLI imprime       | ¿En porcelain? | ¿En el panel? |
|-------|-------------------------------|----------------|---------------|
| todos | origen de la review           | sí (`state`)   | **no**        |
| todos | tip fijado                    | sí (`state`)   | **no**        |
| step  | posición y total              | sí             | sí            |
| step  | identificador del commit      | sí             | sí            |
| step  | **asunto del commit**         | **no**         | **no**        |
| step  | **autor del commit**          | **no**         | **no**        |
| step  | cuerpo del mensaje            | no             | no            |
| step  | diffstat                      | no             | no            |
| step  | pasos con ediciones guardadas | sí (`entry`)   | sí            |
| walk  | todo                          | sí             | sí            |
| whole | **base del rango**            | **no**         | **no**        |

**Hallazgo**: el gap se parte en dos clases con costos muy distintos. El origen
y el tip **ya llegan al panel** y no se dibujan — es un cambio de una función de
render, sin tocar la CLI. Sólo el asunto, el autor y la base necesitan contrato
nuevo. Las dos filas grises (cuerpo y diffstat) son las exclusiones que el spec
registró.

**Consecuencia para el plan**: la Historia 2 se puede entregar casi entera sin
esperar a la CLI, y eso es lo que la hace independientemente testeable como el
spec afirma.

---

## Decisión 1 — El texto libre va en su propio registro, como último campo

**Decisión**: el asunto, el autor y la base **no** se agregan como campos al
final de `state` ni de `entry`. Cada uno viaja en un registro propio con
etiqueta nueva, con el texto libre como **último campo de la línea**:

```
subject<TAB>position<TAB>texto libre hasta el fin de línea
author<TAB>position<TAB>texto libre hasta el fin de línea
base<TAB>texto libre hasta el fin de línea
```

**Rationale**: la razón es una garantía que este proyecto tiene para los paths y
**no** tiene para estos datos, y que se verificó midiendo en vez de asumiendo.

El contrato de `001` puede usar el tab como separador porque un path de git
nunca contiene un tab literal: git cita incondicionalmente cualquier byte de
control, con `core.quotePath` en on o en off (comentario de `changed_paths`,
`bin/git-review-lib.sh:160-173`). Ese razonamiento **no se traslada**: el asunto
de un commit y el nombre de un autor los escribe una persona, no git, y git no
los cita.

Se midió, sobre un repositorio real:

| Byte    | ¿Sobrevive en el asunto?                            | ¿Sobrevive en el nombre del autor?                            |
|---------|-----------------------------------------------------|---------------------------------------------------------------|
| tab     | **sí**, literal                                     | **sí**, literal                                               |
| newline | imposible por definición (`%s` es la primera línea) | **no**: git lo elimina del ident al commitear (`a\nb` → `ab`) |

Es decir: **el separador de campos del formato porcelain puede aparecer dentro
del dato**, y el terminador de registro no. Un campo de texto libre es seguro si
y sólo si es el último de su línea — ahí un tab interno no desplaza nada, porque
no hay nada después que desplazar.

De ahí se sigue todo lo demás:

- **Un solo texto libre por registro.** Asunto y autor no pueden compartir línea:
  el primero de los dos dejaría de ser el último campo.
- **Registros nuevos y no campos agregados.** Poner el asunto al final de `entry`
  lo haría seguro *hoy*, pero convertiría a `entry` en una línea que ya no puede
  crecer: cualquier campo futuro tendría que ir después del texto libre, que es
  precisamente lo que la Decisión 1 de `001` diseñó para evitar. Una etiqueta
  nueva no consume esa capacidad de nadie.
- **Aditividad gratis.** El contrato ya obliga al consumidor a ignorar las
  etiquetas que no reconoce (FR-003 de `002`), y el parser de la extensión ya lo
  hace en su `default:` (`porcelain.ts:144`). Un consumidor viejo no se entera de
  que existen (FR-002, SC-004).

**Alternatives considered**:

- **Escapar el tab dentro del campo.** Rechazada de plano. `porcelain_row` no
  escapa nada por diseño, y agregar escaping obligaría a un des-escapado del
  otro lado: exactamente el punto de normalización extra que `001` existe para
  no crear, y la clase de bug invisible que este proyecto ya sufrió tres veces
  con paths (CRLF, BOM, whitespace).
- **Sustituir el tab por un espacio al emitir.** Rechazada: viola FR-010 (el
  texto se muestra tal como lo escribió su autor) y falsea un dato en silencio,
  que es peor que omitirlo.
- **Campos al final de `state` para la base.** Rechazada por FR-012: `state` ya
  tiene aridad variable según el modo (6 campos en whole, 10 en step, 11 en
  walk), así que un campo "al final" cae en un índice distinto por modo. Un
  consumidor tendría que calcular la posición a partir del modo para leer un
  dato que no depende del modo.
- **Emitir el asunto sólo del commit actual.** Rechazada: FR-007 lo pide para
  toda la secuencia (el selector), y producir todos cuesta lo mismo que producir
  uno (Decisión 2).

---

## Decisión 2 — Producir asuntos y autores con un número constante de procesos

**Decisión**: dos invocaciones de `git log` para toda la secuencia, cada una con
un formato de una sola línea por commit, alineadas con `commits` por número de
línea:

- `git log --reverse --first-parent --no-merges --format=%s <start>..<tip>`
- `git log --reverse --first-parent --no-merges --format='%an <%ae>' <start>..<tip>`

Las mismas flags de recorrido que ya usa `load_step_review_meta` para derivar
`commits`, así que la n-ésima línea de cada salida corresponde al n-ésimo commit
de la secuencia — el mismo idiom de "alinear por número de línea" que el
proyecto ya usa con `sed -n "${step}p"`.

**Rationale**: SC-008 y FR-014 piden que una review de 50 commits no se sienta
lenta, y el riesgo concreto es el bucle ingenuo — un `git log -1` por commit
dentro del `while` que ya recorre las posiciones, o sea 2N procesos. En Windows,
donde el `fork` es emulado y caro (el propio `CLAUDE.md` documenta que por eso
los tests no se corren bajo Git Bash), 2N procesos es la diferencia entre
instantáneo y perceptible. Dos procesos fijos lo vuelven independiente de N.

La alineación por línea es segura **por la medición de la Decisión 1**: ninguno
de los dos formatos puede emitir un newline interno (`%s` es la primera línea
por definición; git elimina el newline del ident al construir el commit). Si
alguno pudiera, la correspondencia línea↔commit se rompería en silencio, que es
el modo de falla que hay que evitar.

**Alternatives considered**:

- **Un solo `git log` con los dos datos separados por un carácter propio**
  (`--format='%an <%ae>%x00%s'`). Rechazada: ahorra un proceso a cambio de
  meter un byte NUL en un pipeline de shell POSIX, donde manipularlo es
  incómodo y desigual entre implementaciones. Dos procesos son baratos y el
  código queda legible.
- **`git rev-list --format`**. Rechazada: intercala una línea `commit <sha>`
  antes de cada registro, así que la salida deja de ser una línea por commit y
  hay que filtrarla — más frágil por nada.
- **Derivarlo del lado de la extensión** con una consulta directa a git.
  Prohibida por FR-001 y por la premisa de `002`; además es justo lo que el
  README de la extensión acaba de dejar asentado como la regla a recordar.

---

## Decisión 3 — Ausencia de registro ≠ campo vacío

**Decisión**: la extensión distingue tres estados por dato, y no dos:

| Estado                      | Cómo se ve en la salida             | Qué muestra el panel          |
|-----------------------------|-------------------------------------|-------------------------------|
| la CLI no lo provee         | el registro no aparece              | lo que muestra hoy, sin hueco |
| el dato existe y está vacío | el registro aparece con campo vacío | la ausencia, como tal         |
| el dato existe              | el registro aparece con contenido   | el contenido                  |

**Rationale**: es FR-004, y sin esto la degradación con una CLI vieja (FR-003,
SC-004) es indistinguible de un commit con asunto vacío. El contrato ya tiene la
regla que lo hace posible —"omitir, nunca en blanco, nunca un centinela"— y el
parser de la extensión ya tiene el precedente exacto: `toOptionalInt`
(`porcelain.ts:74`) existe para que un campo ausente sea ausencia y no un `0`
inventado. Los registros nuevos se leen con la misma disciplina: `undefined`
cuando el registro no llegó, `""` cuando llegó vacío.

**Consecuencia**: **no se sube el requisito mínimo de CLI de la extensión.** El
spec asume que las dos no viajan en lockstep y que convivir con una CLI que no
provee los datos nuevos es un estado normal; degradar es lo consistente con eso,
y subir el mínimo rompería instalaciones que hoy funcionan a cambio de nada.

**Alternatives considered**: emitir siempre el registro, vacío cuando no hay
dato. Rechazada: hace indistinguible "CLI vieja" de "sin dato" para el
consumidor —el registro estaría ausente en un caso y vacío en el otro sólo si el
consumidor ya sabe qué versión corre—, y contradice la regla de omisión del
contrato.

---

## Decisión 4 — Qué ocupa el lugar del identificador en el panel

**Decisión**: en modo step, el **asunto** pasa a ocupar el cuerpo principal de la
entrada (donde hoy está el SHA), y el SHA corto y el autor bajan a la línea de
metadatos que ya lleva el número de posición y las marcas.

**Rationale**: el panel ya tiene una jerarquía establecida por `002` y conviene
respetarla en vez de inventar otra. En walk, el elemento grande es el **path** —
lo que identifica la entrada para una persona— y alrededor van la posición y las
marcas. El equivalente humano de un commit es su asunto: nadie reconoce un
commit por siete caracteres hexadecimales. Poner el asunto donde va el path hace
que los dos modos se lean con la misma gramática, que es lo que permite que el
panel sea uno solo y no dos.

El SHA **no desaparece**: sigue visible en la línea de metadatos. Es el
identificador que el revisor necesita para pasar a la terminal, y quitarlo
rompería la paridad en la dirección contraria a la que esta feature persigue.

**Alternatives considered**:

- **SHA grande, asunto como cuerpo secundario** (donde va el *why* en walk).
  Rechazada: el *why* es la explicación del autor sobre la entrada, y el asunto
  no explica el commit — lo nombra. Ponerlo ahí sugiere una equivalencia con el
  *why* que no existe, y encima deja el elemento grande siendo el dato menos
  legible de los dos.
- **Asunto en la barra superior.** Rechazada: la barra es el chrome que
  sobrevive a la carga y no cambia al navegar (comentario de `renderBar`); el
  asunto cambia en cada paso, así que ahí rompería la única cosa fija del panel.

---

## Decisión 5 — Origen y tip: reemplazar, no acumular

**Decisión**: la barra superior muestra el **origen** de la review en lugar de la
rama, y el tip abreviado junto a él. No se agrega una línea nueva.

**Rationale**: `branch` es siempre `review/<source>` — mostrar los dos es mostrar
el mismo dato dos veces en un sidebar angosto, que es el recurso más escaso del
panel. El origen es además el nombre que el revisor reconoce (es el PR), y el
que la CLI pone primero en su salida humana (`review of <src> (tip <short>)`),
así que reemplazarlo espeja el orden que el producto ya usa.

El tip va **abreviado**, no completo: el contrato lo emite completo (40 bytes) y
la salida humana lo imprime corto. Abreviarlo es presentación, no derivación de
estado — el panel no calcula nada, recorta para mostrar, igual que ya hace con
el des-citado de paths.

**Alternatives considered**:

- **Acumular origen, rama y tip.** Rechazada: satura la barra sin agregar
  información, dado que la rama es derivable del origen por definición.
- **Tip sólo en un tooltip.** Rechazada: FR-008 pide mostrarlo, y un tooltip no
  existe para quien navega con teclado ni para un lector de pantalla — el mismo
  criterio que ya aplicó `002` cuando exigió `aria-label` en los botones sin
  texto.

---

## Decisión 6 — Dónde se prueban los bytes hostiles

**Decisión**: un archivo de tests propio para los bytes hostiles
(`tests/porcelain-bytes.bats`), separado de los tests funcionales de los
registros nuevos, y commits con asunto y autor hostiles agregados al sandbox.

**Rationale**: es la superficie de riesgo nueva de la feature y la única cuyo
modo de falla es invisible — un tab de más no rompe nada a la vista, corre el
campo siguiente. El proyecto ya tiene tres incidentes de esa forma exacta con
paths, todos anotados como notas de release pendientes. Tenerlos en un archivo
propio permite correrlos solos mientras se itera sobre el emisor, que es cuando
importan.

Los casos mínimos, derivados de la medición de la Decisión 1 y de los Edge Cases
del spec: asunto con tab, autor con tab, asunto y autor no ASCII, asunto vacío,
y la verificación de que el registro siguiente **no** se desplazó en ninguno de
esos casos — que es la aserción que de verdad protege FR-011, y no que el texto
"se vea bien".

**Alternatives considered**: sumarlos a `porcelain.bats`. Rechazada sólo por
ergonomía; no hay razón de corrección para separarlos más allá de poder
correrlos aislados.

---

## Decisión 7 — Qué NO se toca

Registrado acá para que la próxima lectura no lo confunda con un olvido:

- **La salida humana.** SC-008 de `001` tiene un test que exige que la porcelain
  no cambie cuando cambia un mensaje humano; esta feature respeta la relación
  inversa. Los datos ya se imprimen, sólo se los expone.
- **El modo walk.** Ya tiene paridad. Lo único que lo alcanza es el encabezado
  común (Decisión 5).
- **`--why`.** Sigue cerrado al modo walk. La respuesta Q3 lo dejó fuera del
  camino por completo: sin cuerpo del mensaje no hay nada que pedirle.
- **La landing** (`docs/index.html`). El cambio no toca ninguna de las cuatro
  cosas que la landing duplica.
- **La consulta directa a git de la extensión** (`readCommitChanges`). Queda
  como está por decisión explícita; el principio general ya quedó asentado en el
  README de la extensión, y qué hacer con esa llamada se decide aparte.
