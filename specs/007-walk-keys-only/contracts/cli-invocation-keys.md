# Contrato (enmienda): `--keys` en invocaciones del panel

**Feature**: `007-walk-keys-only`

Enmienda aditiva al contrato vigente de invocación
([
`005-ciclo-review-panel/contracts/cli-invocation.md`](../../005-ciclo-review-panel/contracts/cli-invocation.md)
y, si `006` ya lo reemplazó, al documento que rija en ese momento). La
lista sigue **cerrada** en verbos y argumentos.

## `git review start … --keys … -- <rama>`

**Argumentos permitidos (delta)**: se agrega `--keys`.

| Argumento | De dónde sale                                                                               | Cuándo se pasa                                                                                                                                               |
|-----------|---------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `--keys`  | `ReviewIntent.layout === "keys"` (nombre exacto a fijar en implementación, p. ej. `"keys"`) | Cuando el revisor eligió el layout solo-keys. **Mutuamente excluyente** con `--step` y `--no-walk`. Con `layout = auto` / `step` / `no-walk` **no** se pasa. |

El resto de la fila de `start` (rama con `--`, `--delta`, `--local` /
`--offline`) no cambia.

**Validación en CLI** (no en el panel): combinaciones inválidas y K=0
fallan con stderr; el panel muestra el error como hoy con start.

## `git review compare … --keys` (si el panel expone compare)

Si la superficie del panel ya invoca `compare` (feature `006` o
posterior), el flag `--keys` se admite con las mismas exclusiones
(`--step` / `--no-walk`). Si el panel **aún no** expone compare, esta
fila queda como permiso futuro: la CLI lo implementa igual; el panel no
está obligado a usarlo hasta que exista la UI.

## Lectura

Sin invocaciones nuevas. El panel sigue usando solo:

- `status --porcelain` → ahora puede incluir el registro `keys`
- `status --why <raw>`
- `next` / `prev` (sin flags nuevos; la secuencia ya viene filtrada)

## Prohibiciones (sin cambio de filosofía)

- No leer `branch.*.reviewwalkkeys` desde la extensión.
- No filtrar la lista de archivos en el cliente “porque el badge dice
  key”: si porcelain no trae `keys` y trae entries mixtas, se muestran
  todas.
- No inventar un comando `git review keys` en v1.
