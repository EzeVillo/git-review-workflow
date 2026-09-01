# Evidencia de pre-release: TUI 0.1.0

**Fecha:** 2026-08-31  
**Commit:** `aed9e05` (`main`)  
**Alcance de esta corrida:** Windows nativo y Linux amd64 en Docker. macOS queda pendiente.

T119 permanece abierta: todavía faltan el smoke en macOS, el recorrido sólo-mouse y tres casos
manuales Windows que esta corrida cubrió sólo con gates (`401`/askpass, worktree y `reftable`),
además de la instalación contra un `tui-v0.1.0` publicado. El tag/release aún no existe; por eso el
instalador de Windows se validó de punta a punta con el servidor falso de la suite, no contra un
asset público.

## Entornos

| Entorno | Terminal | Toolchain |
|---|---|---|
| Windows `10.0.26200` x64 | PTY PowerShell 7.6.4, 80×24 | Git 2.52.0.windows.1, Go 1.27.0, CLI 0.8.0 |
| Debian 12 amd64 (Docker) | tmux 3.3a, dos panes reales de 80×24 y pane de 120×40 | Git 2.39.5, Go 1.25.14 |
| Alpine 3.24 amd64 (Docker) | tmux 3.7c, 80×24 | Git 2.54.0, Go 1.25.14; usado para `reftable` |

## Recorrido manual

Los repos se reconstruyeron con `tests/sandbox.sh` y `tests/sandbox-min.sh`. En Windows se usó el
binario `windows/amd64` construido en el host; en Linux se construyó y ejecutó el binario dentro del
contenedor.

| Caso | Windows | Linux | Evidencia observada |
|---|---|---|---|
| CLI anterior | OK | OK | Un dispatcher de prueba que reporta `0.7.0` y sí delega `ui` produjo `cli-outdated`, nunca `cli-missing`. |
| Path con espacio y no ASCII | OK | OK | `docs/guía de estilo.md` apareció sin corrupción. En Windows el editor recibió exactamente ese argv y el diff abrió; en Linux el output capturado incluyó `diff --git a/docs/guía de estilo.md b/docs/guía de estilo.md`. |
| `start --offline` desde el asistente | OK | OK | En ambos: configurar base → elegir `feature/discount` → Offline → step → entrada 1/2; `next` llegó a 2/2 y `finish` dejó `review-fixes/feature/discount`. |
| Credenciales sin prompt | Gate automático | OK | Un servidor HTTP local devolvió `401`; la TUI volvió al panel con `terminal prompts disabled` y diagnóstico de fetch, sin colgar tmux. Windows ejecutó los gates de `askpass`/timeout. |
| Worktree enlazado | Gate automático | OK | En Linux, `--git-dir` fue `.git/worktrees/t119-wt-linux`, `--git-common-dir` fue `.git`; el porcelain ubicó el draft bajo el primero y la guía propia bajo el segundo, y la TUI dibujó `feature/telemetry 0/4`. El watcher equivalente pasó en Windows. |
| `web-install.ps1 -WithUi` | Pendiente release real | No aplica | `tests/web-install-ps1.bats` pasó 7/7, incluido zip con checksum. Falta repetirlo contra el asset público cuando exista `tui-v0.1.0`. |
| Backend `reftable` | OK (watcher real) | OK | El test fsnotify pasó con Git 2.52 en Windows. En Alpine se abrió una TUI real sobre un repo `reftable`; al escribir `reviewworkflow.base`, pasó sola de setup a `No active review`. |
| `cwd` fuera de un repo | OK | OK | En ambos mostró `Something went wrong…` y `Run git review ui from inside a git repository`, nunca una pantalla vacía. |

También se comprobó en Windows y Linux que un `git review next` ejecutado desde la segunda terminal
actualiza solo el pane con `GIT_REVIEW_UI_WATCH=1`; después de `git pack-refs --all` el siguiente
cambio siguió llegando. El primer ciclo Windows se ejecutó con el watcher apagado y se completó con
refrescos explícitos. En Linux se renderizó 120×40 con `NO_COLOR=1` y
`GIT_REVIEW_UI_ASCII=1`; los controles y las filas siguieron presentes y dentro del ancho.

## SC-001…SC-018

| Criterio | Estado | Evidencia |
|---|---|---|
| SC-001 | OK | Ciclo manual completo `start → next → finish` sin abandonar la TUI, en Windows y Linux. |
| SC-002 | OK | `TestModelAtRestCausesNoInvocations`; la suite completa pasó con `-count=1`. |
| SC-003 | OK | Siete tests fsnotify ejecutados explícitamente: config por rename, packed refs, dos anidamientos, `reftable`, dos checkouts y worktree enlazado. En Debian sólo `reftable` hizo skip por Git 2.39; pasó en Windows y Alpine. |
| SC-004 | OK | `TestMutationSilenceWindowProducesExactlyOneRepaint` dentro de `go test ./...`; el ciclo manual no mostró repintados intermedios. |
| SC-005 | OK | Fixtures de las ocho situaciones y sus golden pasaron en `go test ./...`. |
| SC-006 | OK | `check-client-product-surface`: `actions=27`, con la exclusión TUI declarada. |
| SC-007 | OK | Gates de confirmaciones (`confirms.go`, `confirm_test.go` y checker canónico) verdes. |
| SC-008 | OK | `reveals.tui` vacío y barrido del checker canónico verdes. |
| SC-009 | OK | Golden 80×24 y 120×40 verdes; ambos tamaños se abrieron además en tmux real. |
| SC-010 | OK | Golden `-nocolor`/`-ascii` verdes y smoke Linux 120×40 con ambas variables activas. |
| SC-011 | OK | Sin binario: exit 1 + hint de instalación en Windows. Con binario: la TUI arrancó y devolvió exit 0 al salir. `tests/ui.bats` pasó 10/10. |
| SC-012 | OK | Checker multi-cliente verde (`vs=yes`, `tui=yes`). |
| SC-013 | Parcial | `release-tui.yml` usa `tui-v*` y `gh release create --latest=false`; `tests/release-tui.bats` pasó 6/6. Falta resolver `releases/latest` después del primer tag real. |
| SC-014 | OK | Tests de `go.mod` y frontera de imports verdes. |
| SC-015 | OK | Recorrido manual sólo teclado; gates de alcanzabilidad sólo teclado y sólo mouse verdes para todas las situaciones. |
| SC-016 | OK | Toda la suite usa `nopWatcher` por defecto; el ciclo Windows con watcher apagado fue correcto. En Linux, un `next` externo dejó la pantalla en 5/6 hasta pulsar `r`, que la llevó a 6/6. |
| SC-017 | OK | 66 golden (11 claves de `panel_layout` × dos tamaños × tres capacidades) más dos frames de espera verdes; `-update` no existe sin el build tag. |
| SC-018 | OK | Los tres gates de confirmación y el gate simétrico que prohíbe reveals TUI pasaron en Go + checker. |

## Gates ejecutados

| Comando | Resultado |
|---|---|
| `gofmt -l .` | salida vacía en Windows y Linux |
| `go vet ./...` | OK en Windows y Linux |
| `go test ./... -count=1` | OK en Windows y Linux |
| `go test ./internal/host -run 'Test(RenameAtomic|PackedRefs|Nested|Reftable|HeadCheckout|LinkedWorktree)' -count=1 -v` | 7/7 Windows; 6 OK + 1 skip Debian; `reftable` OK Alpine |
| `node scripts/check-client-product-surface.mjs` | OK, 27 acciones y TUI presente |
| `./lint-docker.sh tui/bump-version.sh` | OK |
| `./tests/run-docker.sh tests/version-consistency.bats` | 17/17 |
| `./tests/run-docker.sh tests/ui.bats tests/release-tui.bats tests/web-install.bats` | 24/24 |
| `bats tests/web-install-ps1.bats` en Windows | 7/7 |

## Checklist de empaquetado

- [x] `Formula/git-review-ui.rb` está trackeada en `main`, versión `0.1.0`, con cuatro `sha256` en placeholder.
- [x] `tests/version-consistency.bats` está verde con sus cuatro checks TUI.
- [x] `tui/bump-version.sh` figura en las listas de shellcheck de `ci.yml` y `release.yml`.
- [x] `README.md` y `README.es.md` documentan instalación, `git review ui` y `git review-ui`.
- [x] `docs/index.html` tiene la caja inglesa `data-i18n="terminalui"` y su valor español en `ES`.
- [x] `tui/CONTRIBUTING.md` contiene build, tests, golden, watcher, `reviewui.*`, smoke y release.

## Pendientes antes del tag

- [ ] Ejecutar la misma matriz en una terminal macOS real.
- [ ] Repetir manualmente en Windows el servidor `401`, el worktree enlazado y el repo `reftable` (los gates nativos ya están verdes).
- [ ] Completar el recorrido manual sólo-mouse; el gate sintético de alcanzabilidad ya está verde.
- [ ] Publicar el primer `tui-v0.1.0`, repetir `web-install.ps1 -WithUi` contra el zip público y comprobar que `releases/latest` sigue apuntando al release de la CLI.
