# Data Model: Ofertas de lectura al iniciar review

**Feature**: `008-start-layout-offers`

## Entidades

### OfferContext (entrada del informe)

Parámetros con los que se piden ofertas. No se persiste.

| Campo | Valores | Notas |
|-------|---------|-------|
| `branch` | nombre sin namespace | Obligatorio para emitir `offer` |
| `source` | `remote` \| `local` \| `offline` | Default CLI = remote (sin flags) |
| `range` | `full` \| `delta` | `delta` exige marker del origin de `source` |

**Resolución tip** (sin red):

| source | tip |
|--------|-----|
| remote | `refs/remotes/<remote>/<branch>` |
| local | `refs/heads/<branch>` |
| offline | `refs/heads/<branch>` |

**Resolución lower** (alineada con start, sin crear rama):

| range | lower (resumen) |
|-------|-----------------|
| full | merge-base / fold_lower contra la base efectiva del source (remota salvo offline) |
| delta | lower bound desde el tip reviewed del marker del origin de source |

Si tip o lower no resuelven → el informe falla (no hay ofertas parciales
mentirosas).

### ReadingOffer (registro porcelain)

Una forma de lectura viable. Cero o más por informe.

| Campo | Valores | Notas |
|-------|---------|-------|
| `id` | `walk` \| `keys` \| `step` \| `whole` | Identificador estable |
| `rank` | `recommended` \| `available` | Solo `walk` puede ser `recommended` |

**Reglas de emisión** (todas deben cumplirse para incluir el id):

| id | Condición | rank |
|----|-----------|------|
| `walk` | walkthrough en tip y ≥1 entrada en `walk_sequence(tip,lower)` | `recommended` |
| `keys` | `walk` viable y ≥1 path en `walk_keys_order(tip,lower)` | `available` |
| `step` | tip+lower resolubles | `available` |
| `whole` | tip+lower resolubles | `available` |

**Invariantes**:

1. Nunca `keys` sin que también se emita `walk`.
2. Nunca dos `recommended` en el mismo informe.
3. Sin walk usable: solo `step` + `whole`, ambos `available`.
4. Con walk usable: `walk` + `step` + `whole` [+ `keys` si K≥1].
5. Orden de emisión estable: `walk`, `keys`, `step`, `whole` (omitir los
   que no apliquen).

### ReviewIntent (extensión — enmienda)

Intent armado por el asistente antes de confirmar.

| Campo | Tipo (008) | Notas |
|-------|------------|-------|
| `branch` | string | Siempre explícito en el asistente |
| `layout` | `walk` \| `keys` \| `step` \| `whole` | **Eliminado** `auto` |
| `range` | `full` \| `delta` | Sin cambio |
| `source` | `remote` \| `local` \| `offline` | Sin cambio |

**Traducción a argv de start**:

| layout | flags de layout |
|--------|-----------------|
| `walk` | *(ninguno)* |
| `keys` | `--keys` |
| `step` | `--step` |
| `whole` | `--no-walk` |

Más `--delta` / `--local` / `--offline` / `-- <branch>` como hoy.

### EffectiveConfig / CandidateBranch / DeltaRecord

Sin cambio de forma (005). El informe con rama sigue emitiendo `delta` de
ambos orígenes cuando existen markers.

## Relaciones

```text
OfferContext ──resuelve──► tip, lower
     │
     ▼
ReadingOffer[]  ──consume──►  asistente (QuickPick)
     │
     ▼
ReviewIntent.layout  ──intentToArgs──►  git review start …
```

## Validación

| Regla | Dónde |
|-------|--------|
| `range=delta` sin delta del origin de source | CLI del informe y `validateIntent` |
| layout no presente en offers | UI no lo ofrece; no revalidar en CLI de start salvo fallos naturales (`--keys` con K=0) |
| CLI sin ninguna línea `offer` | Extensión: fallback whole+step available |
| Tip tracking ausente (remote) | Informe exit ≠ 0 |

## Transiciones (asistente)

```text
[no-review]
  → pick branch
  → pick source
  → [si delta del origin] pick range  |  else range=full
  → load offers(context)
  → pick layout ∈ offers
  → confirm
  → start(argv)
  → [active review]
```

Cancelación en cualquier flecha: sin mutación.
