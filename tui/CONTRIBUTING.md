# Contribuir a la interfaz de terminal

Este documento cubre el desarrollo de la TUI. El uso del producto está en los
[README](../README.es.md); las decisiones y contratos viven en
[`../specs/015-cliente-tui/`](../specs/015-cliente-tui/). La CLI es la única
fuente de verdad: la TUI reinvoca sus registros porcelain y nunca deriva estado
del repositorio por su cuenta.

## Build y tests

El módulo Go es independiente y fija su toolchain y dependencias en `go.mod` y
`go.sum`:

```sh
cd tui
gofmt -w .
go vet ./...
go test ./...
go build ./cmd/git-review-ui
```

Desde la raíz, `node scripts/check-client-product-surface.mjs` compara las
acciones, el layout, la copy y el mapa de teclas contra
`contracts/client-product-surface.yaml`. Antes de entregar un cambio, los cuatro
comandos deben quedar verdes y `gofmt -l .` no debe imprimir archivos.

La suite normal usa un watcher nulo para ser determinista. El watcher real se
ejercita únicamente en `internal/host/watch_fsnotify_test.go`; para una prueba
manual completa se habilita al arrancar:

```sh
GIT_REVIEW_UI_WATCH=1 go run ./cmd/git-review-ui
```

`GIT_REVIEW_UI_WATCH=0` (o dejar la variable sin definir) es la palanca de
apagado total para soporte y tests. Apaga sólo la aceleración por eventos: las
teclas, el foco, las mutaciones y el refresco explícito siguen leyendo la CLI.

## Golden files

Los golden se comparan por bytes en dos tamaños y con glifos normales/ASCII.
Sólo existe el flag de regeneración bajo el build tag deliberado:

```sh
cd tui
go test -tags goldenupdate ./internal/ui -update
git diff -- testdata/golden
go test ./internal/ui
```

Revisá el diff como UI: jerarquía, truncado, foco, barra de teclas, anchos y la
variante ASCII. No aceptes una regeneración masiva sin explicar qué decisión
visual cambió. CI no conoce `-update`, por lo que nunca puede reescribir golden.

## Configuración `reviewui.*`

- `reviewui.startsource`: preselecciona la fuente del asistente de inicio; hoy
  acepta `remote`, `local` u `offline` sin ocultar las demás opciones válidas.
- `reviewui.pollseconds`: piso opt-in para montajes de red que pierden eventos.
  Un entero positivo arma una lectura sólo cuando pasó ese intervalo sin ningún
  otro refresco; ausente, inválido, cero o negativo significa apagado.

Las claves se leen con `git config --get`: una local sobrescribe una global. La
variable `GIT_REVIEW_UI_WATCH` no es configuración de producto y no debe
convertirse en una clave `reviewui.*`.

## Matriz smoke previa a un release

Corré los ocho casos en Windows, macOS y Linux, en una terminal real. Usá
`../tests/sandbox.sh` y `../tests/sandbox-min.sh`; las historias de refresco y
pane se validan en dos panes de tmux/screen.

| # | Caso | Resultado esperado |
|---|---|---|
| 1 | CLI anterior en `PATH` | `cli-outdated`, nunca `cli-missing` |
| 2 | path con espacios y caracteres no ASCII | lista, abre y diffea el path exacto |
| 3 | `start --offline` desde el asistente | inicia la review |
| 4 | credenciales que intentarían prompt | diagnóstico sin colgar el pane |
| 5 | worktree enlazado | guías desde common-dir y borrador desde git-dir |
| 6 | Windows, instalación con `web-install.ps1 -WithUi` | `git review ui` arranca |
| 7 | backend de refs `reftable` | arranca y refresca |
| 8 | `cwd` fuera de un repositorio | error accionable, nunca pantalla vacía |

La evidencia detallada SC-001…SC-018 y los pasos del recorrido están en
[`../specs/015-cliente-tui/quickstart.md`](../specs/015-cliente-tui/quickstart.md).

## Runbook de release

La TUI versiona aparte. No se publica en npm ni en otra tienda; el GitHub
Release publica siete binarios y la fórmula Homebrew consume los cuatro que
corresponden a macOS/Linux × ARM/Intel.

1. Elegí la versión y ejecutá `./tui/bump-version.sh X.Y.Z` desde la raíz.
2. Revisá que cambien sólo `tui/internal/domain/version.go` y la `version` de
   `Formula/git-review-ui.rb`; sus cuatro `sha256` deben seguir en placeholder.
3. Corré `./lint-docker.sh tui/bump-version.sh`,
   `./tests/run-docker.sh version-consistency.bats`, los gates Go y el checker
   del canónico.
4. Completá la matriz smoke y el quickstart de punta a punta.
5. Taggeá el commit ya integrado como `tui-vX.Y.Z` y pusheá el tag.

`.github/workflows/release-tui.yml` vuelve a verificar el commit taggeado en los
tres sistemas, cross-compila los siete targets con `CGO_ENABLED=0`, comprueba
existencia y `SHA256SUMS`, crea el Release con `--latest=false` y fija los cuatro
checksums de la fórmula en la rama por default. No hay paso de publicación en
un registro ni alta previa que realizar.
