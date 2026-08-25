# Contrato (enmienda): registros `draft` en `config --porcelain`

**Feature**: `012-prompt-agente-draft`

Enmienda aditiva a
[`008-start-layout-offers/contracts/config-porcelain-offers.md`](../../008-start-layout-offers/contracts/config-porcelain-offers.md)
y a
[`011-walkthrough-draft-revisor/contracts/config-porcelain-draft.md`](../../011-walkthrough-draft-revisor/contracts/config-porcelain-draft.md).
Describe el delta; la invocación, los flags y la gramática porcelain v1 no
cambian. **El registro `offer` no cambia en nada.**

## Por qué acá y no en `status --porcelain`

`status --porcelain` sale con **exit 2 y stdout vacío** fuera de una rama
`review/*`: la guarda corre antes de todo el bloque legible por máquina
([status:69-75](../../../bin/git-review-verbs/status)). Los tres clientes derivan
la situación `no-review` de ese exit code, así que un borrador sin review no
tiene dónde aparecer ahí. `config --porcelain` es la única superficie que el
panel ya consulta **sin review y sin nombrar ninguna rama**, junto al informe de
estado y al inventario, en el mismo refresco: los registros nuevos no agregan
una invocación.

## Registro `draft` (cero o N veces)

```text
draft<TAB><src><TAB><path><TAB><annotated><TAB><total><TAB><source><TAB><range><TAB><state>
```

| Campo | Valor |
| --- | --- |
| `<src>` | La rama a la que pertenece el borrador, verbatim, tal como se usa de argumento (`feature/checkout`, con `/`) |
| `<path>` | Ruta **absoluta** del archivo, ya resuelta. El cliente la abre; no la arma (FR-021, SC-008) |
| `<annotated>` | Entradas con posición **y** *why* resueltos |
| `<total>` | Entradas que el archivo declara (numeradas y `## ?.`) |
| `<source>` | `remote`, `local` u `offline` — con qué origen se generó |
| `<range>` | `full` o `delta` — con qué rango se generó |
| `<state>` | `fresh` o `reviewed` — si la review que ese borrador alimentaba ya terminó |

**`<source>` y `<range>` no son informativos: son lo que hace utilizable el
botón.** *Validate and start* del panel invoca `draft --build` y `start`, y si
lo hiciera con los flags por defecto sobre un borrador hecho con `--delta`,
`--local` u `--offline`, cubriría otro conjunto de paths y **fallaría siempre**
con error de deriva, sin salida dentro del panel. Salen de la línea
`Generated with:` del bloque de instrucciones, que es su única casa
([`walkthrough-prompt-block.md`](walkthrough-prompt-block.md) § 2b); se leen en
el mismo `awk` que ya cuenta el progreso, o sea a coste cero.

**Si el bloque no está** —lo puede borrar el revisor a mano, y eso es legal—
los dos campos valen `unknown`. El cliente entonces **no ofrece** *Validate and
start* para esa fila y remite a la terminal: mejor una acción menos que una
acción que falla siempre.

**Cuándo se emite**: uno por cada borrador del namespace **activo**
(`<gitdir>/review-walkthrough/`), enumerados por `walk_draft_list`. Se emite con
y sin argumento de rama — no porque la salida del verbo sea simétrica (**no lo
es**: `delta` y `offer` sólo existen con rama), sino porque un borrador es un
hecho del **working tree**, no de la rama consultada. Condicionarlo al argumento
haría que el mismo repositorio reportara distintos borradores según qué se
preguntó, y esa relación no existe.

**Orden**: el de `walk_draft_list` (recursión sobre globs, o sea lexicográfico
por directorio). Estable; nunca se reordena por locale.

**Posición**: después de `candidate` / `remote-candidate` y antes de `delta` /
`offer`. Los consumidores parsean por etiqueta, así que la posición no es
normativa, pero fijarla mantiene la salida determinista y comparable byte a byte
en los tests.

### `<state>`: si la review de ese borrador ya terminó

Un borrador **sobrevive a la review para la que se escribió** — `clean` no lo
toca, y eso no cambia — pero una vez que la review cerró deja de ser trabajo en
curso, y el panel lo dibujaba en el mismo bloque que uno a medio escribir. Este
campo es lo que separa las dos cosas.

`reviewed` cuando **una review completada de esa rama cubrió el mismo tip**
**contra el que el borrador se generó**; `fresh` en todo lo demás. Las tres
piezas:

- **El tip del borrador**, del `tip <sha>` de su bloque de instrucciones (misma
  regla de 40 hex que `walk_sidecar_block_tip`). Se compara el tip del
  **borrador**, no el de la rama hoy, porque lo que se pregunta es si *ese orden
  de lectura* ya se leyó: uno regenerado después de la review cubre un rango que
  nadie leyó y vuelve a `fresh`, y uno cuya rama avanzó sigue describiendo lo que
  sí se leyó, así que sigue `reviewed`. Que además esté **derivado** es otra
  pregunta, y la contesta `build`.
- **El marcador** `reviewworkflow.<src>.reviewed` (o `reviewworkflowlocal.` para
  un borrador `local`/`offline`), que es el tip que la última review **completa**
  de esa rama cubrió: `start` lo escribe, y `abort` y un `clean` sin finish
  exitoso lo revierten. Los dos sabores no se cruzan — hacerlo reportaría un
  borrador como leído porque se revisó la *otra* copia de la rama.
- **`source` = `unknown`** (bloque borrado a mano, que es legal) o sin tip
  legible: `fresh`. No se puede probar nada, y `fresh` es el estado que ofrece
  más, no menos.

**No consulta las reviews vivas**, y eso es deliberado: `start` escribe el
marcador antes de correr la review, así que un borrador que una review está
leyendo ahora mismo reporta `reviewed`. Contestarlo bien cuesta un
`for-each-ref` más un `git config` por review en un camino que corre en cada
refresco, y el panel no dibuja el bloque con una review activa en esa rama. La
pregunta sí se hace donde es gratis: `git review forget --draft --reviewed`
saltea el borrador que una review walk está leyendo, porque ahí el costo se paga
una vez y lo que está en juego es borrar prosa en uso.

### Un borrador de una review pausada nunca aparece

No por una regla: `git review save` movió el archivo a
`review-saved-walkthrough/`, que `walk_draft_list` **no** recorre. Es la
separación de namespaces que 011 construyó, y es lo que hace que FR-024 y SC-012
se cumplan sin código nuevo. Hay un test que lo fija para que nadie la deshaga
por accidente.

### Qué NO dice el registro

No dice si una review activa ya lee ese borrador; ver arriba. Si alguna vez
hace falta, es un campo más al final del mismo registro.

## El progreso

Definido en [`../data-model.md`](../data-model.md) § *Progreso del borrador*. Lo
que este contrato fija:

- Se cuenta **sobre el archivo**, sin cruzarlo con el rango (FR-022). Un
  borrador que quedó fuera de rango informa avance igual; el desajuste es asunto
  de la validación.
- `<annotated> == <total>` **no** promete que `--build` vaya a pasar.
- Un borrador recién generado emite `0<TAB>N` (SC-013).
- Un archivo vacío o de puro whitespace emite `0<TAB>0` — y sigue emitiendo un
  registro, porque el archivo existe y hay que poder abrirlo y descartarlo. (Es
  la distinción `walk_has_draft_file` vs `walk_is_draft` de 011: acá se reporta
  **custodia**.)

**La enumeración manda, `awk` sólo cuenta.** Las filas salen de
`walk_draft_list`; el llamador correlaciona por ruta y lo que `awk` no reportó
cae a `0 0`. No es una preferencia de estilo: **`awk` no ejecuta ninguna regla
para un archivo de cero bytes ni le asigna `FILENAME`**, así que un borrador
vacío no produce ninguna línea y, si `awk` mandara, desaparecería del reporte —
justo el que más necesita aparecer, porque es el estado de uno recién creado.

## Coste

Presupuesto duro, porque este verbo corre en cada refresco del panel sin review:

| Pieza | Procesos |
| --- | --- |
| `walk_draft_list` | **0** (recursión sobre globs, builtin) |
| Progreso de los N borradores | **1** — un solo `awk` con los N archivos como argumentos, **sólo si N ≥ 1** |
| Gitdir absoluto | **1**, y sólo si N ≥ 1 |
| Marcadores de `--delta` | **1**, y sólo si N ≥ 1 — un `git config --get-regexp` para **todos** los borradores, y cada fila se contesta contra ese string con un `case` builtin |

**Con N = 0 no se invoca nada: cero procesos.** No es una optimización, es una
guarda obligatoria: `awk` sin argumentos de archivo lee la entrada estándar y
**se cuelga**. Este verbo corre en cada refresco del panel y también a mano en
una terminal, así que un cuelgue indefinido en el caso más común de todos —un
repositorio sin borradores— violaría SC-005 de la peor manera posible. La
enumeración vacía tiene que cortar antes del `awk` y antes del gitdir absoluto.

Un `awk` por borrador es la otra trampa evidente y también está prohibida: es la
misma regla que produjo `walk_entry_fields`. El cierre por archivo se hace con
`FNR == 1` más el `END`, **nunca con `ENDFILE`**, que es extensión de gawk (CI
corre mawk y BSD awk).

## Ejemplo

Sin review activa, con dos borradores a medio escribir:

```text
config	base	develop
config	remote	origin
remote-candidate	origin	1
candidate	feature/checkout	remote	0
candidate	feature/telemetry	remote	0
draft	feature/pagos	/repo/.git/review-walkthrough/feature/pagos.md	0	5	remote	full	fresh
draft	feature/telemetry	/repo/.git/review-walkthrough/feature/telemetry.md	3	9	local	delta	reviewed
```

## Compatibilidad

Aditivo por diseño. `draft` es una etiqueta nueva de este verbo, así que ningún
cliente publicado la conoce y los tres la ignoran (`default: break`, verificado
en los tres parsers). Un repositorio sin borradores emite exactamente la salida
de hoy, byte por byte.

La etiqueta `draft` de `config --porcelain` y la etiqueta `draft` de
`status --porcelain` **no colisionan**: son verbos distintos con gramáticas de
registro propias, igual que `finish` significa cosas distintas en `status` y en
`list`.

## Tests

`tests/config-offers-draft.bats` (los casos nuevos) y
`tests/walkthrough-draft-progress.bats` (el conteo).

| Caso | Afirma |
| --- | --- |
| Sin borradores | Ningún registro `draft`; la salida es idéntica a la de antes del cambio; **y el comando termina** — con `timeout` o su equivalente del runner, para que un `awk` sin argivos no pueda volver a colarse |
| Un borrador de cero bytes | **Emite registro** con `0<TAB>0`; es el caso que `awk` no puede reportar por su cuenta |
| `<source>` / `<range>` en los cinco orígenes | `remote full`, `local full`, `offline full`, `remote delta`, `local delta`, leídos del bloque |
| Bloque borrado a mano | `<source>` y `<range>` valen `unknown`; el resto del registro no cambia |
| Un borrador recién generado | Un registro, ruta **absoluta y existente** (`[ -f ]`), `0<TAB>N` con N los archivos del rango |
| Dos borradores | Dos registros, uno por rama, en orden estable; ninguno oculta al otro |
| Rama con `/` | `<src>` sale con la barra, y la ruta apunta al subdirectorio |
| Con y sin argumento de rama | Los mismos registros `draft` en los dos casos |
| Progreso parcial | Entrada con número y sin why: no cuenta. Con why y sin número: no cuenta. Con las dos: cuenta |
| Progreso con `> key` | El marcador solo no es *why*: una entrada con `> key` y nada más no cuenta |
| Progreso sin cruzar el rango | Un borrador con un archivo de más informa su total igual, y `--build` sigue rechazándolo por drift |
| Borrador vacío | Un registro con `0<TAB>0` |
| Borrador de una review pausada | **Cero registros** tras `git review save`; vuelven tras `git review continue` |
| Borrador de una review activa | Sí se emite (no se filtra) |
| Coste | El número de procesos no crece con el número de borradores (comparación de `set -x` o de un contador de invocaciones de `awk`) |
