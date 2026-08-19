# Contrato (enmienda): las invocaciones del bloque de borradores

**Feature**: `012-prompt-agente-draft`

Enmienda aditiva a la lista cerrada de invocaciones de los clientes, cuya
versión vigente es
[`011-.../contracts/cli-invocation-draft.md`](../../011-walkthrough-draft-revisor/contracts/cli-invocation-draft.md)
(que enmienda `006`, que enmienda `005`, que enmienda `002`). Se escribe acá y no
editando aquéllos por la misma regla que el repo ya aplicó tres veces: no pueden
convivir dos listas vigentes que se contradigan, así que la vieja queda con un
puntero y la nueva rige.

Todo lo demás —forma de la invocación, timeouts por clase, des-citado
unidireccional de paths, uso acotado de la API de `vscode.git`— se mantiene.

## Lo que cambia

Ninguna invocación nueva **de comando**. Lo que cambia es **desde dónde** y
**con qué argumentos** se hacen dos que ya estaban permitidas, más una
permitida en 011 que pasa a tener un llamador nuevo.

### `git review walkthrough draft --build -- <src>`

**Cuándo (nuevo)**: el revisor apretó **Validate and start** en una fila del
bloque de borradores del panel. El llamador de 011 —el botón *Continue* del
aviso de espera— **desaparece** con el aviso.

| Argumento | De dónde |
| --- | --- |
| `--build` | Siempre |
| `--local` / `--offline` / nada | El campo `<source>` del registro `draft` (`local` / `offline` / `remote`) |
| `--delta` / nada | El campo `<range>` del registro `draft` (`delta` / `full`) |
| `<src>` | El campo `<src>` del mismo registro, verbatim, detrás de `--` |

**Los flags de origen y rango salen del registro, no son los default.** El
borrador ya fue generado con unos flags concretos, y ésos son los que definen su
rango; invocar con otros hace que `--build` muera por deriva **siempre**, sobre
un borrador perfectamente válido. Los mismos flags van al `config --porcelain` y
al `start` que siguen, para que los tres pasos hablen del mismo rango.

**Con `<source>` o `<range>` en `unknown`** —el bloque de instrucciones se borró
a mano— la fila **no ofrece** este control. Se prefiere un control menos a un
control que adivina.

**Prohibido**: `--force`, `--from`, `--stdout`. Pisar prosa, instalar contenido
de otro archivo o emitir un esqueleto no son decisiones que el panel pueda tomar
por el revisor; para eso está la terminal.

**Se consume**: el exit code y el stderr. En fallo, el stderr aplanado es lo que
se le muestra al revisor: es el motivo del rechazo escrito por la CLI, y
redactarlo de nuevo sería inventar un segundo vocabulario de validación.

**Clase**: mutación local, `network: false`.

### `git review config --porcelain -- <src>`

**Cuándo (nuevo)**: después de un `--build` en verde desde el panel, para saber
si el borrador trae entradas esenciales (`offer keys`) y sólo entonces preguntar
recorrido completo vs sólo esenciales. Con **los mismos flags de origen y rango**
que el `--build` anterior.

Ya estaba permitida; lo único nuevo es este llamador.

**No hay un llamador nuevo para conseguir la ruta de un borrador recién creado.**
Se consideró y se descartó: el asistente ya no abre el borrador (ver
[`client-draft-panel.md`](client-draft-panel.md) § 3), así que la ruta llega por
el refresco post-mutación que ya existe, sin una invocación de más.

### `git review forget --draft -- <src>`

**Cuándo (nuevo)**: el revisor apretó **Discard** en una fila y **confirmó**.

| Argumento | De dónde |
| --- | --- |
| `--draft` | Siempre |
| `<src>` | El campo `<src>` del registro, verbatim, detrás de `--` |

**Prohibido**: `--all` (barrería borradores de otras filas, y de archivados que
nadie está mirando), `--saved` (esa es prosa de una review pausada), y omitir
`<src>`.

**Clase**: mutación local, `network: false`. Bajo el lock de mutación y con
confirmación previa, como `discardInventory`.

### `git review walkthrough draft [--local|--offline] [--delta] -- <branch>`

**Sin cambios** respecto de 011. Sigue siendo la creación desde el asistente,
con el origen y el rango que el asistente ya resolvió. Lo que cambia es lo que
pasa **después**: el asistente termina en cuanto la creación sale en verde, sin
abrir nada y sin dejar un aviso esperando.

Esos mismos flags son los que la CLI graba en el bloque de instrucciones y los
que después vuelven por el registro `draft`, cerrando el círculo: lo que el
asistente eligió es lo que el panel replica.

## Prohibiciones (actualiza la tabla de `011`)

| Prohibido | Por qué |
| --- | --- |
| `walkthrough draft --force` desde cualquier cliente | Pisar un borrador empezado se pide a mano |
| `walkthrough draft --from` desde cualquier cliente | Instalar contenido de otro archivo es un acto de terminal; el panel opera sobre el borrador de la fila |
| `walkthrough draft --stdout` desde cualquier cliente | El cliente no consume el esqueleto: lo abre como archivo |
| `forget --draft --all` desde el bloque de borradores | Una acción sobre una fila no puede tocar las demás (FR-026) |
| **Armar la ruta del borrador** | Llega por porcelain. `gitdirFromLink` y el `path.join` de `startReview.ts` se retiran (SC-008) |
| Leer, parsear o validar el archivo del borrador | Sin cambios respecto de 011 |
| Derivar el progreso leyendo el archivo | Llega por el registro `draft` de `config --porcelain` (FR-027) |

**Abrir el borrador en el editor no es leerlo**: el cliente muestra el archivo y
no interpreta un byte, exactamente como ya hace con `.review/walkthrough.md`
tras un `walkthrough init` (`006`).

## Versión mínima

Los tres clientes suben `min_cli_version` a **0.7.0** en el mismo cambio, porque
los registros que consumen no existen antes. El verificador compara el YAML
contra las tres constantes (`version.ts`, `Version.kt`, `Version.cs`), así que
las cuatro puntas se mueven juntas o CI falla.
