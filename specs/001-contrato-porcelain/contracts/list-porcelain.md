# Contrato: `git review list --porcelain`

Mismo formato porcelain v1 que `status --porcelain` (líneas etiquetadas,
campos separados por tab, ver `contracts/status-porcelain.md`). Cubre US6
(FR-020): inventario de todas las reviews del repositorio, activas y
guardadas.

## Invocación

```
git review list --porcelain
```

No requiere estar dentro de una review — enumera todas las que existan en el
repositorio. Cero mutación (FR-022).

### Exit codes

| Code | Significado                                                              |
|------|--------------------------------------------------------------------------|
| `0`  | listado emitido, incluso si está vacío (ausencia de reviews no es error) |
| `1`  | error: no es un repositorio git                                          |

Ni `2` ("no hay review activa") ni `3` ("cursor fuera de rango") aplican acá —
un inventario vacío es un
resultado válido, no la ausencia de algo que se esperaba encontrar
(distinto del caso de `status`, donde la invocación *asume* estar dentro de
una review concreta).

## Registro `branch` (cero o más, uno por rama de review)

```
branch<TAB>name<TAB>saved<TAB>current<TAB>orphan[<TAB>mode[<TAB>position<TAB>total]]
```

- `name`: nombre de la rama (`review/<x>` o `review-saved/<x>`).
- `saved`: `1` si la rama está bajo `review-saved/`, si no `0`.
- `current`: `1` si es la rama en la que está parado HEAD, si no `0`.
- `orphan`: `1` si la rama no tiene `reviewsource` (metadata ausente —
  Acceptance Scenario 2 de US6). Cuando `orphan = 1`, no hay campos `mode`,
  `position` ni `total`: no hay metadata de la que derivarlos.
- `mode`: `whole` | `step` | `walk`, ausente si `orphan = 1`.
- `position`, `total`: presentes sólo si `mode` es `step` o `walk` **y** las dos
  claves de config existen. Se leen de la config de la rama
  (`reviewstep`/`reviewcount` en step, `reviewwalkstep`/`reviewwalkcount` en
  walk): son los mismos valores que muestra `list` humano, **no** el resultado
  de re-derivar la secuencia (ver `research.md`, Decisión 7). Si falta alguna
  de las dos, ambos campos se omiten — el contrato nunca emite el `?` que la
  salida humana usa como relleno visual.

Ojo con la diferencia respecto de `status --porcelain`: ahí `total` es el total
derivado en el momento y `recorded` el registrado al iniciar. Acá hay un solo
número, el registrado. Un inventario no re-deriva la secuencia de cada rama del
repositorio; un consumidor que necesite el número exacto de una review concreta
corre `status --porcelain` estando en ella.

## Registro `fixes` (cero o más, uno por rama `review-fixes/*`)

```
fixes<TAB>name<TAB>current<TAB>session<TAB>state
```

Se emite **después de todos los registros `branch`** (y de sus `branch-draft` /
`finish`): no son reviews —no hay nada que retomar ni que abortar en ellas— y
una posición fija deja a `tests/porcelain-bytes.bats` comparando contra una
salida determinada.

- `name`: nombre de la rama (`review-fixes/<x>`).
- `current`: `1` si es la rama en la que está parado HEAD, si no `0`. Es la
  única rama que `clean` nunca borra, así que un cliente la muestra sin acción
  de descarte.
- `session`: `1` si `review/<x>` todavía existe. Es lo que separa el caso en que
  `git review clean <x>` alcanza del caso en que hace falta `--fixes-only` para
  no llevarse la sesión por delante.
- `state`: cuánto trabajo cuesta descartarla.

| `state`    | Significado                                                                    |
|------------|--------------------------------------------------------------------------------|
| `empty`    | la punta coincide con la de su rama de origen (local o remote-tracking)        |
| `merged`   | contenida en `reviewworkflow.base` (o en `<remote>/<base>` si no hay local)    |
| `unmerged` | tiene commits que la base no tiene                                             |
| `unknown`  | no hay `reviewworkflow.base` utilizable: no hay contra qué comparar            |

`empty` se resuelve **primero y sin mirar la base**: `finish` deja las ediciones
*staged*, no commiteadas, así que una rama de fixes en la que nunca commiteaste
sigue apuntando exactamente donde la creó el finish y no contiene nada tuyo. Como
esa punta es la del PR —que la base normalmente **no** contiene—, el test de
merged por sí solo la reportaría como trabajo a punto de perderse cuando no hay
ninguno.

El costo es de un número **constante** de procesos, no proporcional a la
cantidad de ramas: un `for-each-ref` para las fixes con su punta, uno para las
puntas de las fuentes (con los patrones armados a partir de los nombres de las
fixes, no enumerando `refs/heads`) y uno `--merged`. Este verbo lo invoca el
panel en cada refresco.

Ejemplo (dos activas — una en step, una huérfana — y una guardada en walk):

```
branch	review/feat-x	0	1	0	step	3	9
branch	review/orphan	0	0	1
branch	review-saved/feat-y	1	0	0	walk	2	5
```

Con una rama de fixes cuya review sigue abierta y otra ya integrada en la base:

```
branch	review/feat-x	0	1	0	step	3	9
fixes	review-fixes/feat-x	0	1	empty
fixes	review-fixes/feat-w	0	0	merged
```

Sin reviews ni ramas de fixes en el repositorio: sin líneas, exit `0`. La
presencia de `review-fixes/*` **sí** produce salida aunque no haya ninguna
review: son el único leftover que ninguna superficie nombraba.
