# Contract: CLI invocation (IntelliJ plugin client)

**Normative consumer**: `intellij-plugin/`  
**Sibling consumer**: `vscode-extension/` (misma semántica; distinta implementación)  
**Source of truth for wire format**: CLI `bin/` + parsers de referencia en
`vscode-extension/src/cli/{porcelain,configPorcelain,unquote,nameStatus}.ts`

Este documento **no redefine** porcelain de la CLI. Fija cómo el **plugin**
invoca y consume. Cualquier enmienda de wire format se hace en la CLI y se
actualiza este contrato + ambos clientes.

## Forma de toda invocación

| Setting `gitReview.path` | Plataforma | command | args |
|--------------------------|------------|---------|------|
| vacío | * | `git` | `review`, `<verb\|--version>`, … |
| path a `.exe`/`.cmd`/`.bat` | Windows | ese path | `<verb>`, … (**sin** token `review`) |
| path sin extensión nativa | Windows | `sh` | `<path>`, `<verb>`, … |
| path | POSIX | ese path | `<verb>`, … |

- **cwd** = raíz del único `RepositoryTarget`.
- **sin shell** del caller para el spawn principal (argv array).
- **stdout/stderr** decodificados como **UTF-8** siempre.
- Log de cada start/end (comando, cwd, duración, exit, timedOut).

## Timeouts por clase

| Clase | ms | Verbos |
|-------|-----|--------|
| READ | 15000 | default: status, list, config, --version, config writes |
| LOCAL_MUTATION | 120000 | finish, save, abort, continue, next, prev, clean, forget, compare, walkthrough, preview |
| NETWORK | 300000 | `start`; `forget` si args contienen `--stale` |
| SUPPORT_GIT | 30000 | git de apoyo (`diff --name-status`, `diff-tree`), no git-review — ver § Git de apoyo |

Los tres primeros valores y la regla “verbo desconocido → READ” son los de
`vscode-extension/src/cli/invoke.ts`; el cuarto es el de
`src/commands/openEntry.ts`. `config base|remote` cae en READ por ser un verbo
fuera de las listas de mutación, igual que en la extensión — es una escritura
de config, no un movimiento de refs.

Timeout propio: al vencer, destruir proceso (best-effort árbol) y devolver
`timedOut=true`, `exitCode=null` — no confundir con CLI missing.

## Entorno de red (`network=true`)

Partir del env del proceso del IDE y forzar:

- `GIT_TERMINAL_PROMPT=0`
- `GIT_ASKPASS` / `SSH_ASKPASS` → comando no-op multiplataforma embebido

Solo en invocaciones de clase red.

## Probe de versión

```text
argv: --version   (vía resolveCommand)
stdout trim → X.Y.Z
min: ver contracts/client-product-surface (canónico) = 0.4.0 al abrir esta feature
```

| Resultado | Situation |
|-----------|-----------|
| spawn error / exit ≠ 0 | cli-missing |
| parse fail o &lt; min | cli-outdated |
| ok | continuar a status |

## Lecturas de estado

| Orden | argv | Fallo |
|-------|------|-------|
| 1 | `status --porcelain` | define situation (0/2/3/else/timeout) |
| 2a si exit 2 | `list --porcelain` | fallar → branches vacías, no cambia situation |
| 2b si exit 2 o finish-pending path | `config --porcelain` | fallar → sin config, no cambia situation |
| why | `status --why <raw>` | fallar → why failed; empty → absent |

**Nunca** parsear stdout humano de mutaciones para situation.

## Mutaciones — argv exactos

| Acción | verb | args |
|--------|------|------|
| start | start | ver intent (abajo) |
| continue | continue | `[source]` |
| save | save | `[]` |
| abort | abort | `[]` |
| finish | finish | `[]` o `["--onto-source"]` |
| undo finish | finish | `["--abort"]` luego opcional `["--abort","--force"]` |
| resume finish | finish | `["--resume"]` o `["--resume","--onto-source"]` (onto **solo** desde porcelain) |
| next / prev | next \| prev | `[]` |
| preview | preview | `[]` o `["--stat"]` |
| compare | compare | layout flags + `["--", lower, upper]` |
| clean one | clean | `[source]` |
| clean keep-fixes | clean | `["--keep-fixes", source]` |
| clean all | clean | `[]` |
| forget saved one | forget | `["--saved", source]` |
| forget saved all | forget | `["--saved", "--all"]` |
| forget delta one | forget | `["--delta", source]` |
| forget delta all | forget | `["--delta", "--all"]` |
| forget delta stale | forget | `["--delta", "--stale"]` (network) |
| set base | config | `["base", "--", name]` |
| set remote | config | `["remote", "--", name]` |
| wt init | walkthrough | `["init"]` / `["init","--force"]` |
| wt build | walkthrough | `["build"]` |

### start intent → args

Orden fijo:

1. layout: *(vacío)* | `--keys` | `--step` | `--no-walk`
2. `--delta` si range=delta
3. `--local` \| `--offline` si source ≠ remote
4. `--`, branch

### config probes (start wizard)

```text
config --porcelain
config --porcelain -- <branch>
config --porcelain [--local|--offline] [--delta] -- <branch>
```

Siempre `network=false` en config.

## Exit codes de status (plugin)

| exit | situation base |
|------|----------------|
| 0 | review (+ finish-conflict si registro finish) |
| 2 | no-review (+ finish-pending si list) |
| 3 | out-of-range |
| otro / null (no timeout) | error |
| timedOut | error (mensaje de timeout) |

## Clasificación de fallo de start (red)

Substrings case-insensitive en **stderr** (misma lista que `startFailure.ts`
de la extensión). Match → ofrecer Run in Terminal con `ResolvedCommand`
exacto.

## Git de apoyo (no git-review)

Para diffs / name-status:

- ejecutable vía Git del IDE / `GitExecutableManager`
- `git -C <root> …` o cwd=root
- UTF-8, clase `SUPPORT_GIT` (30 s), buffer grande
- range: `diff --name-status -z --no-renames HEAD`
- commit: `diff-tree -r -z --no-commit-id --name-status --root <sha>`

## Prohibiciones

1. Derivar ReviewState desde Git4Idea / ChangeListManager.
2. `shell=true` con paths de usuario concatenados.
3. Confiar charset default de la JVM en Windows.
4. Encolar mutaciones; parsear finish stdout para toasts de estado.
5. Enviar `PathRef.raw` al panel UI (solo display).
6. Force undo como primera opción.
7. Multi-root: usar `targets[0]`.
