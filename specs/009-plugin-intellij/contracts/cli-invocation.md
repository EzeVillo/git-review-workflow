# Contract: CLI invocation (IntelliJ plugin client)

Enmienda de validación: [guard del contexto de review](../../../contracts/review-state-guard.md).
El prefijo global `--expect-state <guard>` no cambia el verbo lógico ni su clase
de timeout/red. Sustituye la prelectura completa sólo cuando existe un testigo
válido emitido por la CLI; el código 4 exige refresco completo y aviso `STALE`.

Enmienda del 7 de noviembre de 2026: cuando status emite
`capability<TAB>navigation-state`, Next/Prev pueden agregar `--porcelain` y
consumir su respuesta como estado principal completo. Si falta la capacidad
o la respuesta es inválida, se conserva el refresco completo. Comments y la
explicación se completan por separado, rechazando generaciones antiguas.
Un bloque opcional `why`/`why-line` válido publica el porqué sin otra consulta;
si falta o es inválido, sólo el porqué vuelve a `status --why`. El host consulta
los documentos pendientes en el EDT, sin resolver nodos VFS. Sólo un editor
confirmado limpio omite el inventario previo de Comments; un estado sucio o
desconocido mantiene la consulta y el guardado selectivo. Ver el contrato
completo en `contracts/review-state-guard.md`.
El formato y las guardas están en el contrato de contexto enlazado arriba.

**Normative consumer**: `jetbrains-plugin/`  
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
| clean fixes-only | clean | `["--fixes-only", source]` |
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

## Ampliación: comentarios (CLI candidata 0.10.0)

Contrato detallado: `specs/016-comentarios-review/contracts/cli-porcelain.md`.
Esta ampliación no habilita otros verbos ni interpretación de Markdown en el cliente.

| Operación | Invocación permitida |
|---|---|
| Estado independiente | `comments status --porcelain [--context <id> | --all]` |
| Crear un documento | `comments init --document <local|shared> [--context <id>] [context-options] [guards]` |
| Capturar | `comments add --document <local|shared> --stdin [context-options] [location-options] [guards]` |
| Eliminar documento activo | `comments delete --document <local|shared> --context <id> --expect-context <guard> --expect-document <revision>` |
| Renumerar | `comments renumber --document <local|shared> [--context <id>] [guards]` |
| Selector | `comments entries --document <local|shared> --context <id> --porcelain` |
| Histórico | `comments diff --document <local|shared> --context <id> --entry <ordinal> [--porcelain] [guards]` |
| Conservar comparación | `comments save --expect-context <guard> --expect-local <revision> --expect-shared <revision>` |
| Entrega pendiente | `comments prepare --context <id> [--check --porcelain] [guards]` |
| Contenido histórico | `git cat-file blob <OID completo de comment-blob>`, con `GIT_NO_LAZY_FETCH=1` |

`context-options` es una elección explícita `--new-context` o `--use-context <id>`.
`location-options` admite `--path`, `--side`, `--start-line`, `--end-line`,
`--base`, `--head`, `--base-path`, `--head-path` y `--unversioned`.
`guards` conserva `--expect-context` y las revisiones exactas de documento.
El cuerpo no entra en argv ni logs; stdin se cierra. Un lado vacío se representa
sólo cuando la CLI declara `absent`. La comparación de prosa de Prepare usa los
archivos de `comments-delivery-file` y no crea una sesión de código histórica.
El selector de comentarios consume `comment-body` (líneas escapadas) y
`comment-scope` de `entries`; muestra fragmento, ubicación y detalle completo.
La receta de diff se pide con el mismo ordinal y revisión de documento. Delete
admite resultados de Finish además de preparaciones activas y nunca borra la
copia entregada. El visor mantiene la prosa accesible y señala el rango original.

Las capturas exactas de `comments add` envían `--start-column` y `--end-column`
junto con ambos extremos de línea, en unidades UTF-16 1-based y con fin
exclusivo. `entries` y `diff --porcelain` emiten el registro opcional
`comment-columns` (ordinal, lado, columna inicial, columna final). Los clientes
lo asocian por ordinal y lado; si falta, conservan las líneas inclusivas de
los comentarios anteriores. Archivo/general no envía columnas.

El explorador permite `comments delete --document <local|shared> --context <id> --entry <ordinal> --expect-context <token> --expect-document <revision>` para borrar una entrada física sin renumerar ni cambiar las demás. Sólo se ofrece en preparaciones activas o resultados retenidos; tras borrar se vuelve a consultar `entries --porcelain`. Los comentarios generales no ofrecen abrir un diff.

La captura usa `comments-capability <init|add> <local|shared>` de `comments status
--porcelain`: compare ofrece sólo Local. Un único destino se envía explícitamente
sin selector; varios requieren elección por captura. No hay acción Save comments: las
notas de compare se conservan automáticamente al cerrar o limpiar la comparación.

## Continue con estado final

Si `list --porcelain` anuncia `capability continue-state` y un único
`continue-guard` válido, el cliente captura ese testigo al abrir la confirmación
y puede invocar `git review --expect-state <token> continue <source> --porcelain`.
La CLI valida inventario y checkout dentro de la operación. El prefijo usa el
token del inventario exclusivamente para Continue; los otros verbos conservan
sus reglas. Sin el par capacidad/token se mantiene la ruta anterior.

Un sobre `continue-state 1` / `continue-state complete` con un único status y
guard válidos sustituye la lectura principal posterior. Una respuesta incompleta
o inválida provoca un refresco normal, sin repetir Continue. Los errores y el
código 4 también refrescan, y el 4 muestra el aviso Stale habitual. Comments y
el porqué completan por separado con sus guardas de generación. Ver el contrato
canónico `contracts/review-state-guard.md`.
