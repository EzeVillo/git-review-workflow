# Data Model: Submodo walk solo-keys

**Feature**: `007-walk-keys-only`

## Entidades

### ReviewSession (existente, campos nuevos)

Sesión de review activa en `review/<source>` (o guardada en
`review-saved/<source>`).

| Campo          | Origen                 | Notas                                                               |
|----------------|------------------------|---------------------------------------------------------------------|
| `mode`         | `branch.*.reviewmode`  | Sin cambio: `whole` \| `step` \| `walk`                             |
| `walkStep`     | `reviewwalkstep`       | 1-based en la **secuencia efectiva**                                |
| `walkCount`    | `reviewwalkcount`      | Grabado al start = longitud de la secuencia efectiva en ese momento |
| **`keysOnly`** | **`reviewwalkkeys=1`** | **Nuevo.** Ausencia = false. Solo válido si `mode=walk`             |

**Invariantes**:

1. Si `keysOnly` entonces `mode=walk`.
2. Si `mode=walk` y no `keysOnly`, secuencia = `walk_reading_order` (curated +
   uncovered), como hoy.
3. Si `keysOnly`, secuencia = keys en rango (ver abajo); `walkStep ∈ 1..total`.
4. `keysOnly` no altera tip/base/source/working tree materializado.

### EffectiveSequence (derivada, no persistida)

Lista ordenada de paths que consumen `next`/`prev`, `status` y porcelain
`entry`.

| Variante      | Derivación                                                      |
|---------------|-----------------------------------------------------------------|
| walk normal   | `walk_reading_order(tip, HEAD)`                                 |
| **solo-keys** | paths de `walk_sequence(tip, HEAD)` que tienen marcador `> key` |

No se serializa. Cada verbo la re-calcula (igual que hoy con commits en step).

### EssentialEntry (concepto de walkthrough, existente)

Entrada `## N. <path>` cuyo body incluye la línea suelta `> key`. Detectada
por `walk_is_key` / el mismo grep que ya usa el producto. Solo-keys **no**
cambia el formato del sidecar.

### Porcelain view (proyección)

| Señal         | Forma                                                                    |
|---------------|--------------------------------------------------------------------------|
| Filtro activo | registro `keys` (presencia)                                              |
| Entradas      | solo las de la secuencia efectiva; `essential=1` en todas bajo solo-keys |
| Cursor        | `state.position` / `total` / `recorded` / `current` como en walk         |

## Transiciones de estado

```text
[no review]
    │ start --keys (walk aplicable, K≥1)
    ▼
[walk + keysOnly] ──next/prev──► [walk + keysOnly]  (step 1..K)
    │
    ├─ save ──► [saved walk + keysOnly] ──continue──► [walk + keysOnly]
    ├─ finish ──► [review-fixes / done]  (keysOnly muere con la rama)
    └─ abort  ──► [no review]
```

Errores que **no** crean sesión:

- `--keys` + `--step` / `--no-walk`
- `--keys` sin walk aplicable
- `--keys` con K=0

## Validación

| Regla                                    | Cuándo                              |
|------------------------------------------|-------------------------------------|
| `reviewwalkkeys` sin `reviewmode=walk`   | `finish` (y load) → corrupt, abort  |
| `walkstep` fuera de 1..total filtrado    | exit 1 o 3 (base moved), igual walk |
| Path en `--why` no en secuencia efectiva | exit 1                              |

## Relación con entidades de features previas

- No toca `readonly` (compare). Puede coexistir: `compare --keys` →
  registros `keys` + `readonly`.
- No toca marcadores `--delta` ni `reviewworkflow.base`.
- Extensión: `ReviewIntent.layout` gana un valor que implica `--keys`;
  `PanelModel` gana `keysOnly: boolean` leído del porcelain, no de config.
