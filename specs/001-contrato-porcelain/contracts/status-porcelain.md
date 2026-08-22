# Contrato: `git review status --porcelain` / `git review status --why <path>`

Formato porcelain v1: texto plano, una línea por registro, campos separados
por tab (`\t`). Primer campo = etiqueta de tipo de registro. Cuando hay un
path o un id, va **inmediatamente después de la etiqueta** — nunca al final —
para que los campos agregados en el futuro sean siempre aditivos (ver
`research.md`, Decisión 1). Un consumidor debe ignorar cualquier campo extra
al final de una línea de un tipo que ya conoce, y cualquier línea cuya
etiqueta no reconozca.

Nada de esto imprime al canal de errores (FR-019): diagnósticos y notas siguen
sólo en stderr, igual que hoy.

## Invocación

```
git review status --porcelain
```

Válido únicamente dentro de una review activa (HEAD en `review/*`) — no hay
modo "vista previa" fuera de una review (spec, Q1 = A). Cero mutación de
config, refs o working tree (FR-022).

### Exit codes

| Code | Significado                                                                      |
|------|----------------------------------------------------------------------------------|
| `0`  | había una review activa; se emitió al menos el registro `state`                  |
| `1`  | error: metadata ausente o corrupta, no es un repositorio git, uso inválido       |
| `2`  | HEAD no está en una review activa                                                |
| `3`  | el cursor quedó fuera del rango vigente porque HEAD se movió de la base (FR-023) |

`3` es la condición recuperable: la review existe y su metadata está sana, pero
el usuario commiteó encima de la base y la secuencia derivada se achicó. No se
emite ningún registro; el diagnóstico accionable va a stderr, como hoy. Un
consumidor debería ofrecer el arreglo (`git reset --soft`), no reportar un
error genérico. `1`, en cambio, no tiene acción del lado del usuario.

Una rama `review/*` creada a mano, sin `reviewsource`/`reviewtip`, es `1` y no
`2`: HEAD está parado en algo que dice ser una review y el usuario necesita
enterarse. `2` significa "acá no hay nada que mostrar, y eso es normal".

**Los códigos `2` y `3` no son exclusivos de `--porcelain` ni de `status`**
(FR-017, FR-023): valen igual para el `status` humano y para cualquier otro
verbo que detecte la misma situación — `2` en `abort`, `finish`, `preview`,
`save` y `status`; `3` en `status`, `next` y `prev`. Un mismo hecho, un mismo
código, sin importar quién lo detecte ni si se pidió salida porcelain.

## Registro `state` (exactamente una línea, siempre la primera)

```
state<TAB>branch<TAB>source<TAB>tip<TAB>mode<TAB>walkthrough[<TAB>position<TAB>total<TAB>recorded<TAB>current[<TAB>essential]]
```

- `branch`: nombre de la rama `review/<x>` actual.
- `source`: origen revisado (`branch.<x>.reviewsource`).
- `tip`: SHA completo fijado (`branch.<x>.reviewtip`).
- `mode`: `whole` | `step` | `walk`.
- `walkthrough`: `none` | `applied` | `degraded` (ver `research.md`, Decisión 4).
  Siempre `none` en modo `step` — el campo es posicional, así que no se omite.
- `position`, `total`, `recorded`, `current`: presentes sólo si `mode` es `step`
  o `walk`. `current` es el SHA corto del commit (step) o el path (walk).
- `total`: el total **derivado ahora**. Es siempre igual a la cantidad de líneas
  `entry` de esta misma salida.
- `recorded`: el total **registrado al iniciar** la review (`reviewcount` /
  `reviewwalkcount`). En reposo `total == recorded`; si difieren, la base se
  movió y el consumidor puede avisarlo aunque el cursor siga en rango (con el
  cursor ya fuera de rango la invocación no llega acá: sale con `3`).
- `essential`: presente sólo si `mode = walk`. `1` o `0`.

Ejemplo, modo walk, entrada 3 de 7, esencial:

```
state	review/feat-x	origin/feat-x	a1b2c3d4e5f6...	walk	applied	3	7	7	src/core.ts	1
```

Ejemplo, modo whole, sin walkthrough:

```
state	review/feat-x	origin/feat-x	a1b2c3d4e5f6...	whole	none
```

Ejemplo, modo step, commit 2 de 9:

```
state	review/feat-x	origin/feat-x	a1b2c3d4e5f6...	step	none	2	9	9	9fe1c0d
```

## Registros `entry` (cero o más, uno por posición de la secuencia o del listado)

```
entry<TAB>position<TAB>id[<TAB>essential<TAB>annotated|<TAB>banked]
```

- `position`: 1-based. En `step`/`walk`, el mismo orden que recorren
  `next`/`prev`. En `whole` no hay cursor: es sólo la posición dentro del
  listado, un inventario y no una secuencia — el registro `state` de `whole`
  sigue sin `position`/`total`/`recorded`/`current`.
- `id`: un SHA corto de commit sólo en modo `step`. En los otros dos modos
  —`walk` y `whole`— es un path, con las mismas reglas de bytes que cualquier
  otro path de este contrato (ver más abajo).
- En modo walk, dos campos finales: `essential` (`1`/`0`) y `annotated`
  (`1`/`0`). En modo step, uno solo: `banked` (`1`/`0`, existe
  `refs/review-edits/<src>/<position>`). En modo **whole ninguno de los dos
  grupos**: el registro termina en el `id`. El grupo que no aplica al modo se
  **omite** entero, no se emite vacío (Acceptance Scenario 2 de US1).
- `annotated`: `0` cuando el path cambia en el rango de la review pero no
  tiene entrada propia en el walkthrough — la secuencia lo agrega al final del
  orden de lectura en vez de omitirlo, para que un review no llegue al final
  con archivos del PR que el reviewer nunca vio (el precedente es `git
  status`, que no esconde los untracked). `total` cuenta estas posiciones
  igual que las guiadas. El archivo del propio sidecar (`.review/`) entra en
  esta categoría igual que cualquier otro: un walkthrough nunca se anota a sí
  mismo, así que un review con walkthrough committeado siempre tiene al menos
  una posición sin anotar.
- En `whole`, `entry` lista los archivos que el rango toca — el mismo dato que
  `walk` deriva para su orden de lectura, sin guía ni cursor. Un rango
  vacío produce cero registros `entry` y exit `0`, nunca un error.

Ejemplo (walk, 3 entradas, la segunda esencial, la tercera sin anotar):

```
entry	1	src/a.ts	0	1
entry	2	src/b.ts	1	1
entry	3	src/c.ts	0	0
```

Ejemplo (whole, 2 archivos):

```
entry	1	README.md
entry	2	src/quoting.ts
```

## Registros `file` (cero o más; sólo modo `step`)

```
file<TAB>position<TAB>path
```

Inventario de **archivos del commit actual** (el de `state.current` /
`reviewstep`), no de todo el rango:

- Sólo se emiten en modo `step`. En `walk` y `whole` no hay ninguna línea
  `file` (en whole la lista de archivos del rango ya son los `entry`).
- `position`: 1-based **dentro de ese commit**, independiente de
  `reviewstep` / de la posición del commit en la secuencia.
- `path`: un path por línea, en el orden de git, con las mismas reglas de
  bytes que cualquier otro path de este contrato (ver más abajo). Fuente:
  `commit_files` → `git diff-tree --name-only` con `core.quotePath=false`.
- Un commit que no toca archivos (p. ej. vacío) produce **cero** registros
  `file` y exit `0`, nunca un error.
- `state.total` sigue contando solo las líneas `entry` (commits). Los
  registros `file` no entran en ese total.

Los clientes usan esta lista para dibujar el panel (una fila por path). El
patch / los lados del diff **no** van acá: cada fila se abre después con git
/ el host del editor.

Ejemplo (step en el commit 2, que toca `b.txt` y agrega `src/c.txt`):

```
state	review/feat-x	origin/feat-x	a1b2c3d4…	step	none	2	2	2	9fe1c0d
entry	1	c1short	0
entry	2	9fe1c0d	0
…
file	1	b.txt
file	2	src/c.txt
```

## Paths (FR-015, FR-016)

Todo path se emite **byte a byte tal como lo devuelve `changed_paths`**, que es
`git diff --name-only` con `core.quotePath=false`. En concreto:

- Un path con espacios, acentos o cualquier otro byte no ASCII sale literal,
  sin comillas ni escapes. Los límites del campo los marca el tab, no el
  espacio: un path de git nunca contiene un tab literal, porque git cita
  incondicionalmente cualquier byte de control (ver el comentario de
  `changed_paths` en `bin/git-review-lib.sh:160-173`).
- Un path que contiene `"` o `\` sale **citado por git**, con las comillas y
  los escapes que git mismo produce. El contrato no desarma esa cita: hacerlo
  obligaría a reimplementar el escaping de git y crearía el tercer punto de
  normalización que esta feature existe para evitar. Un consumidor que necesite
  el nombre crudo aplica las mismas reglas que aplicaría a cualquier salida de
  git (la señal es la comilla inicial). Es un caso extremo: esos dos bytes son
  ilegales en un path de Windows.

Vale igual para `state.current` en modo walk, el `id` de `entry` en walk o
whole, y el `path` de `file` en step: son el mismo dato de la misma familia de
helpers (`changed_paths` / `commit_files`), sin importar el modo.

## Registros `subject`, `author` y `base`: texto escrito por una persona

```
subject<TAB>position<TAB>asunto
author<TAB>position<TAB>autor
base<TAB>base
```

A diferencia de un path, el contenido de estos tres registros lo escribe una
persona, no git, y **puede contener el separador de campos** (un tab):

| Byte    | ¿Puede aparecer en el asunto? | ¿En el nombre del autor?                   |
|---------|-------------------------------|--------------------------------------------|
| tab     | **sí**                        | **sí**                                     |
| newline | no (`%s` es la primera línea) | no (git lo elimina del ident al commitear) |

De ahí la regla, que aplica a los tres y a cualquier registro futuro con texto
libre:

> **El texto libre es siempre el último campo de su registro, y hay a lo sumo
> uno por registro.** Se emite byte a byte, sin escapar, sin citar y sin
> sustituir nada.

Un consumidor lee ese campo como *"todo lo que sigue al N-ésimo tab, hasta el
fin de línea"* — no como *"el campo N-ésimo"*. Es la misma disciplina que este
contrato ya aplica a los paths, por el motivo opuesto: allá el separador no
puede aparecer en el dato, acá sí, y por eso el dato va donde no hay nada que
desplazar. Corolario de diseño: estos registros **no admiten campos nuevos al
final**. Lo que haya que agregar en el futuro va en un registro propio.

**`subject`** — emitido sólo en modo `step`, una vez por posición de la
secuencia, en el mismo orden que los registros `entry`. `asunto` es la primera
línea del mensaje del commit, tal cual: puede contener tabs, puede estar vacío
(un commit cuyo mensaje no tiene primera línea), nunca contiene un newline.

**`author`** — emitido sólo en modo `step`, una vez por posición, en el mismo
orden. `autor` es el nombre y correo en la forma `Nombre <correo>`, tal como
los muestra la salida humana; puede contener tabs, nunca un newline. Es el
autor, no quien commiteó.

**`base`** — emitido sólo en modo `whole`, y sólo si hay una base registrada
(`branch.<rama>.reviewbase`). Sin base, el registro se omite entero — omitir,
nunca en blanco, la misma regla que el resto del contrato. Registro único, sin
posición: la base es de la review, no de una entrada.

Ejemplo completo (modo step, 2 commits, el primero con ediciones):

```
state	review/feat-x	feat-x	a1b2c3d4e5f6…	step	none	1	2	2	6bce6d1
entry	1	6bce6d1	1
entry	2	f307e69	0
subject	1	feat: exponer el asunto en porcelain
subject	2	test: cubrir los bytes hostiles
author	1	Eze Villo <ezevillodev@gmail.com>
author	2	Eze Villo <ezevillodev@gmail.com>
```

El orden entre grupos de registros no es significativo; el orden **dentro** de
un grupo sí lo es, y coincide con el de `entry`. Un consumidor debe emparejar
por `position`, nunca por orden de aparición.

Ejemplo (modo whole, con base y archivos):

```
state	review/fix-quoting	fix-quoting	1a2b3c4d5e6f…	whole	none
entry	1	README.md
entry	2	src/quoting.ts
base	main
```

## Registro `readonly` (cero o una línea)

```
readonly
```

Sólo cuando la review es de **solo lectura** (`branch.review/<x>.reviewreadonly=1`,
hoy: `git review compare`). Sin campos: la presencia del registro es el dato.
**Omitido** en cualquier otra review (nunca una línea en blanco, nunca un
`readonly\t0`). Un consumidor viejo ignora la etiqueta (FR-003).

`finish` se niega en estas reviews; el consumidor debería ocultar o deshabilitar
esa acción y dejar `abort` / `clean` / navegación / `preview` disponibles.

Ejemplo (compare whole):

```
state	review/v2.0	v2.0	a1b2c3d4e5f6…	whole	none
entry	1	app.txt
readonly
```

## `--why <path>`

```
git review status --why <path>
```

Sólo válido en modo `walk`. Vuelca a stdout, y **únicamente eso**, el texto
explicativo de la entrada `<path>` (FR-012, FR-014): las líneas del cuerpo
menos los marcadores reservados (`> key`, `> at:`), con saltos de línea
internos preservados. Sin ninguna etiqueta ni framing — el stream entero es el
payload, igual que `git show`/`git cat-file -p`.

- `path` no encontrado en la secuencia actual → exit `1`, diagnóstico en
  stderr.
- Entrada sin cuerpo → stdout vacío, exit `0` (Acceptance Scenario 3 de US4).
- Invocado fuera de modo walk → exit `1`, diagnóstico en stderr explicando que
  `--why` sólo aplica a reviews con walkthrough.

Mismos exit codes 1/2/3 que `--porcelain` para "error" / "no hay review activa"
/ "cursor fuera de rango", evaluados antes de llegar a la validación de modo.

## Exclusiones registradas

Datos que la salida humana muestra y que este contrato **deliberadamente** no
expone, con su motivo:

| Dato                                                                                | Motivo                                                                                                                                                                        |
|-------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Cuerpo del mensaje de un commit                                                     | Prosa multi-línea: no puede viajar en un registro de una línea, y exponerla requeriría una superficie de stream propia.                                                       |
| Diffstat de un commit                                                               | El consumidor ya alcanza esos mismos archivos por la superficie de diff de su host; duplicarlo chocaría con la exclusión de interfaz de diff propia (`002-extension-vscode`). |
| Textos de ayuda (`next`, `banked …`)                                                | Son la guía al usuario humano sobre qué comando correr, no estado de la review.                                                                                               |
| Tipo de cambio de un archivo del listado de `whole` (agregado/modificado/eliminado) | `walk` tampoco lo emite para sus entradas; agregarlo es una decisión separable que ninguna feature tomó todavía.                                                              |
