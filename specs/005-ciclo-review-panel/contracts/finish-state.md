# Contrato: el registro `finish` — un cierre que no terminó de resolverse

Extensión aditiva del formato porcelain v1. La fuente normativa sigue siendo
[`001-contrato-porcelain`](../../001-contrato-porcelain/contracts/status-porcelain.md);
acá se agrega **una etiqueta nueva** a dos verbos que ya existen, sin tocar
ningún registro ni ningún exit code vigente.

## El problema que resuelve

`git review finish` deja el repositorio en uno de dos estados que hoy el contrato
**no puede describir**, y en los dos el consumidor ve algo falso:

| Estado real | Qué reporta el contrato hoy | Qué concluye el consumidor |
|-------------|------------------------------|-----------------------------|
| Cierre completo, con punto de undo vivo | `status` exit `2` (`HEAD` ya no está en `review/*`) | "No hay ninguna review" |
| Cierre frenado por conflicto de ediciones bancadas | `status` exit `0`, review de aspecto normal | "Una review normal" — y ofrece navegar por ella |

El segundo es el peligroso: el panel habilitaría `next`/`prev` sobre un working
tree con marcadores de conflicto y un cierre a medio hacer.

## Por qué en dos verbos distintos

Porque los dos estados se observan desde lugares distintos, y eso no es una
elección: es dónde queda `HEAD`.

- **Cierre completo** → `HEAD` está en `review-fixes/<src>`, o en la rama del PR
  con `--onto-source`. `status` sale con `2` por diseño y no tiene dónde colgar el
  dato. Pero la rama `review/<src>` sigue existiendo —`finish` no la borra— con su
  registro de undo, así que **`list` ya la enumera**: sólo falta decir en qué
  estado está. Y el panel en `no-review` ya invoca `list --porcelain` para dibujar
  el inventario, así que no cambia *cuándo* se invoca nada.
- **Cierre trabado** → `HEAD` sigue en `review/<src>` y `status` responde `0`. El
  dato tiene que llegar por ahí, que es lo que el consumidor consulta cuando hay
  review.

El caso `--onto-source` es el que descarta cualquier heurística por nombre de
rama: ahí `HEAD` queda en la rama del PR, sin prefijo reconocible. Partir de las
ramas `review/*` y su config lo cubre sin mirar dónde está parado el usuario.

## Por qué un registro propio y no un campo más

El registro `state` tiene aridad variable por modo (5, 9 o 10 campos después de
la etiqueta) y campos posicionales. Un campo agregado al final sería ambiguo
justamente en los modos que omiten grupos. `001` ya previó el caso y fijó la
regla: *lo que haya que agregar en el futuro va en un registro propio*.

La compatibilidad sale gratis: un consumidor anterior ignora la etiqueta que no
conoce, que es su obligación desde `001`.

---

## En `git review status --porcelain`

```text
finish<TAB>state<TAB>onto
```

- `state`: **siempre `conflict`** en este verbo. Es el único estado de cierre
  observable desde dentro de una review activa; un cierre completo ya sacó a
  `HEAD` de `review/*`.
- `onto`: `1` si el cierre en curso llevaba `--onto-source`, `0` si no. Sale de
  `branch.review/<x>.reviewundokind`, que `finish` ya registra
  (`bin/git-review-verbs/finish:329-341`).
- **Se omite el registro entero** cuando no hay ningún cierre en curso. No existe
  un valor `none`.
- Va después del registro `state`, que `001` fija como la primera línea. Su
  posición relativa a `entry`/`subject`/`author`/`base` no es significativa: el
  consumidor empareja por etiqueta, nunca por orden de aparición.

Ejemplo (modo step, cierre trabado, sin `--onto-source`):

```text
state	review/feat-x	feat-x	a1b2c3d4e5f6…	step	none	2	9	9	9fe1c0d
finish	conflict	0
entry	1	6bce6d1	1
entry	2	9fe1c0d	0
…
```

**Por qué `onto` está en el contrato y no en la memoria del consumidor**:
continuar un cierre trabado es `finish --resume [--onto-source]`, y el flag tiene
que ser el mismo con el que empezó — si no, las ediciones terminan en otro lado
del que el usuario eligió. Guardarlo del lado del consumidor funciona hasta que
el editor se reinicia, y ahí el resume silenciosamente hace otra cosa. Es estado
de la review, la CLI ya lo tiene registrado, y el consumidor no puede
reconstruirlo: por definición va en el contrato.

**Exit code**: sigue siendo `0`. Un cierre trabado no es un error del verbo —
`status` respondió correctamente— y convertirlo en uno rompería a todo consumidor
que hoy trata `≠ 0` como fallo. El estado se comunica con el registro, no con el
código.

**Consecuencia obligatoria para el consumidor** (FR-027): con este registro
presente, la navegación por la secuencia **no se ofrece**. La review sigue siendo
legible; lo que no corresponde es moverse dentro de ella mientras hay un cierre a
medio aplicar.

---

## En `git review list --porcelain`

```text
finish<TAB>branch<TAB>state<TAB>onto
```

- `branch`: la rama `review/<x>` a la que pertenece el cierre. Va inmediatamente
  después de la etiqueta, como todo identificador en este formato. Se empareja con
  el `name` del registro `branch` de
  [`list-porcelain`](../../001-contrato-porcelain/contracts/list-porcelain.md).
- `state`: `pending` | `conflict`. Acá aparecen **los dos**: `list` mira el
  repositorio entero, no la rama en la que estás parado, así que también ve la
  review trabada cuando el usuario se fue a otro lado.
- `onto`: `1` | `0`, con el mismo significado y el mismo origen que en `status`.
- Una línea por review con cierre sin resolver. Las reviews sin cierre en curso
  no emiten registro.

Ejemplo (dos reviews abiertas, una con un cierre completo pendiente):

```text
branch	review/feat-x	0	0	0	walk	3	7
branch	review/fix-y	0	1	0	whole
finish	review/feat-x	pending	0
```

**Exit code**: sin cambios (`0` en cualquier repositorio git; un inventario vacío
sigue siendo un resultado válido).

---

## Cardinalidad e invariantes

- **A lo sumo un cierre por review.** Lo garantiza la CLI: `finish` se niega a
  empezar otro mientras hay uno sin resolver
  (`bin/git-review-verbs/finish:364-373`). El consumidor no tiene que desempatar.
- **`conflict` implica que `review/<x>` existe y `HEAD` puede estar en ella.**
  `pending` implica que existe y `HEAD` **no** está en ella.
- **El registro desaparece cuando el cierre se resuelve**, por cualquiera de sus
  caminos: deshacerlo, continuarlo hasta el final, o tirar la review entera. El
  consumidor no necesita saber cuál ocurrió: vuelve a preguntar.

## Resolución de `git review finish --abort`

El verbo **no** recibe el nombre de la review: identifica el cierre a deshacer
y después restaura `review/<src>`, elimina o revierte la rama producto del
finish y limpia el registro de undo (igual que si se invocara desde
`review-fixes/<src>`).

Orden de resolución del target:

1. Si `HEAD` es `review-fixes/<src>`, `review/<src>`, o la rama del PR cuando
   `review/<src>` tiene undo (caso `--onto-source`), y ese undo existe → ese
   target.
2. Si no, se listan todas las `review/*` con `reviewundohead` (el mismo
   universo que las filas `finish` de `list --porcelain`):
   - **cero** → error `no finish to abort` (sin inventar `review/<rama-actual>`);
   - **una** → esa;
   - **varias** → si hay **exactamente un** finish completado
     (`reviewundoouthead` presente, el caso `pending`), se usa ese; si no, error
     listando los targets y pidiendo cambiar a la rama del cierre deseado.

Efectos de un abort exitoso (invariantes): `HEAD` en `review/<src>`; tree e
index del snapshot pre-finish; `review-fixes/<src>` borrada (o la rama del PR
revertida/borrada según onto); registro de undo y fila `finish` de `list`
desaparecen. La rama desde la que se invocó **no** se reescribe salvo al
cambiar `HEAD` hacia la review.

## Qué NO expone este registro

| Dato | Motivo |
|------|--------|
| Qué archivos están en conflicto | El consumidor ya los alcanza por la superficie de control de código fuente de su host; duplicarlo chocaría con la exclusión de interfaz de diff propia que `002` mantiene. |
| El nombre de la rama que el cierre produjo | Se deriva del `branch` y del `onto` que el registro ya trae, sin ambigüedad: `review-fixes/<x>` o el propio `<x>`. Un campo que el consumidor puede calcular no va en el contrato. |
| Cuándo se hizo el cierre | No hay ninguna decisión que dependa de eso. |

`onto` sí entró, y la regla que lo decidió vale para lo que venga: un dato entra
al contrato cuando el consumidor **no puede reconstruirlo** y lo necesita para
invocar correctamente. Deshacer un cierre no lo necesita (la CLI ya sabe cuál
deshacer); continuarlo sí, porque el flag viaja en la invocación.
