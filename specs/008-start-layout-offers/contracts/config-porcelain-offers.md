# Contrato (enmienda): registros `offer` en `config --porcelain`

**Feature**: `008-start-layout-offers`

Enmienda aditiva al contrato vigente
[`005-ciclo-review-panel/contracts/config-porcelain.md`](../../005-ciclo-review-panel/contracts/config-porcelain.md).
No reemplaza ese archivo: describe el delta. La gramática porcelain v1
(líneas por tab, etiquetas desconocidas se ignoran) no cambia.

## Invocación (delta)

```sh
git review config --porcelain [--local | --offline] [--delta] [--] [<branch>]
```

| Flag | Efecto en el informe |
|------|----------------------|
| *(sin `--local`/`--offline`)* | Contexto de **origen remoto** para ofertas: tip = `refs/remotes/<remote>/<branch>`. **No** hace `git fetch`. |
| `--local` | Origen local: tip = `refs/heads/<branch>`. Base del rango full sigue la política de start en modo local (base remota si está disponible en tracking, sin fetch nuevo). |
| `--offline` | Origen offline: tip y base solo locales; sin red. |
| `--delta` | Rango incremental: lower bound desde el marker del **origin del contexto** (`remote` vs `local`/`offline`). Sin marker → exit `1`, stderr claro, sin filas `offer`. |
| `<branch>` | Obligatorio para emitir `delta` (como hoy) y para emitir `offer`. Sin rama: comportamiento previo (config + candidates solamente). |

**Mutua exclusión**: `--local` y `--offline` no se combinan (exit `1`).

**Compatibilidad**: sin los flags nuevos, un consumidor que solo pedía
`--porcelain [<branch>]` sigue recibiendo config, candidates y deltas.
**Además**, cuando hay `<branch>`, esta feature emite `offer` para el
contexto default (remoto, full) si el tip/lower resuelven. Un consumidor
que no conoce `offer` las ignora.

Los flags `--local` / `--offline` / `--delta` en `config` **solo** afectan
resolución de ofertas (y validación de `--delta`); no escriben config ni
crean ramas.

## Registro `offer` (cero o más)

```text
offer<TAB>id<TAB>rank
```

- `id`: `walk` | `keys` | `step` | `whole`
- `rank`: `recommended` | `available`
- **Orden de emisión** (estable): walk, keys, step, whole — omitiendo ids
  no viables. Nunca reordenar por locale.
- **Cuándo**: solo si la invocación nombra `<branch>` y tip+lower del
  contexto son resolubles. Si el tip no existe (p. ej. sin
  `refs/remotes/<remote>/<branch>`), exit `1` y **ningún** `offer` (también
  puede omitirse el resto del porcelain o emitirse config/candidates antes
  del error: la implementación MUST fallar de forma que el consumidor no
  tome un set de offers vacío como “solo whole+step por CLI vieja” cuando el
  fallo es “tip missing”. Preferido: exit ≠ 0 con stderr).

### Reglas de viabilidad

| id | Emitir cuando |
|----|----------------|
| `walk` | Existe walkthrough en el tip y `walk_sequence(tip, lower)` tiene ≥1 path |
| `keys` | Se emite `walk` y `walk_keys_order(tip, lower)` tiene ≥1 path |
| `step` | tip+lower resolubles |
| `whole` | tip+lower resolubles |

| rank | Regla |
|------|--------|
| `recommended` | **Solo** `walk`, y solo cuando se emite `walk` |
| `available` | Todo lo demás emitido |

**Invariantes**:

1. Si hay `keys`, hay `walk`.
2. Como máximo un `recommended` por informe.
3. Sidecar stale (0 entradas en rango): no `walk`, no `keys`; sí `step` y
   `whole` con `available`.

### Ejemplos

Remoto, full, walk con 2 keys:

```text
config	base	main
config	remote	origin
candidate	feature/x	remote	0
…
delta	feature/x	abc…	remote
offer	walk	recommended
offer	keys	available
offer	step	available
offer	whole	available
```

Local, full, sin walkthrough:

```text
…
offer	step	available
offer	whole	available
```

Delta que no intersecta el walkthrough:

```text
…
offer	step	available
offer	whole	available
```

## Costo

Procesos acotados: rev-parse del tip, resolución de lower (config +
merge-base según start), como máximo una lectura de walkthrough y pases de
secuencia/keys ya existentes en lib. **Prohibido** un proceso por path del
PR. **Prohibido** `git fetch` en este camino.

## Salida humana

Sin cambio obligatorio: la forma no-porcelain de `config` no lista ofertas
en v1 (dato machine-readable para el asistente).

## Exit codes

| Code | Significado (delta sobre 005) |
|------|-------------------------------|
| `0` | Éxito; puede haber cero `offer` solo si no se nombró rama (o implementación que no emite offers sin contexto — ver arriba: con rama y tip OK siempre hay al menos step+whole). |
| `1` | Error de uso, no es repo, tip no encontrado, `--delta` sin marker del origin del contexto, flags incompatibles. |
