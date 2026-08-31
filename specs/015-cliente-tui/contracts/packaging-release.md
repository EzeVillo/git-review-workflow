# Contract: Empaquetado, distribución y release (cliente TUI)

**Consumidores normativos**: `Formula/git-review-ui.rb`,
`.github/workflows/release-tui.yml`, `web-install.sh`, `web-install.ps1`,
`tests/version-consistency.bats`

**Tres vías, más el binario del Release** (FR-048): Homebrew y los dos one-liner. **npm queda
afuera** (FR-049) —es la única vía de la CLI que la TUI no hereda—, y también Scoop, WinGet y
`go install` como vía soportada. Ninguna tienda entra.

La razón de npm, en corto: `bin` en un `package.json` mapea a **un** archivo, así que un paquete con
varios binarios necesita un shim que elija cuál correr, y ese shim es JavaScript. Instalar la TUI por
npm pediría **Node para correr un binario estático de Go** — la dependencia de runtime que motivó
elegir el lenguaje, reintroducida en una sola vía.

La CLI no se toca: su paquete npm sigue existiendo, conserva **cero dependencias** y no menciona ni
transporta la TUI (FR-049); su fórmula queda como está —`depends_on "git"` y nada más, que es el
punto de esa vía— (FR-050).

---

## Los targets

Siete, desde **un solo runner ubuntu**. Es el motivo declarado por el que se eligió Go: cross-compile
nativo, sin `cross`, sin matriz de runners reales y sin `lipo`.

| GOOS | GOARCH | Archivo de release |
|---|---|---|
| darwin | arm64 | `git-review-ui_<v>_darwin_arm64.tar.gz` |
| darwin | amd64 | `…_darwin_amd64.tar.gz` |
| linux | amd64 | `…_linux_amd64.tar.gz` |
| linux | arm64 | `…_linux_arm64.tar.gz` |
| linux | arm (v7) | `…_linux_armv7.tar.gz` |
| windows | amd64 | `…_windows_amd64.zip` |
| windows | arm64 | `…_windows_arm64.zip` |

**Las siete van al Release, y las tres vías las consumen a todas.** Sin npm no hay una segunda matriz
más chica que mantener alineada.

**`CGO_ENABLED=0` es obligatorio**, no una optimización: es lo que hace que un solo binario de
`linux/amd64` funcione en glibc y en musl (Alpine incluida), y es lo que permite compilar los siete
desde un runner. Flags: `-trimpath -ldflags "-s -w"`. La versión **no** se inyecta por `-ldflags`:
vive en `tui/internal/domain/version.go` para que `tests/version-consistency.bats` la pueda leer.

**Plataforma sin binario publicado**: la CLI corre igual (es shell POSIX) y `git review ui` se niega
con el mismo hint accionable. Es el comportamiento correcto, no un caso sin cubrir (Assumption de la
spec).

---

## La matriz del release, y el hint por plataforma

**Las siete se publican como asset del Release**, y esa tabla es la única matriz: no hay una segunda,
más chica, para otra vía. Ésa era la complicación que traía npm y que ya no existe.

**Una plataforma fuera de la matriz es una vía degradada, no un usuario bloqueado** (FR-081). El
binario del Release es un archivo: se obtiene con `curl`, con `wget`, con el navegador o con un
`COPY` en un Dockerfile — sin registro, sin runtime y sin gestor de paquetes. Es el artefacto más
portable que publica este proyecto.

### El hint de `git review ui` nombra la vía que corresponde

El verbo se niega con un hint accionable cuando no encuentra el ejecutable, y ese hint **no puede ser
uno solo genérico** (FR-081): la vía correcta depende de dónde corre.

| Dónde | Qué nombra el hint |
|---|---|
| macOS | `brew install` desde el tap del proyecto |
| Linux con `brew` en el `PATH` | lo mismo |
| Linux sin `brew` | `web-install.sh` con su flag |
| Windows | `web-install.ps1` con `-WithUi` |
| Cualquier otro caso | la página del Release |

Se decide con lo que la shell ya sabe —`uname` y si `brew` está en el `PATH`—, **sin invocar red**.
El verbo es shell POSIX con `set -eu` y **no puede usar `A && B || C`** (SC2015 falla en Ubuntu y en
Windows en CI): el `case` explícito es la forma.

Y el hint **no menciona npm**, porque la TUI no está ahí (FR-049). El de la CLI lo sigue
mencionando, porque la CLI sí.

---

## Homebrew: fórmula propia con binario prebuilt

`Formula/git-review-ui.rb`, nueva. `on_macos`/`on_linux` × `on_arm`/`on_intel`, cada rama con su
`url` y su `sha256` apuntando al asset del Release de `tui-v*`. Instala el binario en `bin` y nada
más.

```ruby
depends_on "git"
```

**Y nada más.** No declara `depends_on "git-review-workflow"` aunque la TUI la necesite: la CLI llega
por cuatro vías y Homebrew sólo ve una, así que una dependencia dura le instalaría una segunda copia
a quien ya la tiene por npm o por un one-liner. Y `cli-missing` no es un error: es una **situación de
panel completa**, con su copy y su comando copiable, diseñada para este momento exacto.

Como en la fórmula de la CLI, el `sha256` de cada rama lo **fija el workflow de release** después del
tag: hasta que el tarball existe, es desconocido. `tui/bump-version.sh` estampa la `version` y deja
los siete `sha256` **a propósito**, igual que hace `./bump-version.sh` con el de la CLI.

---

## Los dos one-liner: la TUI va detrás de un flag apagado

**Instalar la CLI deja exactamente lo que deja hoy** (FR-079). Sin el flag, `web-install.sh` y
`web-install.ps1` **no descargan ni escriben nada** de la TUI: ni una petición a la API, ni un
archivo, ni una línea de salida distinta de la de hoy.

| Instalador | Flag | Forma |
|---|---|---|
| `web-install.sh` | `GIT_REVIEW_WITH_UI=1` | `curl … \| GIT_REVIEW_WITH_UI=1 sh` — la misma forma que ya tienen `PREFIX` y `REF`. **No** se llama `GIT_REVIEW_UI`: esa variable ya es la ruta al ejecutable que lee el verbo, y reusarla haría que quien deje el flag exportado rompa `git review ui` |
| `web-install.ps1` | `-WithUi` | `-SkipUi` **no existe**: no hay nada que saltear |

**Y no se prompt-ea por él.** El proyecto se niega con un hint, no pregunta —es la misma regla del
verbo `ui`—, así que el instalador tampoco puede preguntar «¿querés también la TUI?». Como mucho,
`web-install.sh` puede cerrar nombrando la vía; ni siquiera eso es obligatorio.

**Por qué el default es apagado**: que la TUI esté disponible por una vía no autoriza a esa vía a
entregarla sin que se la pidan. Un one-liner que instala la CLI y de paso baja ~10 MB de binario que
nadie pidió es una sorpresa, y una sorpresa que además cambia lo que hay en el `PATH`. El opt-out que
este documento proponía antes queda revertido.

`web-uninstall.sh` / `web-uninstall.ps1` **sí** borran la TUI si está — un desinstalador que deja
mitad de las cosas es otro problema, y ahí no hay sorpresa que evitar.

Tres cosas que el diseño del release le impone al camino del flag:

1. **No pueden resolver `releases/latest`.** Ese endpoint es del CLI y el Release de la TUI se crea
   con `--latest=false` justamente para no robárselo (FR-052). El ref de la TUI sale de listar
   `releases?per_page=100` y quedarse con el primer tag que empieza con `tui-v`.
2. **Verifican el `sha256`** del asset contra el `SHA256SUMS` publicado en el mismo Release, y si no
   coincide **no instalan**. Un instalador que baja un binario y no lo verifica es peor que no tener
   esa vía.
3. **Sin asset para la plataforma**, saltean el paso con una nota y dejan la CLI instalada igual.
   La matriz es la del Release, que es la única que hay.

El paso de la TUI va **después** del de la CLI y **nunca** puede hacer fallar la instalación de la
CLI: su fallo es una nota, no un `exit`. `web-install.sh` es shell POSIX y pasa por el mismo
`shellcheck` de CI, así que valen las reglas de siempre —sin bashisms, sin `A && B || C`—.

**Gate de FR-079**: un test que corre el instalador **sin** el flag y afirma que no quedó ningún
archivo de la TUI en el `PREFIX` y que no se pidió ninguna URL de la TUI. Es la mitad que se rompe en
silencio: agregar el paso «por comodidad» no falla nada por sí solo.

---

## Versionado y tags

La TUI versiona **aparte de la CLI y de los otros tres clientes**, con el mismo patrón que ellos.

| Comando | Qué estampa |
|---|---|
| `./tui/bump-version.sh X.Y.Z` | `tui/internal/domain/version.go` y la `version` de `Formula/git-review-ui.rb` (los `sha256` quedan para el workflow) |

**Dos archivos.** Es la simplificación que compra no publicar en ningún registro: no hay
`package.json` que mantener alineado ni pines de dependencias por plataforma que puedan quedar atrás
de a uno.

Escrito en shell POSIX con `set -eu`, con el mismo `sed_i` por archivo temporal que usa
`./bump-version.sh` (GNU y BSD difieren en `-i`), y se suma a las dos listas de `shellcheck`
(`ci.yml` y `release.yml`).

`tests/version-consistency.bats` gana su bloque, con nombres de `@test` en **ASCII puro**:

- el `version.go` de la TUI es semver pelado;
- la fórmula coincide con `version.go`;
- **no existe ningún `package.json` bajo `tui/`** — el gate que impide que la vía descartada vuelva
  por la ventana sin que nadie lo note.

Cada uno afirma igualdad y nombra el archivo que quedó atrás — un bump parcial falla fuerte, que es
para lo que existe ese archivo.

---

## `.github/workflows/release-tui.yml`

Dispara con `tui-v*`. Namespace propio: `v*` sigue siendo **sólo** la CLI y `jetbrains-v*` sólo el
plugin.

| Job | Runner | Qué hace |
|---|---|---|
| `verify` | ubuntu, macos, windows | `gofmt -l` (vacío), `go vet ./...`, `go test ./...`, `node scripts/check-client-product-surface.mjs`. Un tag no puede publicar código roto, y el gate corre **contra el commit tageado** |
| `build` | **ubuntu** | los siete targets con `CGO_ENABLED=0 -trimpath`, empaquetados (`.tar.gz` / `.zip`) + `SHA256SUMS` |
| `release` | ubuntu | `gh release create "$GITHUB_REF_NAME" --latest=false --generate-notes` + sube los archivos y el `SHA256SUMS`; después fija los `sha256` de la fórmula en la rama por default, con el mismo `sed_i` del workflow de la CLI |

**Tres jobs, no cuatro.** No hay job de publicación: el Release *es* la publicación.

### `--latest=false` no es cosmético

`web-install.sh` y `web-install.ps1` resuelven `releases/latest` para elegir el ref **de la CLI**. Un
release de cliente marcado *latest* haría que el instalador de la CLI se pare en un tag ajeno. Es la
misma razón exacta por la que `release-jetbrains.yml` lo lleva (líneas 133-134 y 166 de ese archivo),
y SC-013 lo verifica resolviendo `releases/latest` después del tag.

### Se verifica antes de subir

Antes de crear el Release, dos asserts —y los dos fallan el release, no lo avisan—:

1. los **siete** archivos existen y no están vacíos;
2. el `SHA256SUMS` cubre los siete y cada suma coincide con su archivo.

**No hay orden de publicación que pueda fallar en silencio**, que era el riesgo estructural de la vía
descartada: hay un solo artefacto y un solo paso que lo sube.

---

## Runbook manual: lo que ningún workflow puede hacer

**Casi nada, y ése es el punto.** Sin registro de paquetes de por medio no hay alta previa que hacer,
así que el modo de falla que la spec advertía —el primer release muriendo con un error que *parece*
de OIDC roto y no lo es— desaparece junto con la vía que lo causaba (FR-053).

No hace falta crear una organización en ningún registro, ni publicar un bootstrap, ni configurar
publicación confiable, ni acertar un orden de publicación entre paquetes. Tampoco hace falta un alta
de Homebrew: la fórmula vive en este mismo repo, como la de la CLI, y se instala con el mismo
`brew tap`.

Queda lo de siempre en este repo: el `sha256` de la fórmula es desconocido hasta que el asset existe,
así que `bump-version.sh` lo deja **a propósito** y lo fija el workflow después del tag.

### Checklist de pre-release, para que el primero no sea el que descubre esto

- [ ] `Formula/git-review-ui.rb` en la rama por default, con la `version` estampada y los `sha256`
      en placeholder
- [ ] `tests/version-consistency.bats` verde con el bloque de la TUI
- [ ] `tui/bump-version.sh` en las dos listas de `shellcheck`
- [ ] los dos README y las dos puntas de la landing actualizados
- [ ] `tui/CONTRIBUTING.md` escrito

---

## Documentación que viaja con el release

| Superficie | Qué cambia | Regla |
|---|---|---|
| `README.md` **y** `README.es.md` | el verbo `ui` en la tabla; el sinónimo `git review-ui` en **una línea**, sin pedir disculpas y sin volverlo una segunda forma documentada; las vías de instalación de la TUI | FR-054 — **los dos, en el mismo cambio** |
| `docs/index.html` | una caja más en `install-grid` | FR-055 — bilingüe en **un solo archivo**: el texto va en el HTML en inglés **y** en el diccionario `ES`, emparejados por `data-i18n`. Las cajas existentes ya usan ese patrón (`nonode`, `thenonce`), así que la nueva necesita su clave en las **dos** puntas |
| `tui/CONTRIBUTING.md` | build, test, golden, `GIT_REVIEW_UI_WATCH`, `reviewui.*`, el runbook de release | FR-056 |
| `CLAUDE.md` | el cuarto cliente en § Clientes del monorepo; el árbol `tui/`; los comandos | la paridad se cuenta acá y en los `CONTRIBUTING.md` |

**Ninguna de esas superficies nombra a los otros tres clientes ni dice «paridad con X»** (FR-031). La
paridad es una regla del monorepo, no una promesa al usuario.

---

## Lo que NO se toca

1. `package.json` de la CLI — sigue con **cero dependencias**, y **no gana ninguna mención de la
   TUI**: el paquete de la CLI no la anuncia ni la transporta (FR-049).
2. `Formula/git-review-workflow.rb`.
3. `.github/workflows/release.yml` — `v*` sigue siendo sólo la CLI.
4. **Lo que instalar la CLI deja en la máquina** (FR-079). Los dos one-liner ganan un flag apagado, y
   sin él su comportamiento y su salida son exactamente los de hoy.
5. **El pin de `bats@1.13.0` en sus cuatro lugares** (los tres runners de CI, `release.yml`,
   `tests/Dockerfile`). El job nuevo es Go; la suite bats no cambia de versión. `tests/ui.bats` corre
   con el bats que ya está.
6. `docs/.nojekyll`, `docs/logo.svg`, `docs/og.png` — generados, nunca a mano.
