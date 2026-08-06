# Contrato (enmienda): registro `keys` en `status --porcelain`

**Feature**: `007-walk-keys-only`

Este documento **enmiende de forma aditiva** el contrato vigente de
[
`001-contrato-porcelain/contracts/status-porcelain.md`](../../001-contrato-porcelain/contracts/status-porcelain.md).
No reemplaza ese archivo: describe solo el delta. Tras implementar, el
texto normativo puede fusionarse en `001` o quedarse referenciado como
enmienda vigente (misma disciplina que `005` con cli-invocation).

## Registro `keys` (cero o una línea)

```text
keys
```

- **Cuándo**: la review activa está en modo walk **y** el filtro solo-keys
  está activo (`branch.<review>.reviewwalkkeys=1`).
- **Campos**: ninguno. La presencia del registro es el dato.
- **Omitido** en whole, step, y walk sin filtro (nunca `keys\t0`, nunca
  línea en blanco).
- Un consumidor que no conoce la etiqueta **la ignora** (regla general de
  `001`).

Puede coexistir con `readonly` (p. ej. `compare --keys`).

## Efecto sobre registros existentes

### `state` (walk)

Sin cambio de forma. Con solo-keys:

- `mode` sigue siendo `walk`.
- `position` / `total` / `recorded` / `current` / `essential` describen la
  **secuencia filtrada**:
    - `total` = cantidad de keys en rango **ahora**
    - `recorded` = `reviewwalkcount` grabado al start (= K al iniciar)
    - `current` = path de la key en el cursor
    - `essential` en `state` = `1` siempre que el cursor esté en una key
      (siempre, bajo este filtro)

### `entry` (walk)

Misma forma `entry<TAB>position<TAB>path<TAB>essential<TAB>annotated`.

Con solo-keys se emite **una línea por key en la secuencia filtrada**,
posiciones `1..K` en el orden relativo del walkthrough:

- `essential` = `1` en todas
- `annotated` = `1` en todas (una key implica entrada en el sidecar)
- **No** se emiten uncovered ni entradas no-key

Un consumidor que lista `entry` para pintar el panel **no necesita
filtrar en cliente**: la CLI ya acotó el listado.

### `--why <path>`

Sin cambio de protocolo. El path debe pertenecer a la **secuencia
efectiva** (bajo solo-keys: una de las keys). Un path que es del PR pero
no es key en la secuencia → exit `1`, diagnóstico en stderr.

## Ejemplo

Walk solo-keys, 2 keys, cursor en la primera:

```text
state	review/feat-x	origin/feat-x	a1b2c3…	walk	applied	1	2	2	src/core.ts	1
entry	1	src/core.ts	1	1
entry	2	src/api.ts	1	1
keys
```

## Compatibilidad

- Consumidor pre-007: ignora `keys`; ve `mode=walk` con menos `entry` de
  las que habría sin filtro (comportamiento correcto para esa sesión).
- No se introduce porcelain v2 ni se reordenan campos de `state`.
