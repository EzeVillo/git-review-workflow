# Contrato: `git review walkthrough draft`

**Feature**: `011-walkthrough-draft-revisor`

Subcomando nuevo del verbo `walkthrough`. `init` y `build` no cambian.

## Invocación

```sh
git review walkthrough draft [--local | --offline] [--delta] [--force] [--] [<branch>]
git review walkthrough draft --build [--local | --offline] [--delta] [--] [<branch>]
```

| Argumento | Significado |
| --- | --- |
| `<branch>` | Rama bajo review. Default: la rama actual. Mismo posicional que `git review start`. |
| `--build` | Valida el borrador existente en vez de crearlo. |
| `--force` | Sobrescribe un borrador existente (sólo sin `--build`). |
| `--local` | Tip local (`refs/heads/<branch>`) en vez del remoto. |
| `--offline` | Tip y base sólo locales. |
| `--delta` | Rango incremental desde el marcador del origen del contexto. |
| `--` | Cierra el parseo de opciones. |

**Mutua exclusión**: `--local` y `--offline` no se combinan. `--force` con
`--build` es error de uso.

**Sin red**: como `config --porcelain`, resuelve el tip desde las refs ya
presentes en el clon. Nunca hace `fetch`. Un tip remoto ausente es error
accionable, no un fetch implícito.

## Resolución del rango

Idéntica a la de `emit_reading_offers`, y por lo tanto a la que usará el
`start` correspondiente:

1. `tip` = `refs/remotes/<remote>/<branch>` (o `refs/heads/<branch>` con
   `--local`/`--offline`).
2. `base` = `reviewworkflow.base`; sin ella, error accionable.
3. `start` = marcador de `--delta`, o `merge-base(baseref, tip)`.
4. `lower` = `fold_lower(start, baseref, tip)` — pliega la base ya integrada.
5. Archivos = `changed_paths(lower, tip)` menos `.review/`.

Esto es lo que garantiza FR-002: el esqueleto lista exactamente lo que la review
va a cubrir.

## Comportamiento — crear (sin `--build`)

| Condición | Salida | Exit |
| --- | --- | --- |
| Éxito | Escribe el esqueleto; imprime la ruta y el número de archivos, más la instrucción de completarlo y validarlo | `0` |
| Éxito, y el tip trae walkthrough del autor | Lo anterior **más** una nota en stderr: el borrador tendrá precedencia sobre el walkthrough del PR mientras exista (FR-005a). Nota, no rechazo | `0` |
| Ya existe borrador, sin `--force` | `error: <ruta> already exists; pass --force to overwrite` | `1` |
| Sin `reviewworkflow.base` | El mismo mensaje accionable que ya emiten `start` y `walkthrough init` | `1` |
| Rama o tip inexistente | `error: <label> not found` | `1` |
| Sin cambios vs la base | `error: no changes vs <base>; nothing to walk through` | `1` |
| `--delta` sin marcador previo | El mismo mensaje que hoy da esa condición | `1` |

El esqueleto es **byte por byte el mismo** que produce `init` (misma función
generadora): encabezado, comentario de instrucciones, sección `## Heads-up` y
una entrada `## ?. <path>` con su placeholder `<!-- why: -->` por archivo.

**Invariante**: en ningún caso —éxito o error— se modifica el índice, el árbol
de trabajo ni ninguna ref. `git status` antes y después es idéntico.

## Comportamiento — validar (`--build`)

Reusa el cuerpo de validación de `build`, contra el rango resuelto arriba:
placeholders sin completar, encabezados mal formados, `> key` con valor, rutas
duplicadas y drift. En éxito reescribe el borrador canónicamente (ordenado por
los números del autor, renumerado `1..N`, marcador `> key` normalizado y
elevado, líneas en blanco recortadas).

| Condición | Salida | Exit |
| --- | --- | --- |
| Válido | `walkthrough draft ok: <n> entries[ (<k> key)], in sync with <branch>` y reescritura canónica | `0` |
| No existe borrador | `error: no draft for <branch>; run git review walkthrough draft first` | `1` |
| Cualquier rechazo de validación | El mensaje específico de esa regla, en stderr | `1` |

Las notas de selectividad de `> key` (todas marcadas / ninguna con ≥6 entradas)
se emiten como nota en stderr y **no** afectan el exit code.

## Efecto sobre otros verbos

| Verbo | Efecto |
| --- | --- |
| `start <branch>` | Si hay borrador para `<branch>`, entra en walk sobre él. Si no hay borrador ni sidecar, imprime una nota accionable señalando `walkthrough draft`. |
| `compare <a> <b>` | Usa el borrador cuando el argumento nombra una rama con borrador; con revisiones sueltas (SHA/tag) usa el walkthrough del autor. |
| `list` | Marca `(draft)` junto al modo `walk`, en reviews activas y pausadas. |
| `save` | Mueve el borrador de `review-walkthrough/` a `review-saved-walkthrough/`. |
| `continue` | Movimiento inverso, antes de reconstruir el estado de la review. |
| `clean` | Poda `review-walkthrough/`, nunca `review-saved-walkthrough/`. |
| `forget --saved <branch>` | Borra también el borrador guardado de esa rama. |
| `finish` | No lo toca. El borrador no aparece jamás en `review-fixes/`. |

## Compatibilidad

Aditivo puro: ningún flag, salida ni exit code existente cambia. Un repositorio
sin borradores se comporta exactamente como hoy en todos los verbos.
