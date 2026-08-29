# Contrato (enmienda): `walkthrough draft` en la lista cerrada

**Feature**: `011-walkthrough-draft-revisor`

> **Enmendado.** La lista vigente es
> [`012-prompt-agente-draft/contracts/cli-invocation-draft-panel.md`](../../012-prompt-agente-draft/contracts/cli-invocation-draft-panel.md).
> Lo que cambió: `walkthrough draft --build` y `config --porcelain` tienen un
> llamador nuevo —*Validate and start*, en el bloque de borradores del panel— y
> llevan los flags de origen y rango que reporta el registro `draft`, no los
> default; `forget --draft -- <src>` se suma como invocación del panel; el
> botón *Continue* del aviso de espera, que era el llamador de `--build` acá,
> desaparece con el aviso. Este documento queda como historia: no pueden
> convivir dos listas vigentes que se contradigan.

Enmienda aditiva a la lista cerrada de invocaciones de los clientes, cuya
versión vigente es
[`006-superficie-panel-completa/contracts/cli-invocation.md`](../../006-superficie-panel-completa/contracts/cli-invocation.md)
(que a su vez enmienda `005`, que enmienda `002`). Se escribe acá y no editando
aquellos por la misma regla que el repo ya aplicó dos veces: no pueden convivir
dos listas vigentes que se contradigan, así que la vieja queda con un puntero y
la nueva rige.

Lo único que cambia es que **el subcomando `draft` existe** y pasa a estar
permitido. Todo lo demás —forma de la invocación, timeouts por clase, des-citado
unidireccional de paths, uso acotado de la API de `vscode.git`— se mantiene.

## Invocaciones nuevas

### `git review walkthrough draft --porcelain [--local | --offline] [--delta] -- <branch>`

**Cuándo**: el revisor eligió la oferta `draft` en el paso de forma de lectura
del asistente de inicio. Nunca por iniciativa del cliente.

| Argumento               | De dónde                                                     |
|-------------------------|--------------------------------------------------------------|
| `draft`                 | Siempre                                                       |
| `--porcelain`           | Siempre. Cambia la línea de resumen por el registro `merged`  |
| `--local` / `--offline` | El **origen** que el asistente ya resolvió; mutuamente excluyentes |
| `--delta`               | El **rango** que el asistente ya resolvió                     |
| `<branch>`              | El `name` de la candidata elegida, verbatim, detrás de `--`   |

**Se consume**: el exit code, el stderr y el registro `merged` del stdout
(`merged<TAB>kept<TAB>added<TAB>dropped`). **No se parsea la salida humana**: la
frase que `--porcelain` reemplaza traía la ruta, la cantidad y el comando del
paso siguiente, y leerla era exactamente lo prohibido acá. Los tres números son
lo único que este verbo dice y ninguna fila del panel contesta; con ellos el
cliente arma su propia frase (`UserCopy.draftUpdated`). Sin el registro —una CLI
por debajo de `min_cli_version`— el cliente **se calla**, nunca inventa.

Las notas de stderr tampoco se reenvían en bloque: el invocador exporta
`GIT_REVIEW_ADVICE=0`, así que las que ofrecen un comando y las que repiten un
registro no llegan. Las que quedan sí se muestran tal cual.

**Prohibido**: `--force` (sobrescribir un borrador empezado no es una decisión
que el asistente pueda tomar por el revisor; para eso está la terminal) y
`--build` en la misma invocación (son dos pasos del bucle, no uno).

**Clase**: mutación local, `network: false`. El borrador se deriva de refs ya
presentes; el asistente ya hizo el fetch que correspondiera.

### `git review walkthrough draft --build [--local | --offline] [--delta] -- <branch>`

**Cuándo**: el revisor apretó *Continue* en el aviso de espera.

Mismos argumentos de origen y rango que la creación —tienen que ser los mismos:
un borrador se valida contra el rango de la review que se va a iniciar, no
contra otro—, más `--build`.

**Se consume**: el exit code y el stderr. En fallo, el stderr aplanado es lo que
se le muestra al revisor: es el motivo del rechazo, escrito por la CLI, y
redactarlo de nuevo acá sería inventar un segundo vocabulario de validación.

**Prohibido**: `--force`.

**Clase**: mutación local, `network: false`.

## Prohibiciones (actualiza la tabla de `006`)

La fila

| Prohibido                                                 | Por qué      |
|-----------------------------------------------------------|--------------|
| `walkthrough` con subcomandos distintos de `init`/`build` | No existen   |

pasa a leerse:

| Prohibido                                                          | Por qué                                      |
|--------------------------------------------------------------------|----------------------------------------------|
| `walkthrough` con subcomandos distintos de `init`/`build`/`draft`  | No existen                                    |
| `walkthrough draft --force`                                        | Pisar un borrador empezado se pide a mano     |
| Leer, parsear, validar o escribir el archivo del borrador          | Es el mismo formato que el sidecar, y sigue habiendo dos únicos puntos de normalización de paths |
| Derivar si hay borrador mirando el gitdir                          | Eso llega por `offer` (`draft` / `draft-resume`) |

**Abrir el borrador en el editor no es leerlo**: el cliente muestra el archivo y
no interpreta un byte, exactamente como ya hace con `.review/walkthrough.md`
tras un `walkthrough init` (`006`).
