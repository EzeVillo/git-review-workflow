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

## Compatibilidad

Aditivo puro. Una review sobre walkthrough del autor no emite el registro y su
salida es byte por byte la de hoy.
