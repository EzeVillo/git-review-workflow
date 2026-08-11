# Contrato (enmienda): registro `draft` en `status --porcelain`

**Feature**: `011-walkthrough-draft-revisor`

Enmienda aditiva a
[`001-contrato-porcelain/contracts/status-porcelain.md`](../../001-contrato-porcelain/contracts/status-porcelain.md).
Describe el delta; la gramática v1 no cambia.

## Registro `draft` (cero o una vez)

```text
draft
```

Registro de **presencia**, sin campos — la misma forma que ya usa el submodo
keys-only ([status:252](../../../bin/git-review-verbs/status:252)).

**Cuándo se emite**: cuando la review activa corre sobre un borrador del
revisor, es decir cuando existe el borrador de `<src>`. Sólo puede darse en
`mode = walk`.

**Posición**: en el bloque de registros de presencia, después de `state` y de
los registros de entradas, junto a los demás marcadores del mismo tipo.

## Por qué un registro y no un campo

El registro `state` de walk se parsea **por posición** en los dos clientes
publicados:

```text
state	<cur>	<src>	<tip>	walk	applied	<step>	<total>	<count>	<path>	<essential>
```

Agregar un campo al final es la clase de cambio que parece inocuo y desalinea a
un consumidor que valida la aridad. Un registro propio no puede desalinear nada
y un cliente que no lo conoce lo ignora, que es exactamente lo que la gramática
porcelain v1 promete para las etiquetas desconocidas.

## Salida legible (no porcelain)

La línea de modo gana un sufijo:

```text
  mode    walk  [3/12] on src/api/orders.ts (key)
  mode    walk (draft)  [3/12] on src/api/orders.ts (key)
```

El sufijo va pegado al modo y **no** desplaza ni altera el resto de la línea,
para que siga siendo legible de un vistazo y no rompa a quien la mire con
herramientas de línea.

## Consumo en los clientes

- **Panel**: badge de texto discreto junto al modo, dentro de un bloque que ya
  existe. **No** agrega controles ni bloques, así que
  `contracts/client-product-surface.yaml` § `panel_layout` **no cambia** y
  `check-client-product-surface.mjs` / `PanelLayoutContractTest` siguen verdes
  sin tocarse.
- **Ningún cliente** infiere el origen del walkthrough por su cuenta: sólo
  refleja este registro.

## `status` puede reasentar el cursor

A partir de esta feature, `status` sobre una review walk **puede escribir**
`branch.<review>.reviewwalkstep` y `reviewwalkcount`. Es la única escritura del
camino de lectura y hay que documentarla, porque hasta acá `status` era un
comando de lectura pura.

**Cuándo**: sólo cuando el cursor quedó pasado del final porque el revisor editó
su propio borrador y lo acortó — el resto de las causas de un cursor fuera de
rango siguen siendo diagnóstico, no recuperación (`walk_recover_cursor`,
[git-review-lib.sh](../../../bin/git-review-lib.sh)). Con el walkthrough del
autor no puede ocurrir: está congelado en el tip.

**Por qué desde el camino de lectura y no desde `next`/`prev`**: el clamp
aterriza en la última entrada, y ésa es justo la posición desde la cual `next`
no escribe ([next:49](../../../bin/git-review-verbs/next:49) imprime *no more
entries* y sale). Persistir sólo desde los verbos de navegación dejaría el
estado sin converger indefinidamente: la nota se repetiría en cada invocación y
`list` —que lee las claves crudas, sin re-derivar— mostraría una posición y un
total que no existen.

**Garantías para los clientes**:

- La escritura es **best-effort**. Si falla (otro proceso con `.git/config.lock`,
  gitdir read-only), el comando igual sale 0 y su porcelain lleva ya el cursor
  clampeado: la posición que reporta es correcta aunque no haya persistido.
- Es **idempotente**. Dos clientes refrescando a la vez escriben el mismo valor,
  y una escritura perdida se reintenta sola en la próxima invocación.
- Puede **disparar el watcher** de un cliente que observe `.git/config` (la
  extensión de VS Code lo hace en su fallback). El refresco resultante encuentra
  el cursor ya en rango y no vuelve a escribir, así que converge en una
  iteración.

## Compatibilidad

Aditivo puro. Una review sobre walkthrough del autor no emite el registro y su
salida es byte por byte la de hoy.
