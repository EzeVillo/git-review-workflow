# Contrato: invocaciones permitidas (enmienda 006)

Enmienda de validación: [guard del contexto de review](../../../contracts/review-state-guard.md).
El prefijo global `--expect-state <guard>` se permite en las mutaciones del
contexto mostrado. Las lecturas, `--check` y los comentarios con guards propios
no lo llevan. El código 4 exige refresco completo y el aviso `STALE` existente.

**Enmienda** de
[
`005-ciclo-review-panel/contracts/cli-invocation.md`](../../005-ciclo-review-panel/contracts/cli-invocation.md).
A partir de esta feature, **este documento rige** junto con el de `005` para
todo lo que `005` no reemplace: se **levantan** las prohibiciones de `clean`,
`forget`, `walkthrough`, `compare` y `preview`, y se enumera la lista cerrada
de argumentos. Donde este archivo y el de `005` se contradigan sobre estos
cinco verbos, gana éste.

La forma de invocación, timeouts por clase, lock, y el resto de verbos de
`002`/`005` no cambian.

## Criterio de admisión (enmienda)

Ver `spec.md` de esta feature: representable + (inversa **o** confirmación) +
hogar en el producto. Solo lectura (`preview`) sin modal.

---

## Mutaciones nuevas

Todas serializadas por `MutationLock`, no cancelables una vez iniciada la
mutación, confirmación **fuera** del lock, revalidación de `StateToken` cuando
la acción se originó en una fila de inventario (FR-012).

### `git review clean [--keep-fixes | --fixes-only] [<branch>]`

| Argumento      | Cuándo                                                                                     |
|----------------|--------------------------------------------------------------------------------------------|
| *(ninguno)*    | Clean all leftovers (`review/*` y, por defecto, `review-fixes/*`)                          |
| `<branch>`     | Source name verbatim (`feature/x`), nunca `review/x`                                       |
| `--keep-fixes` | Post-finish del panel: borra solo `review/<branch>` (+ undo); deja `review-fixes/<branch>` |
| `--fixes-only` | Fila de "Edits you extracted": borra solo `review-fixes/<branch>`; deja la sesion en pie  |

**Prohibido**: cualquier otro flag, y los dos juntos (la CLI los rechaza). El
panel en `finish-pending` **debe** pasar `--keep-fixes` (el clean “lleno” del
inventario/palette sigue sin el flag); la fila de la seccion “Edits you
extracted” **debe** pasar `--fixes-only` **siempre**, exista o no todavia la
sesion: el argv no puede depender de un dato que se relee en cada refresco, y un
`clean <branch>` que llegue tarde se llevaria puesta una review viva.

**Se consume**: exit code + stderr. Estado vía refresh `status`/`list`.

### `git review forget --saved (<branch> | --all)`

| Argumento  | Cuándo               |
|------------|----------------------|
| `--saved`  | Siempre en este modo |
| `<branch>` | Una review guardada  |
| `--all`    | Todas las guardadas  |

**Prohibido**: `--dry-run`, `--delta` en la misma invocación, `--stale`.

### `git review forget --delta (<branch> | --all | --stale)`

| Argumento  | Cuándo                                                     |
|------------|------------------------------------------------------------|
| `--delta`  | Siempre en este modo                                       |
| `<branch>` | Un source                                                  |
| `--all`    | Todos los markers                                          |
| `--stale`  | Solo stale; **network: true**, timeout de mutación con red |

**Prohibido**: `--dry-run` en la UI (no se pasa nunca desde la extensión).

### `git review compare <a> <b> [--step | --no-walk]`

| Argumento              | De dónde                                       |
|------------------------|------------------------------------------------|
| `<a>`, `<b>`           | Candidata o commit-ish tipeado, verbatim       |
| `--step` / `--no-walk` | layout; mutuamente excluyentes; auto = ninguno |

Usar el separador `--` cuando el parseo del verbo lo requiera para commit-ish
que parecen opciones (misma disciplina que `start`: preferir pasar `--` antes
de los posicionales si se implementa un único camino estable).

**Prohibido**: otros flags.

### `git review walkthrough init [--force]`

| Argumento | Cuándo                                  |
|-----------|-----------------------------------------|
| `init`    | Siempre                                 |
| `--force` | Solo tras confirmación de sobrescritura |

**Prohibido en esta feature (UI)**: `--base` (opcional futuro; no en lista de
código hasta que se implemente picker).

### `git review walkthrough build`

Sin flags en la UI de esta feature. **Prohibido**: `--check` hasta que se
exponga explícitamente.

---

## Lectura nueva

### `git review preview [--stat]`

**Cuándo**: acción del usuario con review en condiciones que la CLI acepta.

**Se consume**: stdout (cuerpo a mostrar) + stderr (notas/errores) + exit code.
**No** se usa para rellenar mode/position/entries del view-model.

**Sin confirmación modal.** Timeout de lectura.

---

## Prohibiciones (actualizada respecto de 005)

Se **elimina** la fila que prohibía invocar `clean`, `forget`, `walkthrough`,
`compare`, `preview`.

Se **agregan**:

| Prohibido                                                 | Por qué                                                 |
|-----------------------------------------------------------|---------------------------------------------------------|
| `git branch -D` / borrar refs a mano                      | FR-006 — solo clean/forget                              |
| Pasar `--dry-run` a forget                                | No hay superficie; la confirmación es el dry-run humano |
| Combinar `--saved` y `--delta`                            | El verbo lo prohíbe                                     |
| `walkthrough` con subcomandos distintos de `init`/`build` | No existen — **enmendado por `011-walkthrough-draft-revisor`**: `draft` ya existe; ver `specs/011-walkthrough-draft-revisor/contracts/cli-invocation-draft.md` |
| Parsear stdout de `preview` para el view-model de review  | FR-005                                                  |

Todo lo demás de la tabla de `005` se mantiene.

## Ampliación: comentarios (CLI candidata 0.10.0)

Contrato detallado: `specs/016-comentarios-review/contracts/cli-porcelain.md`.
Esta ampliación no habilita otros verbos ni interpretación de Markdown en el cliente.

| Operación | Invocación permitida |
|---|---|
| Estado independiente | `comments status --porcelain [--context <id> | --all]` |
| Crear un documento | `comments init --document <local|shared> [--context <id>] [context-options] [guards]` |
| Capturar | `comments add --document <local|shared> --stdin [context-options] [location-options] [guards]` |
| Eliminar documento activo | `comments delete --document <local|shared> --context <id> --expect-context <guard> --expect-document <revision>` |
| Renumerar | `comments renumber --document <local|shared> [--context <id>] [guards]` |
| Selector | `comments entries --document <local|shared> --context <id> --porcelain` |
| Histórico | `comments diff --document <local|shared> --context <id> --entry <ordinal> [--porcelain] [guards]` |
| Conservar comparación | `comments save --expect-context <guard> --expect-local <revision> --expect-shared <revision>` |
| Entrega pendiente | `comments prepare --context <id> [--check --porcelain] [guards]` |
| Contenido histórico | `git cat-file blob <OID completo de comment-blob>`, con `GIT_NO_LAZY_FETCH=1` |

`context-options` es una elección explícita `--new-context` o `--use-context <id>`.
`location-options` admite `--path`, `--side`, `--start-line`, `--end-line`,
`--base`, `--head`, `--base-path`, `--head-path` y `--unversioned`.
`guards` conserva `--expect-context` y las revisiones exactas de documento.
El cuerpo no entra en argv ni logs; stdin se cierra. Un lado vacío se representa
sólo cuando la CLI declara `absent`. La comparación de prosa de Prepare usa los
archivos de `comments-delivery-file` y no crea una sesión de código histórica.
El selector de comentarios consume `comment-body` (líneas escapadas) y
`comment-scope` de `entries`; muestra fragmento, ubicación y detalle completo.
La receta de diff se pide con el mismo ordinal y revisión de documento. Delete
admite resultados de Finish además de preparaciones activas y nunca borra la
copia entregada. El visor mantiene la prosa accesible y señala el rango original.

Las capturas exactas de `comments add` envían `--start-column` y `--end-column`
junto con ambos extremos de línea, en unidades UTF-16 1-based y con fin
exclusivo. `entries` y `diff --porcelain` emiten el registro opcional
`comment-columns` (ordinal, lado, columna inicial, columna final). Los clientes
lo asocian por ordinal y lado; si falta, conservan las líneas inclusivas de
los comentarios anteriores. Archivo/general no envía columnas.

El explorador permite `comments delete --document <local|shared> --context <id> --entry <ordinal> --expect-context <token> --expect-document <revision>` para borrar una entrada física sin renumerar ni cambiar las demás. Sólo se ofrece en preparaciones activas o resultados retenidos; tras borrar se vuelve a consultar `entries --porcelain`. Los comentarios generales no ofrecen abrir un diff.

La captura usa `comments-capability <init|add> <local|shared>` de `comments status
--porcelain`: compare ofrece sólo Local. Un único destino se envía explícitamente
sin selector; varios requieren elección por captura. No hay acción Save comments: las
notas de compare se conservan automáticamente al cerrar o limpiar la comparación.
