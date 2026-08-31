# Implementation Plan: Cliente TUI de terminal, cuarto cliente del monorepo

**Branch**: `015-cliente-tui` | **Date**: 2026-08-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/015-cliente-tui/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the
execution workflow.

## Summary

Cuarto cliente de la CLI `git-review-workflow`, esta vez sin host: una TUI que vive en un pane de
terminal, escrita en **Go** con bubbletea/lipgloss/bubbles/fsnotify, más el verbo POSIX
`git review ui` que la lanza. Código en `tui/`, módulo Go propio, **dominio puro** (parseo,
proyección del panel, copy, tabla de confirmaciones, mapa de iconos, keymap) + host (procesos,
filesystem, reloj) + capa de dibujo. Cuarto consumidor del mismo porcelain y del mismo canónico
anti-drift.

Tres frentes, y sólo tres, son trabajo de diseño; el resto es ejecución sobre moldes que el
monorepo ya tiene:

1. **El refresco sin host.** Los otros tres se enteran porque la plataforma les avisa. Acá hay que
   construir el aviso: vigilancia de contenedores + debounce + ventana de silencio contra el lock de
   mutación, con un apagado total que la suite ejerce por default.
2. **La migración del canónico y de su verificador.** `min_cli_version` deja de ser escalar y
   `multi_root_error` deja de ser copy compartida. Las dos tocan a los **tres clientes ya
   publicados**, así que las dos se hacen **preservando bytes**: cambia la forma, no los valores.
3. **El empaquetado.** Fórmula propia con binario prebuilt, los dos one-liner con la TUI detrás de un
   flag apagado, `tui-v*` y `--latest=false`. **Sin npm**: no hay registro de por medio, así que no
   hay ninguna alta previa que hacer a mano.

Orden de entrega por capas, como el plugin de JetBrains: cada capa deja la TUI usable en un
subconjunto de historias y ninguna se mergea sin sus tests.

## Technical Context

**Language/Version**: **Go 1.25** (última estable al planear; el pin vive en **un solo lugar**,
`tui/go.mod`, y CI usa `go-version-file: tui/go.mod` en vez de repetir el número). Verbo `ui` en
shell POSIX puro con `set -eu`, como los quince que ya existen. `scripts/check-client-product-surface.mjs`
sigue siendo Node. El repo pasa a toolchain de cinco lenguajes (sh + TS + Kotlin + C# + Go).

**Primary Dependencies**: cuatro directas y ninguna más —
`github.com/charmbracelet/bubbletea`, `.../lipgloss`, `.../bubbles`, `github.com/fsnotify/fsnotify`.
`fsnotify` se importa en **un solo archivo** (`internal/host/watch_fsnotify.go`) y bubbletea/lipgloss/
bubbles **nunca** en `internal/domain/`. FR-075 lo verifica leyendo `go.mod` y barriendo imports.

**Storage**: estado de review = **sólo CLI**, reinvocando porcelain. Preferencias del cliente =
claves `git config` bajo `reviewui.*`, leídas defensivamente (`|| true` del lado sh, error ignorado
del lado Go), con `--global` como preferencia y local como override. **Cero archivos propios en
disco** (FR-078): ni cache, ni log persistido, ni `lastOpened`. El registro de invocaciones vive en
memoria del proceso y muere con él.

**Testing**: `go test ./...` en los tres SO. Cuatro clases:
unit de dominio (parsers, situación, `PanelModel`, intent, argv, copy);
**golden files de layout** a 80×24 y 120×40 para las ocho situaciones, con color apagado y con
fallback ASCII forzado, no regenerables desde CI;
**tests de vigilancia** contra un repositorio de prueba real, únicos que instancian fsnotify;
y **tests de contrato** (layout contra el canónico, alcanzabilidad sólo-teclado, sólo-mouse,
frontera de imports). El verbo suma `tests/ui.bats` a la suite bats existente —mismo `bats@1.13.0`,
**los cuatro pines quedan intactos**—. Integración a mano por el quickstart antes de cada release.

**Target Platform**: siete targets desde **un solo runner ubuntu** (`CGO_ENABLED=0`, cross-compile
nativo de Go): `darwin/arm64`, `darwin/amd64`, `linux/amd64`, `linux/arm64`, `linux/arm` (v7),
`windows/amd64`, `windows/arm64`. Terminales objetivo: Windows Terminal, conhost con VT, macOS
Terminal, iTerm2, tmux, screen y los terminales de Linux.

**Project Type**: monorepo — CLI (sh) + tres clientes de editor + **cuarto cliente sin host**.

**Performance Goals**: **cero procesos de `git review` en reposo** (SC-002, y es un número medido,
no cualitativo: el registro de invocaciones cuenta). Primer paint con el `waiting_text` en el primer
frame, antes de la primera invocación. Debounce de vigilancia 200 ms con techo de 1 s. Timeouts
15/120/300 s + 30 s del git de apoyo, los mismos de los otros tres.

**Constraints**: UTF-8 explícito en `stdout`/`stderr`; un solo `cwd` (el del proceso); nunca derivar
estado del filesystem ni del evento; `PanelModel` **comparable por valor** (es lo que hace
demostrable el "exactamente un repintado" de SC-004); ningún emoji ni glifo de ancho ambiguo;
`NO_COLOR`; terminal restaurado ante panic; dominio sin `os/exec`; los dos README y las dos puntas
de la landing en el mismo cambio; **ninguna superficie que le llegue a quien instala nombra a los
otros tres clientes**.

**Scale/Scope**: 8 situaciones (+ la superficie de espera) × 2 tamaños de golden; **27 acciones**
clasificadas 22 nativas / 4 delegadas / 1 `not_in: [tui]`; tres mapas de controles de fila; ~4–5k
LOC entre dominio, host y dibujo; **0** paquetes publicados en registros; 7 binarios adjuntos al
Release; 1 fórmula; 1 workflow de release nuevo; 1 job de CI nuevo; 2 cambios de forma en el canónico
que tocan a los tres clientes ya publicados.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` sigue **sin ratificar** (es la plantilla con placeholders
`[PRINCIPLE_N_NAME]`), igual que cuando se planeó `009-plugin-intellij`, así que no hay principios
MUST que violar. Los gates de abajo **no** son constitucionales: son las reglas vigentes de
`CLAUDE.md` y de los contratos del repo, usadas como sustituto explícito.

| Gate | Estado | Nota |
|------|--------|------|
| CLI única fuente de verdad | ✅ | FR-012: todo sale de porcelain; la TUI no lee refs ni config de review |
| Verbos POSIX, sin bashisms, sin `A && B \|\| C` | ✅ | `bin/git-review-verbs/ui`, quince líneas, shellcheck en los tres SO |
| Los verbos son privados; sólo el dispatcher va al `PATH` | ✅ | `git-review-ui` **no es un verbo**: es un programa aparte que git expone por la convención `git-*` de terceros (FR-006). La regla queda intacta y `tests/dispatcher-only.bats` la sigue afirmando |
| Espejar idioms de git / riesgo asimétrico | ✅ | el verbo se **niega** con hint accionable (FR-003), no pregunta ni instala |
| Paths / encoding multiplataforma | ✅ | `PathRef` crudo/mostrable, UTF-8 explícito, `core.quotePath` lo resuelve la CLI |
| Copy de paneles (las siete reglas de §15) | ✅ | `UserCopy` propio, puerta única de confirmación, `reveals: []` declarado, sin prosa que nombre un comando que una tecla en pantalla corre |
| Advice apagado en un solo lugar | ✅ | FR-009: `GIT_REVIEW_ADVICE=0` en `internal/host/invoke.go` y en ningún otro archivo |
| Tests con asserts fuertes, `@test` en ASCII | ✅ | `tests/ui.bats` afirma exit code **y** stderr **y** el efecto; golden files por bytes |
| bats pinneado en cuatro lugares | ✅ | **no se toca ninguno**: el job nuevo es Go |
| Los DOS README | ✅ | FR-054, mismo cambio |
| Landing bilingüe en un solo archivo | ✅ | FR-055, las dos puntas |
| Multi-cliente anti-drift | ✅ | el cuarto cliente entra al canónico **con sus gates**, no después |
| Documentos de trabajo en español | ✅ | esta feature; encabezados de plantilla verbatim en inglés |

**Sin violaciones.** Complexity Tracking vacío.

### Re-evaluación post Phase 1

- Los cinco contratos de `contracts/` cierran superficie, invocación, refresco, canónico y release
  sin tocar el wire format de la CLI: el único cambio en `bin/` es un verbo nuevo que no lee ni
  escribe estado.
- **Las dos migraciones del canónico son value-preserving.** `min_cli_version` pasa a mapa con los
  cuatro valores sembrados en `0.8.0`; `multi_root_error` sale de `strings:` con los tres textos
  actuales copiados verbatim. Ningún archivo de los tres clientes publicados cambia un byte en el
  commit de forma. Eso es lo que hace que CI no se ponga roja en el medio.
- El split dominio/host/dibujo permite SC-005, SC-009, SC-015 y SC-016 **sin un terminal**: los
  golden y los tests de alcanzabilidad corren sobre `PanelModel` y sobre `Update`, no sobre un TTY.
- `reveals:` y `min_cli_version` pasan de escalar/lista plana a **mapa por cliente**. Es un cambio
  de forma del canónico, no una excepción: la forma nueva es la que ya tienen `not_in:` y
  `panel_layout`, donde cada cliente contesta por sí mismo.
- La divergencia de `min_cli_version` **es** el gate de FR-028: desde el día que la TUI publica, los
  cuatro valores difieren en `main`, así que cualquier chequeo que exigiera igualdad estaría rojo.

## Project Structure

### Documentation (this feature)

```text
specs/015-cliente-tui/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── cli-invocation.md            # la lista CERRADA de invocaciones (FR-014)
│   ├── tui-surface.md               # 8 situaciones, 27 acciones, teclas, mouse, overlay
│   ├── refresh.md                   # vigilancia, debounce, lock, apagado total
│   ├── client-product-surface.md    # qué gana el canónico y cómo migra su verificador
│   └── packaging-release.md         # Homebrew, one-liners, tui-v*, matriz y hint por plataforma
├── checklists/
│   └── requirements.md              # ya existe
└── tasks.md                         # Phase 2 (/speckit-tasks) — NO lo crea /speckit-plan
```

### Source Code (repository root)

```text
bin/
└── git-review-verbs/ui              # NUEVO — verbo POSIX, ~15 líneas, exec, sin bashisms
bin/git-review                       # usage: una línea más en Commands:
completions/git-review-workflow.{bash,zsh,fish}   # el verbo, en las tres (FR-005)

contracts/
└── client-product-surface.yaml      # min_cli_version -> mapa; reveals -> mapa;
                                     # multi_root_error sale de strings:; listing.applies_to;
                                     # keymap:; not_in: [tui] en openAllChanges
scripts/
└── check-client-product-surface.mjs # aprende a leer Go y a preguntar por cliente

tui/                                 # NUEVO — módulo Go propio, cero código compartido
├── go.mod                           # ÚNICA fuente del pin de Go y de las cuatro deps
├── go.sum
├── CONTRIBUTING.md                  # FR-056
├── bump-version.sh                  # FR-051 (POSIX, shellcheck, sed_i por archivo temporal)
├── cmd/git-review-ui/main.go        # composition root + centinela de askpass
├── internal/
│   ├── domain/                      # PURO: stdlib y nada más
│   │   ├── porcelain.go             # status / config / list, tolerante en las tres formas
│   │   ├── situation.go             # las ocho + waiting, con la prioridad del canónico
│   │   ├── pathref.go               # crudo (a la CLI) / mostrable (a pantalla y editor)
│   │   ├── panelmodel.go            # proyección COMPARABLE POR VALOR
│   │   ├── layout.go                # los bloques por situación, espejo de panel_layout:
│   │   ├── usercopy.go              # TODA la copy del cliente (FR-030)
│   │   ├── confirms.go              # la tabla + ConfirmMutation, la ÚNICA puerta
│   │   ├── icons.go                 # el ÚNICO mapa: prev/next/file/trash/diff + ASCII
│   │   ├── keymap.go                # tecla -> acción/movimiento, espejo de keymap:
│   │   ├── actions.go               # id -> verbo + argv (lista cerrada)
│   │   ├── intent.go                # ReviewIntent -> argv del asistente
│   │   ├── watchrules.go            # raíces, allowlist de prefijos, presupuesto (datos puros)
│   │   ├── version.go               # Version + MinCLIVersion
│   │   └── installhint.go           # npm_install / npm_update
│   ├── host/                        # procesos, filesystem, reloj
│   │   ├── invoke.go                # git review <verbo>; clases; GIT_REVIEW_ADVICE=0 (un lugar)
│   │   ├── askpass.go               # el centinela no-op de credenciales
│   │   ├── gitdata.go               # rev-parse: --git-dir / --git-common-dir / --show-toplevel
│   │   ├── lock.go                  # MutationLock (profundidad 1) + ventana de silencio
│   │   ├── watch.go                 # interface Watcher + nopWatcher (el apagado total)
│   │   ├── watch_fsnotify.go        # ÚNICO archivo que importa fsnotify
│   │   ├── watchset.go              # deriva el conjunto: 6 raíces, dedup por dir, cierre, tope
│   │   ├── open.go                  # las cuatro delegadas: $EDITOR, difftool, $PAGER
│   │   └── clipboard.go             # OSC 52, con su degradación
│   └── ui/                          # bubbletea / lipgloss / bubbles
│       ├── program.go               # Model, Update, View
│       ├── render.go                # PanelModel -> (frame, HitMap)
│       ├── confirm.go               # EL ÚNICO overlay modal del cliente
│       ├── palette.go               # la lista completa de acciones (equivalente de surface: action)
│       └── keys.go                  # KeyMsg/MouseMsg -> intent tipado
├── testdata/
│   ├── porcelain/                   # fixtures de las ocho situaciones
│   └── golden/<situación>-<80x24|120x40>[-nocolor|-ascii].txt

Formula/git-review-ui.rb             # NUEVO — fórmula propia, binario prebuilt por plataforma
web-install.sh / web-install.ps1     # la TUI detrás de un flag APAGADO (GIT_REVIEW_WITH_UI=1 / -WithUi);
                                     # sin el flag, exactamente lo que dejan hoy
tests/ui.bats                        # NUEVO — el verbo: ausente, presente, $GIT_REVIEW_UI, exec
tests/dispatcher-only.bats           # VERBS= suma "ui" (lista hardcodeada, línea 12)
tests/version-consistency.bats       # bloque nuevo: fórmula == version.go, y NINGÚN package.json
.github/workflows/ci.yml             # job `tui` (go vet/gofmt/test en los tres SO)
.github/workflows/release-tui.yml    # NUEVO — tag tui-v*, --latest=false, 7 binarios + SHA256SUMS
README.md / README.es.md             # el verbo, el sinónimo git review-ui, las vías
docs/index.html                      # las DOS puntas: HTML inglés + diccionario ES
```

**Structure Decision**: módulo Go independiente en `tui/`, hermano de los otros tres clientes y con
su propio `go.mod` — no un paquete de un módulo raíz, que no existe. El id de cliente en el canónico
es **`tui`**, el mismo que la spec ya usa en `not_in: [tui]`, y el directorio lleva ese nombre para
que id y árbol coincidan (los otros tres ya lo hacen: `vscode`→`vscode-extension/`,
`intellij`→`jetbrains-plugin/`, `visualstudio`→`visualstudio-extension/`; acá el par es directo).
El split de capas es el mismo que JetBrains y Visual Studio —dominio puro, host, dibujo— con dos
diferencias que la ausencia de host impone: `internal/host/` incluye la **vigilancia** (que en los
otros tres la da la plataforma) y `internal/ui/` incluye el **ciclo de vida del terminal** (que en
los otros tres lo da el IDE). La frontera de lenguaje es el punto: no hay ninguna ruta de import
desde `tui/` hacia otro cliente, y hay un test que lo afirma (FR-075).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
