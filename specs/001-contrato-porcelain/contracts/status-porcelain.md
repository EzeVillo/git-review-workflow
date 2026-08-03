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

## Registros `entry` (cero o más, uno por posición de la secuencia)

```
entry<TAB>position<TAB>id[<TAB>essential<TAB>annotated|<TAB>banked]
```

- `position`: 1-based, mismo orden que recorren `next`/`prev`.
- `id`: path (modo walk) o SHA corto de commit (modo step).
- En modo walk, dos campos finales: `essential` (`1`/`0`) y `annotated`
  (`1`/`0`). En modo step, uno solo: `banked` (`1`/`0`, existe
  `refs/review-edits/<src>/<position>`). El grupo que no aplica al modo se
  **omite** entero, no se emite vacío (Acceptance Scenario 2 de US1). En
  `whole` no hay registros `entry` en absoluto.
- `annotated`: `0` cuando el path cambia en el rango de la review pero no
  tiene entrada propia en el walkthrough — la secuencia lo agrega al final del
  orden de lectura en vez de omitirlo, para que un review no llegue al final
  con archivos del PR que el reviewer nunca vio (el precedente es `git
  status`, que no esconde los untracked). `total` cuenta estas posiciones
  igual que las curadas.

Ejemplo (walk, 3 entradas, la segunda esencial, la tercera sin anotar):

```
entry	1	src/a.ts	0	1
entry	2	src/b.ts	1	1
entry	3	src/c.ts	0	0
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

Vale igual para `state.current` en modo walk que para el `id` de `entry`: los
dos son el mismo dato de la misma fuente.

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
