# Data Model: 009-plugin-intellij

Modelo de dominio del plugin. Independiente de Swing/IntelliJ Platform.
Alineado al código de `vscode-extension/src/cli/*`, `review/situation.ts`,
`views/panelModel.ts` y `review/state.ts`.

## Situation

```text
cli-missing | cli-outdated | no-review | finish-pending
| review | finish-conflict | out-of-range | error
```

### Derivación

```text
sin cwd único                     → error
--version falla / exit ≠ 0        → cli-missing
versión < min o formato inválido  → cli-outdated
status --porcelain:
  exit 0 + finish conflict        → finish-conflict
  exit 0                          → review
  exit 2 + list finish pending    → finish-pending
  exit 2                          → no-review
  exit 3                          → out-of-range
  timeout / otro                  → error
```

`isReviewReadable` = `review | finish-conflict`.  
Navegación next/prev solo si `situation == review`.

## PathRef

| Campo | Uso |
|-------|-----|
| `raw` | Bytes/string tal cual porcelain; argv de `status --why` |
| `display` | Unquoted para UI y paths de filesystem |

## StateRecord (status)

| Campo | whole | step | walk |
|-------|-------|------|------|
| branch, source, tip | ✓ | ✓ | ✓ |
| mode | whole | step | walk |
| walkthrough | none/applied/degraded | none | applied/degraded… |
| position, total, recorded | — | ✓ | ✓ |
| current | — | SHA short | PathRef |
| essential | — | — | en state y entry |

## EntryRecord

| Campo | whole | step | walk |
|-------|-------|------|------|
| position | ✓ | ✓ | ✓ |
| id | PathRef | SHA | PathRef |
| essential / annotated | — | — | ✓ |
| banked | — | ✓ | — |

Maps opcionales step: `subjects`, `authors` por position.  
Opcionales de status: `base` (whole), `finish{conflict,onto}`, `readonly`, `keysOnly`.

## BranchRecord (list)

`name`, `saved`, `current`, `orphan`, `mode?`, `position?`, `total?`,
`finish?{pending|conflict, onto}`.

`sourceOf(name)`: quita prefijo `review-saved/` o `review/`.

## EffectiveConfig / candidates / remotes / delta / offer

Parse de `config --porcelain` — idéntico a `configPorcelain.ts`:

- `config base` (omit si unset), `config remote` (default origin)
- `candidate`, `remote-candidate`, `delta`, `offer` (walk|keys|step|whole × recommended|available)

## ReviewState

Agregado en memoria del host tras un refresh:

- `situation`
- `state?`, `entries`, `branches`
- `config?`, `candidates?`, `remotes?`
- `subjects?`, `authors?`, `base?`, `finish?`, `readonly?`, `keysOnly?`
- `stderr?` en situaciones de fallo

Reglas: list/config **solo** en no-review / finish-pending; fallo de list/config
no cambia situation.

## PanelModel

Proyección plana para UI (paridad `panelModel.ts`):

- situation, busy, repoLabel?
- reviews[] (inventario), pendingFinish?, noBaseConfigured, configuredBase?, configuredRemote?
- mode, branch, source, tip, base?, position, total, baseMoved, atFirst, atLast
- navigationLocked, degraded, readonly, keysOnly
- current?, entryCount, files[], lastOpened?, why?
- notes derivadas (solo presentación)

## ReviewIntent

Antes de start:

- `branch: String`
- `source: remote | local | offline`
- `range: full | delta`
- `layout: walk | keys | step | whole`

`intentToArgs` → lista de argv (sin verbo):

```text
[layoutFlags…][ --delta?][ --local|--offline?] -- <branch>
```

walk → sin flag de layout; keys → `--keys`; step → `--step`; whole → `--no-walk`.

## StateToken

Huella `{ branch?, tip?, situation }` capturada al abrir diálogo; revalidar
antes del spawn dentro del lock.

## MutationLock

Profundidad 1: si busy, discard + evento/aviso; no cola.

## Invocation

| Campo | Notas |
|-------|-------|
| verb | o `--version` |
| args | lista |
| cwd | root único |
| gitReviewPath? | setting |
| network | env anti-prompt |
| timeoutMs | por clase |

`InvocationClass` = `READ` (15 s) · `LOCAL_MUTATION` (120 s) · `NETWORK`
(300 s) · `SUPPORT_GIT` (30 s). La cuarta es el git de apoyo de los diffs
(`diff --name-status`, `diff-tree`): no invoca git-review, pero comparte el
invoker y su timeout no puede quedar como constante suelta en `diff/`.

## ResolvedCommand

`command` + `args` tras `resolveCommand` (git review / path / sh+path).

## HousekeepingKind

Enum cerrado → verb+args (tabla del contrato de invocación).

## LastOpenedMap

Persistencia **del IDE** (no CLI): branch de review → display path, máx. 20,
solo whole.

## Transiciones relevantes

```text
no-review --start ok--> review
review --save--> no-review (saved en list)
review --abort--> no-review
review --finish (con edits)--> finish-pending
review --finish (sin edits)--> no-review (+ posible delta)
finish-pending --undo--> review | no-review
finish-conflict --resume/abort/undo--> …
review --next/prev--> review (mismo mode, position±)
```
