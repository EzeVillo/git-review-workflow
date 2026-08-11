# Contrato: invocaciones permitidas (enmienda 006)

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

### `git review clean [--keep-fixes] [<branch>]`

| Argumento      | Cuándo                                                                                     |
|----------------|--------------------------------------------------------------------------------------------|
| *(ninguno)*    | Clean all leftovers (`review/*` y, por defecto, `review-fixes/*`)                          |
| `<branch>`     | Source name verbatim (`feature/x`), nunca `review/x`                                       |
| `--keep-fixes` | Post-finish del panel: borra solo `review/<branch>` (+ undo); deja `review-fixes/<branch>` |

**Prohibido**: cualquier otro flag. El panel en `finish-pending` **debe**
pasar `--keep-fixes` (el clean “lleno” del inventario/palette sigue sin el
flag).

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
