# Contrato: asistente de start con ofertas de lectura

**Feature**: `008-start-layout-offers`

Enmienda el comportamiento del asistente definido en
`005-ciclo-review-panel` (Decisión 9 / FR-012) y la fila de `start` en
`cli-invocation` de 005/006/007 respecto al layout.

## Orden de pasos (normativo)

1. Rama (candidatas de `config --porcelain`)
2. Origen (`remote` | `local` | `offline`; `defaultSource` solo preselecciona)
3. Rango — **solo** si existe `delta` del origin del source elegido
4. Forma de lectura — QuickPick **solo** con ids presentes en `offer`
5. Confirmación modal con frase que nombra la forma elegida
6. `git review start` con `network: true` bajo el lock (como hoy)

Pasos 1–4 y la carga de ofertas: `network: false`.

## Carga de ofertas

Tras origen (y rango si aplica):

```text
git review config --porcelain [<--local|--offline>] [<--delta>] -- <branch>
```

| source del intent | flags |
|-------------------|--------|
| remote | *(ninguno de origen)* + opcional `--delta` |
| local | `--local` + opcional `--delta` |
| offline | `--offline` + opcional `--delta` |

Parsear filas `offer`. Si exit ≠ 0: toast con stderr; no start.

### Fallback CLI pre-008

Si exit 0 y **cero** filas `offer`: tratar como ofertas sintéticas

- `whole` / `available`
- `step` / `available`

sin walk ni keys. (No confundir con exit ≠ 0 por tip missing.)

## ReviewLayout y argv

| layout | label UI (EN, producto) | description (borrador) | argv layout |
|--------|-------------------------|------------------------|-------------|
| `walk` | Walkthrough | curated reading order from the PR | *(ninguno)* |
| `keys` | Walkthrough — keys only | only entries marked key | `--keys` |
| `step` | Commit by commit | one commit at a time | `--step` |
| `whole` | Whole diff | entire diff at once | `--no-walk` |

- Si `rank=recommended`, el ítem se presenta como recomendado (sufijo o
  description “(recommended)”) y va **primero** en el QuickPick (el host
  preselecciona el primero).
- Orden de ítems no-recommended: el del contrato (`keys`, `step`, `whole`
  tras `walk` si existe).
- **Prohibido** layout `auto` o label “Automatic”.
- **Prohibido** mostrar un id que no vino en `offer` (salvo el fallback
  sintético whole+step).

## Confirmación (FR-011)

La frase nombra la forma real, por ejemplo:

- walk: *Start reviewing \<branch\> as a walkthrough?*
- keys: *Start reviewing \<branch\>, keys only?*
- step: *Start reviewing \<branch\> commit by commit?*
- whole: *Start reviewing \<branch\> as the whole diff?*

Detail sigue mostrando `git review start …` exacto y la base si hay.

## Lista cerrada de invocaciones (delta)

| Verbo | Cuándo | network |
|-------|--------|---------|
| `config --porcelain` | Inicio del asistente | false |
| `config --porcelain … -- <branch>` | Tras origen/rango (deltas + offers) | false |
| `start …` | Tras confirmación | true |

Sin invocaciones nuevas de otros verbos. Sin lectura de
`.review/walkthrough.md` ni de `branch.*.review*` desde la extensión.

## Relación con 007

Si 007 ya añadió `keys` como ítem estático en el QuickPick, **esta feature
lo reemplaza**: keys solo aparece cuando el informe emite `offer keys`. El
argv `--keys` y el porcelain de review activa (`keys`) siguen siendo de
007; este contrato solo gobierna **cuándo** el asistente lo ofrece.
