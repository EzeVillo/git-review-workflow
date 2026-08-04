# Data Model: El ciclo de una review, completo desde el panel

Las entidades que esta feature agrega, y las transiciones de estado que el panel
tiene que poder describir. Extiende el modelo de
[`002`](../002-extension-vscode/data-model.md) sin reemplazarlo: `ReviewState`,
`Entry`, `PathRef`, `Why` y `Situation` siguen siendo los de aquella feature.

Regla que atraviesa todo el documento y que ya venía de `001`: **omitir, nunca en
blanco, nunca un centinela**. Un dato ausente no se emite; no se emite vacío ni
como `?`, `none` o `-1`.

---

## Del lado de la CLI

### `EffectiveConfig` — cómo se armaría una review acá

Lo que responde `git review config --porcelain`. Existe **con o sin review
activa**; es la respuesta a "cómo se armaría", no a "cómo está armada".

| Campo | Tipo | Presencia | Notas |
|-------|------|-----------|-------|
| `base` | nombre de rama | Opcional | La rama contra la que se arma el rango. Ausente = sin configurar, que es un estado normal y la razón de FR-010. |
| `remote` | nombre de remoto | Siempre | El efectivo. `origin` cuando no hay nada configurado — la CLI ya tiene ese default (`bin/git-review-verbs/start:158`), así que el consumidor nunca tiene que conocerlo. |

**Invariante**: ningún campo revela dónde está guardado. Que hoy `base` viva en
`reviewworkflow.base` es interno; moverlo no cambia esta salida (FR-008).

### `CandidateBranch` — una rama que se puede elegir

| Campo | Tipo | Presencia | Notas |
|-------|------|-----------|-------|
| `name` | nombre de rama | Siempre | Sin el prefijo del namespace: `feature/checkout`, no `refs/remotes/origin/feature/checkout`. Es el valor que vuelve a la CLI como argumento. |
| `origin` | `remote` \| `local` | Siempre | De qué namespace salió. Decide cuál corresponde ofrecer según el origen elegido (FR-009b). |
| `current` | `0` \| `1` | Siempre | Si es la rama que `HEAD` tiene ahora. El panel la propone primera (FR-011). |

**Exclusiones** (FR-009b): las tres familias propias del producto —`review/*`,
`review-saved/*`, `review-fixes/*`— nunca son candidatas. Es lo que `start` ya
rechaza explícitamente, así que ofrecerlas sería ofrecer un fallo.

**Duplicados**: una rama puede aparecer **dos veces**, una por origen, y eso es
información, no ruido: significa que existe local y remota, que es justo el caso
donde el eje `--local` cambia qué se revisa.

**Sobre el `name` como argumento**: vale la misma regla que `002` fijó para el
`name` de `list` — git prohíbe tabs, espacios y caracteres de control en un
nombre de rama, así que el campo es el nombre byte por byte y puede volver a la
CLI tal cual. No aplica el des-citado de paths.

### `FinishState` — el estado de un cierre que no terminó de resolverse

La entidad nueva más importante: es lo que hoy el contrato **no puede decir**.

| Valor | Qué significa | Dónde queda `HEAD` | Salidas |
|-------|----------------|--------------------|---------|
| `pending` | Un cierre se completó y todavía no se deshizo ni se aceptó. Hay un punto de undo vivo. | Fuera de `review/*` (en `review-fixes/<src>`, o en la rama del PR con `--onto-source`) | Deshacerlo, o simplemente seguir: aceptar el resultado es commitear en esa rama y dejar de mirar atrás. |
| `conflict` | Un cierre se frenó porque ediciones bancadas chocaron con el tip. El working tree tiene marcadores. | En `review/<src>` | Resolver y continuar, o dar marcha atrás. |

**Los dos son estados de la review, no de la rama en la que estás parado.** Por
eso `pending` se observa desde el inventario (`list`) y `conflict` desde el
estado de la review actual (`status`): ver
[`contracts/finish-state.md`](contracts/finish-state.md).

Cada uno lleva además **`onto`** (`1`/`0`): si el cierre en curso iba sobre la
rama del PR o sobre una rama de arreglos aparte. No es decorativo — continuar un
cierre trabado es `finish --resume [--onto-source]` y el flag tiene que ser el
mismo con el que empezó, así que el consumidor necesita el dato para invocar
bien. Recordarlo del lado del editor funcionaría hasta el primer reinicio, y ahí
el resume mandaría las ediciones a otro lado en silencio.

**Cardinalidad**: a lo sumo uno por review. La CLI ya lo garantiza —`finish`
rechaza empezar otro mientras hay uno sin resolver
(`bin/git-review-verbs/finish:364-373`)— así que el consumidor no tiene que
resolver ambigüedades.

**Ausencia**: una review sin cierre en curso **no emite el registro**. No hay un
tercer valor `none`.

---

## Del lado de la extensión

### `Situation`, ampliada

El tipo de `002` gana dos miembros. El mapeo desde la CLI deja de ser sólo por
exit code, porque los estados nuevos son ortogonales a él:

| `Situation` | Cómo se determina | Qué muestra el panel |
|-------------|-------------------|-----------------------|
| `review` | exit `0` sin registro `finish` | Lo de siempre |
| `finish-conflict` | exit `0` **con** registro `finish conflict` | La review, con la navegación bloqueada (FR-027) y las dos salidas |
| `finish-pending` | exit `2` **y** el inventario reporta un cierre `pending` | El estado vacío, pero encabezado por el cierre pendiente en vez de "no hay ninguna review" |
| `no-review` | exit `2` sin ningún cierre pendiente | Lo de siempre |
| `out-of-range`, `error`, `cli-missing`, `cli-outdated` | Sin cambios | Sin cambios |

**Precedencia**: `finish-conflict` gana sobre `review`, y `finish-pending` sobre
`no-review`. Nunca al revés: un cierre sin resolver es siempre lo primero que hay
que contar.

**Compatibilidad**: contra una CLI `0.3.x` el registro no llega nunca, así que
las dos situaciones nuevas no se alcanzan y el panel se comporta como antes. No
hace falta una rama de código para "CLI vieja" más allá del aviso que ya existe.

### `ReviewIntent` — la review que todavía no existe

Lo que el asistente arma entre que el revisor empieza a elegir y confirma. **No
se persiste**: si el asistente se cancela, no queda nada.

| Campo | Valores | Default |
|-------|---------|---------|
| `branch` | nombre de una `CandidateBranch` | La rama actual |
| `layout` | `auto` \| `step` \| `no-walk` | `auto` |
| `range` | `full` \| `delta` | `full` |
| `source` | `remote` \| `local` \| `offline` | El ajuste `gitReview.defaultSource` |

**Reglas de validez, todas leídas del reporte de la CLI y ninguna adivinada**:

- `range = delta` sólo se ofrece si el reporte indica que hay un punto de
  referencia previo para esa rama (FR-015).
- Con `source = local` u `offline`, las candidatas que se ofrecen son las de
  origen `local`; con `remote`, las remotas.
- Todo lo demás —working tree sucio, review ya existente, rama que no resuelve—
  **no se valida acá**. Se deja fallar y se muestra el diagnóstico (FR-032).

**Traducción a argumentos**: es la única función que convierte esta entidad en
argv, y es pura y testeable sin editor. Sus salidas están enumeradas —y acotadas—
en [`contracts/cli-invocation.md`](contracts/cli-invocation.md). Emite siempre
`--` antes del nombre de rama: una rama que empieza con guion es legal en git y
sin el separador la leería el parseo de opciones del verbo.

### `SourcePreference` — lo único que se recuerda

Un ajuste del host (`gitReview.defaultSource`), no estado del producto. Alcance
usuario con sobrescritura por workspace, que es lo que el host ya da (FR-016a).
No viaja a la CLI: sólo decide qué ítem viene preseleccionado.

### `StateToken` — el testigo contra la premisa caduca

Capturado al armar un diálogo, revalidado después de confirmar (FR-038).

| Campo | Por qué está |
|-------|--------------|
| `situation` | Si cambió, el diálogo ya no describe la realidad |
| `branch` | La review sobre la que se decidió |
| `tip` | Detecta que la review se rehízo sobre otro snapshot mientras el modal esperaba |

Si el testigo no coincide al confirmar, **no se invoca nada** y se informa que el
estado cambió. Es una comparación de tres strings sobre datos que el refresco ya
trae; no cuesta una invocación extra.

---

## Transiciones

Las que esta feature agrega al ciclo. Cada arista es un verbo de la CLI; ninguna
la produce la extensión por su cuenta.

```text
                    ┌──────────── abort ────────────┐
                    ↓                               │
              (no hay review) ──── start ──→ (review activa) ──── save ──→ (review pausada)
                    ↑                          │        ↑                        │
                    │                          │        └──── continue ──────────┘
                    │                       finish
                    │                          │
                    │              ┌───────────┴───────────┐
                    │              ↓                       ↓
                    │      (cierre pendiente)     (cierre trabado)
                    │              │                  │         │
                    └── aceptar ───┘                  │      finish --abort
                       (commitear)                    │         │
                             ↑                        │         ↓
                             └──── finish --resume ───┘   (review activa)
                                                                ↑
                             finish --abort ────────────────────┘
```

**Lecturas del diagrama que importan para el panel**:

- `start` es la única arista que **accede a la red**, y por eso la única con la
  ruta de credenciales de la Decisión 5.
- `finish` es la única con **dos destinos posibles**, y cuál se alcanza no lo
  decide el usuario: lo decide si las ediciones bancadas chocan o no.
- Todo estado tiene al menos una arista de salida hacia un estado anterior. Es el
  criterio de admisión (punto 2) hecho diagrama: no hay callejones.
- "Aceptar" un cierre pendiente **no es un verbo**: es commitear en la rama que el
  cierre produjo, que ya es superficie del editor. El panel no lo ofrece; sólo
  deja de reportar el cierre cuando la CLI deja de reportarlo.
