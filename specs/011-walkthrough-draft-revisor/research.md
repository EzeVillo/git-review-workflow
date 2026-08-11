# Research: Walkthrough del revisor (draft local)

**Feature**: `011-walkthrough-draft-revisor` | **Fase**: 0 | **Fecha**: 2026-08-09

Decisiones de diseño previas a la implementación. Cada una registra qué se
eligió, por qué, y qué alternativas se descartaron.

## Decisión 1 — Dónde vive el borrador

**Decisión**: en el directorio de datos de git del working tree,
`$(git rev-parse --git-dir)/review-walkthrough/<src>.md`, con `<src>` el nombre
de la rama bajo review (crea subdirectorios cuando el nombre trae `/`, igual que
las refs).

**Rationale**: es el idiom que git ya usa para archivos de trabajo que el
usuario edita pero que no son contenido del repo — `COMMIT_EDITMSG`,
`MERGE_MSG`, `rebase-merge/git-rebase-todo`. Da las cuatro propiedades que pide
FR-003 de una sola vez, sin maquinaria: es un path real que cualquier editor o
agente abre y guarda; no aparece en `git status`; `start` no lo ve como árbol
sucio; `finish` no puede extraerlo a `review-fixes/` porque no está en el
árbol. Al vivir en el gitdir del working tree, además, es correcto por
construcción bajo `git worktree`: cada worktree tiene el suyo.

**Alternativas descartadas**:

- *Un blob apuntado por una ref (`refs/review-walkthrough/<src>`)*: encaja con
  `refs/review-edits/`, pero un blob no se edita. Habría que exportarlo a un
  temporal, dejar que el usuario lo edite y re-importarlo en cada iteración del
  ciclo de validación — todo para conseguir lo que un archivo ya da.
- *El working tree (`.review/walkthrough.md` sin commitear)*: es exactamente la
  pared que la feature viene a tirar abajo.
- *Fuera del repo (directorio de config del usuario)*: se desvincula del
  repositorio, sobrevive a `clean` sin que nadie lo recoja, y rompe el modelo de
  estado del proyecto —todo el estado de review vive en los datos de git del
  repo— sin ninguna ventaja a cambio.

## Decisión 2 — Cómo entra el borrador al sistema de lectura

**Decisión**: `walk_read` gana la resolución de precedencia (borrador local
primero, sidecar commiteado después) y un helper `walk_use_draft <src>` fija el
`<src>` de contexto. Los cargadores de contexto que ya resuelven `src`
—`load_walk_review_meta` y `load_step_review_meta`— lo llaman por su cuenta, de
modo que **todo verbo con review activa lo obtiene sin tocarlo**; los pocos que
resuelven `src` por fuera de un review (`start`, `compare`,
`emit_reading_offers`, el propio `walkthrough draft`) lo llaman explícitamente.

**Rationale**: `walk_read` ya es *el* punto único por donde el contenido del
walkthrough entra a los lectores — y por eso es donde vive la normalización de
CR y BOM. Poner ahí la precedencia hace que las trece funciones que cuelgan de
ella (`walk_parse`, `walk_body`, `walk_preamble`, `walk_is_key`,
`walk_count_keys`, `walk_is_annotated`, `walk_entry_fields`, `walk_why`,
`walk_sequence`, `walk_reading_order`, `walk_keys_order`, y por encima de ellas
`next`/`prev`/`status --why`/`compare`) funcionen sobre un borrador **sin una
línea de cambio**, y garantiza que ninguna superficie pueda leer un walkthrough
distinto del que lee otra.

El contexto va por variable y no por parámetro nuevo porque `walk_read` recibe
un commit-ish, no una rama, y sus once llamadores intermedios tampoco conocen la
rama: propagar un segundo argumento obligaría a cambiar la firma de toda la
cadena. La variable se lee siempre como `${walk_draft_src:-}`, que es seguro
bajo `set -u`.

**Riesgo asumido y su mitigación**: un verbo que resuelva `src` por su cuenta y
se olvide de llamar `walk_use_draft` leería el sidecar mientras otro lee el
borrador — la clase de divergencia invisible que este proyecto persigue. Se
mitiga en dos frentes: (a) los cargadores de contexto lo hacen por todos, así
que la lista de llamadores explícitos es corta y cerrada; (b) un test de
integración recorre las superficies de una misma review (`status`, `status
--why`, `next`, `preview`) y afirma que todas reportan el contenido del
borrador, no el del autor.

**Caso especial: `compare`.** Es el único lector que no trabaja con una rama:
llama `walk_read` con un commit-ish arbitrario
([compare:168](../../bin/git-review-verbs/compare:168)). Resolución (FR-011a):
`compare` fija el contexto con `walk_use_draft` cuando su argumento **es** una
rama bajo review y existe borrador para ella; cuando le pasan SHAs o tags, no lo
fija y la lectura cae al walkthrough del autor, que es la única referencia que
existe para una revisión suelta. Sin esto, la misma rama se leería en dos
órdenes distintos según el comando — exactamente la divergencia que la Decisión 2
existe para prevenir.

**Alternativas descartadas**:

- *Segundo parámetro `<src>` en toda la cadena*: más explícito, pero toca once
  firmas y sus llamadores, y cualquier olvido produce el mismo fallo silencioso
  que la variable — sin ahorrar el test que lo detecta.
- *Nombrar el borrador por tip en vez de por rama*: haría a `walk_read` puro
  sobre el commit, pero el borrador moriría en cada push del autor, que es justo
  cuando más caro sale rehacerlo.

## Decisión 3 — Superficie de la CLI

**Decisión**: un subcomando más del verbo existente:

```sh
git review walkthrough draft [--local | --offline] [--delta] [--force] [--] [<branch>]
git review walkthrough draft --build [--local | --offline] [--delta] [--] [<branch>]
```

**Rationale**: espeja el par `init` / `build` que el autor ya conoce, dentro del
mismo verbo, en vez de estrenar un verbo de primer nivel. `<branch>` posicional
con default a la rama actual y `--` para cerrar el parseo son los mismos idioms
de `start`, que es el comando con el que el revisor lo va a usar en pareja. Los
flags de origen y rango existen porque el borrador tiene que listar exactamente
los archivos que la review va a cubrir (FR-002), y ese conjunto depende del
origen y del rango elegidos — el asistente los decide antes de la forma de
lectura, así que están disponibles cuando hacen falta.

**Alternativas descartadas**:

- *Verbo propio `git review draft`*: agrega superficie de primer nivel para algo
  que es una variante de autoría de walkthrough; el dispatcher ya tiene 15
  verbos.
- *Flag de `init` (`walkthrough init --draft`)*: `init` refuerza en su salida y
  en sus mensajes que escribe el sidecar del PR; un flag que cambia el destino
  del archivo y el rol de quien lo escribe es un comando distinto disfrazado.

## Decisión 4 — Ciclo de vida, espejando el de las ediciones

**Decisión**: el borrador sigue exactamente el recorrido que ya siguen las
ediciones bancadas de `--step`:

| Momento | Ediciones (hoy) | Borrador (esta feature) |
| --- | --- | --- |
| Review activa | `refs/review-edits/<src>/<n>` | `<gitdir>/review-walkthrough/<src>.md` |
| `save` | mueve a `refs/review-saved-edits/` | mueve a `<gitdir>/review-saved-walkthrough/<src>.md` |
| `continue` | devuelve al namespace activo | devuelve al namespace activo |
| `clean` | poda sólo el namespace activo | ~~poda sólo el namespace activo~~ → **no toca ninguno** (revisado, ver abajo) |
| `forget --saved` | borra el guardado | borra el guardado |
| `forget --draft` | — | borra el activo (`<branch>` o `--all`) |

**Rationale**: es la respuesta a la clarificación de sesión (FR-008a) y, sobre
todo, no estrena una regla. El revisor que ya entendió que pausar pone sus
ediciones a salvo de `clean` no tiene que aprender nada nuevo, y el que no lo
sabe aprende una sola regla en vez de dos. `save` **mueve** en lugar de copiar,
igual que hace con las refs, para que no queden dos borradores divergentes de la
misma rama.

**Alternativas descartadas**:

- *Que `clean` nunca toque borradores*: los de PRs cerrados se acumularían sin
  que nada los recoja, y `clean` dejaría de dejar el repositorio limpio.
- *Que `clean` los borre siempre*: retomar una review pausada devolvería al diff
  completo sin que el revisor haya pedido perder nada — la sorpresa que el
  proyecto ya evitó al crear `refs/review-saved-edits/`.

**Revisión posterior a la implementación (la alternativa descartada era la
correcta).** Podar «todo borrador cuya `review/<src>` no exista» destruye en
silencio el borrador del **primer paso del flujo documentado** —
`walkthrough draft` → completarlo → `--build` → `start` —, donde todavía no
existe ninguna review para reclamarlo: un `git review clean` en esa ventana
borraba trabajo escrito a mano sin decir una palabra, y `--keep-fixes` (cuyo
contrato es *borrá menos*) también lo hacía. La corrección es la que este
proyecto ya aplica a los otros dos estados persistentes: `clean` borra ramas y
refs de sesión, y `forget` descarta lo que sobrevive a la review. El borrador es
prosa del revisor, no un artefacto de la máquina, así que va del lado de
`forget` — y la acumulación, que era el motivo para descartar esta opción, la
resuelve `forget --draft --all`. De paso desaparece el único uso de `find(1)` de
`bin/` (`-empty`/`-delete`, fuera de POSIX): borrar por nombre es un `rm -f`.

## Decisión 5 — Cómo lo reportan los offers

**Decisión**: dos ids nuevos en el registro `offer` de `config --porcelain`,
emitidos con rank `available` inmediatamente después de `keys` y antes de
`step`:

- `draft` — no hay borrador para esta rama y se puede armar uno.
- `draft-resume` — ya hay un borrador empezado para esta rama.

Se emite **como mucho uno de los dos**, y `draft` no se emite cuando el tip trae
walkthrough del autor utilizable (FR-016a). `draft-resume` sí se emite en ese
caso: si el revisor ya tiene borrador propio, la review va a usarlo igual.

**Rationale**: el contrato de offers ya define exactamente esta forma —"la CLI
es la única fuente de viabilidad, el cliente nunca adivina"— y agregar ids es
aditivo por diseño: un cliente viejo que no los conoce los ignora. Dos ids en
lugar de uno porque el cliente necesita distinguir *empezar* de *continuar* para
elegir el texto, y derivarlo por su cuenta significaría mirar el borrador, que
es precisamente lo que el contrato prohíbe.

**Alternativas descartadas**:

- *Un id `draft` más un campo de estado*: cambia la forma del registro (`offer
  <id> <rank>`) para todos los ids; dos ids no cambia nada.
- *Reutilizar `walk` con un rank nuevo*: rompería a los clientes publicados, que
  mapean `walk` directo al layout de walk.

## Decisión 6 — Cómo se marca una review que corre sobre un borrador

**Decisión**: un **registro de presencia** en `status --porcelain`, no un campo
nuevo en el registro `state`.

**Rationale**: hay precedente exacto en el mismo archivo — el submodo keys-only
se reporta así, como registro de presencia, en lugar de ensanchar `state`
([status:252](../../bin/git-review-verbs/status:252)). Ensanchar `state`
agregaría un campo al final de una línea que los clientes publicados parsean por
posición; un registro propio es inequívocamente aditivo y no puede desalinear
nada. En la salida legible, una marca junto al modo (`mode walk (draft)`), y en
el panel un badge discreto que **no** requiere tocar `panel_layout` porque es
texto dentro de un bloque existente.

## Decisión 7 — Coste en procesos (restricción de Windows)

**Decisión**: la resolución de precedencia se hace con un test de archivo del
shell (`[ -f ]`), y cuando hay borrador se lee por redirección en vez de `git
show`.

**Rationale**: el proyecto tiene una restricción dura y medida — crear un
proceso cuesta ~50 ms bajo Git Bash en Windows contra ~1 ms en Linux, y ya hubo
regresiones de segundos por añadir procesos por entrada. `[ -f ]` es un builtin:
cero procesos. Y el camino con borrador **ahorra** el `git show` que hoy paga
cada `walk_read`, así que la feature no puede degradar la latencia del panel;
en el peor caso la mejora. El chequeo de existencia para los offers reusa el
mismo test, sin procesos nuevos en `config --porcelain`.

## Decisión 8 — Qué NO se toca

- **El esqueleto no cambia.** Su texto ya está escrito para "quien anota este
  PR" y no depende de que sea el autor; reescribirlo por rol duplicaría un
  bloque largo de instrucciones con dos versiones que se desincronizan.
- **La validación no se duplica.** `--build` reusa el cuerpo de validación de
  `build` (placeholders, drift, duplicados, marca `> key` con valor,
  renumerado); lo único que cambia es de qué archivo lee y contra qué rango
  compara.
- **`panel_layout` no se toca**, y por lo tanto tampoco
  `check-client-product-surface.mjs` en su parte de layout ni
  `PanelLayoutContractTest`. La feature no agrega acciones ni bloques.
