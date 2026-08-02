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
- **Modo walk** (`reviewmode = walk`): un walkthrough (sidecar
  `.review/walkthrough.md`, committeado al PR por el autor con `git review
  walkthrough init/build`) convierte el `start` en un cursor de lectura sobre la
  review completa. El formato tiene tres piezas: el **preámbulo** (`## Heads-up`,
  todo lo previo a la primera entrada — `build` lo preserva verbatim menos los
  comentarios HTML, y `start`/`compare` lo imprimen una vez al entrar), las
  **entradas** (`## N. <path>` + el why) y el marcador reservado **`> key`** (línea
  suelta al tope del body: presencia = entrada esencial, ausencia = default; se
  filtra del why y se muestra como `(key)`). Los marcadores reservados van todos
  como líneas `> ...` al inicio del body — ver también el `> at: ` de v2. El cursor vive en claves *
  *propias** — `reviewwalkstep`
  (1-based) y `reviewwalkcount` (guard) — nunca en `reviewstart/reviewcount/
  reviewstep`: el guard de metadata de `finish` aborta si esas claves de step
  existen sin `reviewmode=step` (y hay un guard espejo para claves walk sin
  `reviewmode=walk`). La secuencia de entradas NO se persiste: se re-deriva en
  cada verbo parseando el walkthrough del tip y filtrando por intersección de
  paths con el rango real, igual que step re-deriva `commits` con `rev-list`. En
  walk `HEAD` queda clavado en el lower bound, así que la derivación es estable
  aunque el usuario edite. Walk no banca refs (las ediciones viven en el working
  tree, como whole); el cursor muere con la rama. Un walkthrough roto/stale nunca
  falla una review: degrada a whole con nota.
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
- **Hay DOS README y siempre se actualizan los dos.** `README.md` (inglés) y
  `README.es.md` (español) son traducciones espejo. Cualquier cambio de
  comportamiento (flags, superficie de comandos, tabla de verbos, ejemplos)
  tiene que reflejarse en *ambos* en el mismo cambio — nunca tocar solo uno.
- **La landing (`docs/index.html`) es pitch, no documentación.** Es la página de
  GitHub Pages. A propósito **no** documenta flags ni la tabla de verbos: para eso
  linkea a los README, así no hay una tercera superficie de docs que mantener
  sincronizada. Pero sí duplica cuatro cosas puntuales, y solo esas hay que
  revisarlas cuando el cambio las toca:
    1. la **tabla comparativa** (la de la landing es un recorte de 4 filas de la
       de los README);
    2. los **métodos de instalación** (npm / Homebrew / PowerShell / one-liner);
    3. los **comandos que aparecen en los ejemplos** — `start`, `next`, `finish`,
       `walkthrough init|build`, `reviewworkflow.base`;
    4. el **formato del walkthrough** que muestra el demo interactivo (el
       `## Heads-up`, `## N. <path>` + el *why*, y el badge `key`).
       Si tu cambio no toca nada de eso, la landing no se toca.
- **La landing es bilingüe en un solo archivo.** El inglés vive en el HTML (para
  que lo indexen los crawlers) y el español en el diccionario `ES` del `<script>`,
  emparejados por `data-i18n`. Si editás un texto con `data-i18n`, editá las dos
  puntas — igual que con los README. La vista mobile del cuadro comparativo se
  **genera desde la propia `<table>`** en JS, así que agregar una fila o una
  columna a la tabla ya se propaga sola: no la dupliques a mano.
- **Ante una duda genuina, preguntá.** Si hay una decisión de diseño o una
  ambigüedad real que no se resuelve leyendo el código, preguntarle al usuario
  suele ser más certero y económico que explorar a ciegas o adivinar y rehacer.
- **Solo shell POSIX (`sh`)**, con `set -eu` arriba de cada script. Nada de
  bashisms — los comandos deben correr bajo `dash`/Git Bash. El repo también
  trae *instaladores* de PowerShell (`web-install.ps1`) y un paquete npm, pero
  los comandos en sí son POSIX.
- **`sed` multiplataforma:** GNU y BSD difieren en `-i`; hacé las ediciones
  in-place a través de un archivo temporal (ver `sed_i` en `bump-version.sh`).
- **Nada de `A && B || C` como if-then-else.** shellcheck lo marca con SC2015
  (falla en Ubuntu y Windows en CI) porque `C` también corre si `B` falla, no
  solo si `A` es falso. Para guardas de validación usá un `if` explícito con la
  condición invertida: `if [ $# -eq 0 ] || [ -z "$1" ]; then die "..."; fi` en
  vez de `[ $# -gt 0 ] && [ -n "$1" ] || die "..."`. El idiom `A || C` a secas
  (sin `&&`) sí está permitido — no dispara SC2015.
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

## Landing (GitHub Pages)

`docs/index.html` se publica en GitHub Pages desde la rama `main`, carpeta
`/docs` (Settings → Pages → *Deploy from a branch*). **No hay build ni
workflow**: es un HTML estático autocontenido, así que cada push a `main` que
toque `docs/` lo republica solo en un par de minutos. Para previsualizarlo,
abrilo directo en el navegador — no necesita servidor.

- `docs/.nojekyll` evita que Pages lo pase por Jekyll.
- `docs/og.png` es la preview de los links (copia de `trailer-poster.png`);
  las URLs de `og:image` y `canonical` están hardcodeadas a
  `ezevillo.github.io/git-review-workflow/` — si algún día se le pone dominio
  propio, hay que tocar esas líneas del `<head>` (y agregar un `docs/CNAME`).
- `docs/` **no** está en `files` de `package.json`, así que no viaja en el
  tarball de npm ni infla el paquete.

## Release

La versión está duplicada a propósito: `VERSION`, `bin/git-review` y
`package.json` viajan dentro del tarball (npm publica la versión de
`package.json`); `Formula/git-review-workflow.rb` apunta al tarball.
`./bump-version.sh X.Y.Z` estampa los tres desde un solo argumento (deja a
propósito el `sha256` de la fórmula —desconocido hasta que existe el tarball del
tag; el workflow de release lo fija). Los releases se cortan pusheando un tag
`v*`: el workflow crea el GitHub Release, fija la fórmula y publica a npm vía
Trusted Publishing (OIDC, sin `NPM_TOKEN`: el repo está registrado como trusted
publisher en npmjs.com). Un `tests/version-consistency.bats` protege contra el
drift.
