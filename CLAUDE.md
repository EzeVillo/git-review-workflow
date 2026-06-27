# CLAUDE.md

## Qué es esto

Una suite de verbos de `git review` (shell POSIX) para revisar un pull request
**editándolo y ejecutándolo**. Todo cuelga del dispatcher `git review <verbo>`,
al estilo de `git bisect`/`git stash`. `git review start` materializa el diff
completo del PR como cambios *staged y sin commitear* sobre una rama
`review/<branch>` cuyo `HEAD` queda en el merge-base; editás/ejecutás en tu
working tree y después `git review finish` extrae *tus* ediciones a una rama
aparte `review-fixes/<branch>`. Ver `README.md` para la superficie completa de
comandos.

## Comandos (desarrollo)

```sh
# Lint — todo script de shell debe pasar shellcheck. `find` recorre bin/
# (incluido el subdirectorio privado bin/git-review-verbs/, que el glob `bin/*`
# ya no alcanza) y excluye el .gitkeep; cubre el dispatcher y todos los verbos.
shellcheck $(find bin -type f ! -name '.gitkeep') install.sh uninstall.sh web-install.sh web-uninstall.sh bump-version.sh

# Tests — bats. En Windows NO corras bats bajo Git Bash (minutos por archivo,
# fork emulado lento). Corré en el contenedor Linux:
./tests/run-docker.sh                 # toda la suite
./tests/run-docker.sh review.bats     # un solo archivo
./tests/run-docker.sh tests/range.bats extras.bats   # cualquier arg/path de bats
```

La imagen de Docker (bats + git, `tests/Dockerfile`) se construye en el primer
uso y el repo se monta read-only; los tests crean sus repos temporales dentro
del contenedor. Los tests del instalador de PowerShell (`*-ps1.bats`) necesitan
`pwsh`, que no está en el contenedor, así que solo corren de verdad en CI / en
Windows local. CI corre shellcheck + bats en runners reales de **ubuntu, macos
y windows** en cada push y PR. Cada OS instala bats/shellcheck de una fuente
distinta (`apt` / `brew` / `npm`), con versiones distintas: usá solo
flags/comandos que funcionen en los tres. Apuntá al mínimo común denominador y
no asumas que la versión más nueva (típicamente la de Windows/npm local)
representa a las otras — p. ej. `bats --abort` anda en npm pero rompe el bats
viejo de apt en Ubuntu.

## Arquitectura

- **`bin/git-review`** — el dispatcher, el **único** ejecutable que va al `PATH`
  (`git` lo descubre como `git review`). Rutea `git review <verbo> [args]` al
  ejecutable del verbo: resuelve su propia ubicación real (siguiendo symlinks),
  exporta `GIT_REVIEW_LIBEXEC=<su dir>`, hace `shift` y `exec`utea
  `git-review-verbs/<verbo>`. `-h`/sin args lista los verbos; `--version`/`-V`
  imprime la versión. Un verbo inexistente da `error:` a stderr (exit ≠ 0).
- **`bin/git-review-verbs/*`** — un ejecutable de shell POSIX por verbo (sin
  extensión; `chmod +x`), `prog="git review <verbo>"`. Son **privados**: no van
  al `PATH` ni se llaman `git-*`, así que `git` no los descubre como
  `git <verbo>`; el único punto de entrada es el dispatcher. Los que usan helpers
  compartidos sourcean `"${GIT_REVIEW_LIBEXEC:?}/git-review-lib.sh"`.
- **`bin/git-review-lib.sh`** — se *sourcea, nunca se ejecuta*. Tiene los
  helpers compartidos por los verbos de modo `--step` (`show_commit`,
  `load_step_review_meta`, `goto_step`). Los verbos lo sourcean vía
  `"${GIT_REVIEW_LIBEXEC:?}/git-review-lib.sh"` (el dispatcher exporta esa var con
  su dir real resuelto). Como solo define funciones, sourcearlo no tiene efectos
  secundarios. Es **libexec**: vive junto al dispatcher y los verbos, nunca en el
  `PATH` (symlink/copia según el instalador; ver `install.sh` / Homebrew /
  `web-install`).

### Modelo de estado — dónde vive el estado del review

Las sesiones de review son stateful y guardan todo en los datos de git del
repo, no en archivos del working tree:

- **Ramas:** `review/<branch>` (review activo), `review-fixes/<branch>`
  (ediciones extraídas), `review-saved/<branch>` (review pausado).
- **Config por rama** (`branch.review/<x>.review*`): `reviewmode`,
  `reviewsource`, `reviewtip`, `reviewstart`, `reviewcount`, `reviewstep` —
  llevan el modo y la posición en `--step`. Se leen defensivamente (`|| true`)
  porque con `set -eu` una clave borrada a mano abortaría el script en silencio.
- **Refs de ediciones:** `refs/review-edits/<src>/<step>` bancan las ediciones
  de cada commit en `--step` como objetos commit-tree; `git review save` los mueve
  a `refs/review-saved-edits/` para que `git review clean` (que poda
  `refs/review-edits/`) nunca toque un review guardado.
- **Marcadores `--delta`:** las claves de config `reviewworkflow.<src>.reviewed`
  registran el último tip revisado. Son deliberadamente *persistentes* —
  sobreviven a `git review clean`; solo se limpian con `git review forget --delta`.
- **Entradas de config:** `reviewworkflow.base` (dónde se integran los PRs — sin
  default, un review completo falla sin él) y `reviewworkflow.remote` (default
  `origin`). Ambas son claves `git config` por repo, por diseño.

## Convenciones

- **Espejar los idioms de git.** Es el principio rector del proyecto: preferir
  diseños consistentes con git nativo (omitir el arg para la rama actual, `--`
  para terminar el parseo de opciones, riesgo asimétrico en los verbos
  destructivos) antes que inventar comandos nuevos.
- **Solo shell POSIX (`sh`)**, con `set -eu` arriba de cada script. Nada de
  bashisms — los comandos deben correr bajo `dash`/Git Bash. El repo también
  trae *instaladores* de PowerShell (`web-install.ps1`), pero los comandos en sí
  son POSIX.
- **`sed` multiplataforma:** GNU y BSD difieren en `-i`; hacé las ediciones
  in-place a través de un archivo temporal (ver `sed_i` en `bump-version.sh`).
- **Tests con asserts fuertes, sin falsos positivos.** Cada `@test` de bats debe
  fallar de verdad cuando el comportamiento se rompe. En concreto:
  - Afirmá el `status` esperado *además* de la salida (`[ "$status" -eq 0 ]` /
    el código de error que corresponda). Nunca dejes pasar un test solo porque
    el comando no abortó.
  - Para verificar contenido preferí igualdad o aserciones específicas
    (`[ "$output" = "..." ]`) antes que `grep`/globs laxos que matchean de más;
    si usás `[[ "$output" == *"x"* ]]`, que el patrón sea único y significativo.
  - Verificá el **efecto real** sobre el estado de git (ramas/refs/config/working
    tree), no solo el texto impreso.
  - Para los casos de error, afirmá el exit code *y* el mensaje en `stderr`, y
    confirmá que el efecto colateral NO ocurrió.
  - Nada de tests tautológicos (que pasan pase lo que pase) ni asserts comentados.
  - **Nombres de `@test` en ASCII puro.** Nada de em dashes (`—`), acentos ni
    otros caracteres no-ASCII en el texto del nombre. bats convierte cada nombre
    en un nombre de función shell escapando byte por byte, y el bats de Windows
    en CI trastabilla con los bytes UTF-8 → `unknown test name '...\342-80-94...'`
    (pasa en Linux/macOS, rompe en Windows). El cuerpo del test puede tener lo
    que sea; es solo el nombre el que se vuelve nombre de función.

## Release

La versión está duplicada a propósito: `VERSION` y `bin/git-review` viajan
dentro del tarball; `Formula/git-review-workflow.rb` apunta a él. `./bump-version.sh
X.Y.Z` estampa los tres desde un solo argumento (deja a propósito el `sha256` de
la fórmula —desconocido hasta que existe el tarball del tag; el workflow de
release lo fija). Los releases se cortan pusheando un tag `v*`. Un
`tests/version-consistency.bats` protege contra el drift.
