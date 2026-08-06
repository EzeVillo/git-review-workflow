# Research: Ofertas de lectura al iniciar review

**Feature**: `008-start-layout-offers` | **Date**: 2026-08-06

## Decisión 1 — Ofertas en `config --porcelain`, no verbo nuevo ni dry-run de start

**Decision**: Extender `git review config --porcelain` con flags de contexto
(`--local` / `--offline` / `--delta`) y registros aditivos `offer` cuando se
nombra una rama.

**Rationale**: `config --porcelain` ya es el canal de “qué hay disponible
antes de que exista una review” (candidatas, base, delta). Las formas de
lectura son el mismo tipo de dato. Un `start --dry-run` predice **un** argv;
aquí hace falta **listar** opciones. Un verbo `probe` sería superficie nueva
sin ganancia sobre config.

**Alternatives considered**:

| Opción | Por qué no |
|--------|------------|
| `start --dry-run` | Encaja mal para listar; empuja a N invocaciones |
| Matriz offer por todos los orígenes en una sola llamada sin flags | Contrato denso; el wizard ya eligió origen |
| Extensión lee `git show tip:.review/walkthrough.md` | Viola “no deriva estado / no parsea sidecar” |

## Decisión 2 — Eliminar layout `auto` en la extensión; whole unificado

**Decision**: `ReviewLayout = "walk" | "keys" | "step" | "whole"`. No existe
`auto`. El id de producto para el diff entero es siempre **whole** (tanto si
no hay walk como si se ignora el walkthrough). Argv: `whole` → siempre
`--no-walk`; `walk` → sin flag de layout (la CLI detecta walk en el tip).

**Rationale**: “Automatic” ocultaba walk vs whole. Un solo nombre **whole**
es más claro que “Ignore the walkthrough” cuando no hay walkthrough.
`--no-walk` es idempotente sin sidecar, así el mapeo intent→argv es 1:1 sin
ramas.

**Alternatives considered**:

| Opción | Por qué no |
|--------|------------|
| Mantener `auto` + badges | Sigue opaco en la confirmación |
| Ids `whole` y `no-walk` distintos | Ruido de producto; el usuario no distingue “whole por defecto” vs “forzar whole” |
| Exigir `--walk` en la CLI | Rompe el bare-start de terminal; fuera de alcance (spec) |

## Decisión 3 — Solo `walk` es recommended; keys solo available

**Decision**: `rank` del registro `offer` es `recommended` únicamente en
`walk` cuando se emite. `keys`, `step`, `whole` usan `available`. Sin walk
usable no hay ningún `recommended`.

**Rationale**: Walk es el orden del autor; keys es un atajo de primer pase,
no el default. Evita dos “recomendados” que compiten.

## Decisión 4 — Orden del wizard: rama → origen → rango → lectura

**Decision**: Reordenar el asistente respecto a 005 (que hacía layout antes
de origen/rango).

**Rationale**: Walk usable y K dependen del **tip** (remoto vs local) y del
**lower bound** (full vs delta). Ofrecer layout antes era necesariamente
inesacto. Progressive disclosure de delta ya existía; se extiende a layout.

## Decisión 5 — Tip remoto del informe = tracking ref local; sin fetch

**Decision**: Con origen remoto (default de config/start sin `--local`), el
probe resuelve `refs/remotes/<remote>/<branch>` **sin** `git fetch`.
`--offline` y base offline siguen la misma política local que start. El
`start` confirmado con origen remoto **conserva** su fetch actual.

**Rationale**: El listado de candidatas ya vive de refs locales del remoto.
Meter red en el asistente reintroduce el problema de credenciales que 005
aisló en start. El usuario pidió explícitamente no-fetch en el probe.

**Race aceptada**: entre ofertas y start el remoto en el servidor puede
moverse; post-start el panel/notas de la CLI son la verdad (US4). No se
reabre el wizard solo por eso.

**Si falta el tracking ref**: error exit ≠ 0 con mensaje claro; no se emiten
offers inventadas.

## Decisión 6 — Criterio “walk usable” = misma degradación que start

**Decision**: Walk es viable sii existe walkthrough en el tip **y**
`walk_sequence(tip, lower)` tiene ≥1 path. Si el sidecar existe pero no
intersecta el rango → no `offer walk` ni `keys` (equivalente a la
degradación a whole de start, pero **antes** de crear la review).

Keys viable sii walk viable y `walk_keys_order` tiene ≥1 path.

Step y whole viables si tip y lower son resolubles (base presente para full;
marker del origen para delta).

## Decisión 7 — Fallback CLI sin registros `offer`

**Decision**: Si la invocación con contexto de rama termina exit 0 y no hay
ninguna línea `offer`, la extensión ofrece solo `whole` + `step` sin
recommended (CLI pre-008).

**Rationale**: No bloquear start en checkouts viejos; no inventar walk/keys.

## Decisión 8 — Deltas siguen emitiéndose; offers dependen de flags de origen/rango

**Decision**:

- `config --porcelain` sin rama: igual que hoy (config + candidates).
- `config --porcelain [--local|--offline] [--delta] -- <branch>`: config +
  candidates + deltas (ambos orígenes, como hoy) + **offers** para el tip y
  lower del contexto de flags (default sin `--local`/`--offline` = remoto
  sin red).

`--delta` sin marker del origen del contexto: exit ≠ 0 (el consumidor no
debería pasar `--delta` sin haber filtrado el delta del origin; defensa en
profundidad).

**Rationale**: Una sola llamada post-origen/rango alimenta validación de
delta + ofertas; reutiliza el patrón actual de la extensión.
