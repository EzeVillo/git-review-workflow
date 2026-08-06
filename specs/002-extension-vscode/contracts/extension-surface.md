# Contrato: superficie de la extensión en VS Code

Lo que la extensión le contribuye al editor y, por lo tanto, lo que el usuario
puede invocar, ver o configurar. Es la parte del `package.json` (manifiesto)
que constituye interfaz pública: cambiar un `command.id` o una clave de
configuración rompe keybindings y `settings.json` de usuarios.

Las decisiones de forma están en `research.md` (4, 5, 6, 12); acá va el detalle
normativo.

## Activación

```json
"activationEvents": ["onView:gitReview.walkthrough"]
```

Activación perezosa: no corre nada hasta que la vista se abre por primera vez.
Ninguna invocación a la CLI ocurre al arrancar el editor — abrir una ventana en
un repositorio cualquiera no debe costar un proceso.

## Vista

Un view container propio en la Activity Bar, con una sola vista.

| Campo        | Valor                             |
|--------------|-----------------------------------|
| Container id | `gitReview`                       |
| View id      | `gitReview.walkthrough`           |
| Tipo         | `webview` (`WebviewViewProvider`) |

El tipo es interfaz pública igual que los ids: cambiarlo cambia qué
contribuciones del manifiesto el host renderiza (ver *Estados vacíos*).

### Estructura del panel

```text
┌───────────────────────────────────────┐
│ walk · review/feature/x        [2/7]  │ ← barra: modo, rama, posición/total
├───────────────────────────────────────┤
│ 02                             (key)  │ ← posición y marca de la entrada
│ src/limiter/bucket.ts                 │ ← PathRef.display (o SHA en step)
│                                       │
│ <el why del autor, tal cual>          │ ← cuerpo (walk)
│                                       │
│ [ ⧉ File ]  [ ⇄ Diff ]                │ ← en step, sólo Diff
│ [    ‹    ]  [    ›    ]              │ ← sólo ícono, con aria-label
├───────────────────────────────────────┤
│ 3 uncovered                           │ ← pie: abre su QuickPick; sin
└───────────────────────────────────────┘    archivos sin cobertura no se dibuja
```

Reglas normativas:

- El contenido principal es la **entrada actual**, elegida por coincidencia de
  `position`, nunca por `id` (FR-005, FR-006).
- La barra lleva `N/M` — posición y total derivado (FR-009) —, la advertencia de
  que la base se movió cuando `total ≠ recorded` (FR-011), y en multi-root de qué
  repositorio se trata (FR-029).
- La nota de walkthrough degradado con su motivo va en la barra (FR-010), y no
  impide usar la review.
- Mientras hay una invocación en vuelo (FR-030) el panel **reemplaza el cuerpo
  por un esqueleto** y deja fijos la barra, las notas y el pie: son del review,
  no de la entrada, y no cambian al navegar. La carga es **una sola fase**, no
  dos — cubre el verbo y el `--why` de la entrada nueva, para que el revisor no
  vea primero la entrada anterior con sus controles apuntando a ella y después un
  segundo estado de carga adentro del *why*. Tres reglas la acotan:
    - el esqueleto entra recién pasado un umbral (~120 ms), así que una
      navegación rápida pasa de una entrada a la otra sin parpadeo — salvo con el
      panel todavía en blanco, donde entra de una;
    - un *why* lento tiene techo (~800 ms): pasada esa espera se muestra la
      entrada, que ya es la correcta, con el *why* cargando adentro;
    - ningún control acciona sobre una entrada que no es la dibujada, ni siquiera
      en la ventana previa al esqueleto.
      El esqueleto lleva `role="status"` y su texto para lectores de pantalla, y su
      pulso se apaga con `prefers-reduced-motion` (FR-031).
- Esencial (walk) y con ediciones guardadas (step) se distinguen por **texto**
  (`key` / `edits`) además del color (FR-007, FR-027, FR-031).
- **El texto visible de toda la extensión va en inglés**, igual que el de la CLI
  cuyo `stderr` el panel muestra al lado del propio. Los términos son los del
  `--porcelain` (`key`, `uncovered`) y no sinónimos: la marca `key` del panel es
  el marcador `> key` del walkthrough.
- Un ícono reemplaza a la palabra sólo donde no desambigua nada (navegar) y la
  acompaña donde sí (archivo vs diff). Los íconos son **SVG inline**, no la
  fuente de codicons: cargarla obligaría a servir el `.ttf` como recurso del
  webview y a abrirle `font-src` a la CSP. Un control sin texto visible lleva
  `aria-label` y `title`: el ícono saca la palabra de la vista, no del árbol de
  accesibilidad.
- El identificador que se muestra es `PathRef.display` en walk y el SHA corto en
  step (FR-012).
- En `mode = whole` no hay secuencia ni navegación (FR-026), y eso no es un
  error: el cuerpo es el **listado de archivos del rango** (004), un inventario
  sin cursor. Sobre la lista va un solo control, que abre todos esos archivos
  juntos en un multi-diff — el equivalente del `Diff` que `step` ofrece por
  commit. Cada fila abre el diff del suyo, y la **última fila abierta queda
  marcada**: sin cursor, es lo único que dice por dónde iba la lectura. Esa
  marca la registra el host (no la CLI, que no la conoce) y persiste entre
  sesiones; se lleva por path y desaparece sola cuando ese archivo deja de estar
  en el rango. Es la **única** excepción a "la extensión no guarda estado", y lo
  es porque no hay ningún estado del review con el que pueda contradecirse.
- El *why* de la entrada actual es el cuerpo, con sus saltos de línea (FR-017).
  Sus cuatro estados —en vuelo, presente, ausente, fallido— se muestran
  distinguibles (FR-018, `data-model.md` § `PanelModel`).
- El panel muestra la entrada actual y **no** ofrece acceso a la secuencia
  completa: ésa vive en `gitReview.goToEntry`, desde la paleta. Los archivos sin
  cobertura siguen siendo una superficie **separada** de la secuencia, nunca
  mezclada con ella (FR-008).
- El *why* del panel es el texto entero, no un recorte: el link a `showWhy` abre
  el mismo contenido renderizado como Markdown en un editor, y por eso se
  anuncia como "open in editor" y no como una lectura más completa.

### Estados vacíos

Uno por valor de `Situation` distinto de `review`, renderizado por el propio
panel: párrafo explicativo y un botón, salvo `error` (Decisión 5). **No** son
contribuciones `viewsWelcome` del manifiesto — el host sólo las renderiza en
vistas de tipo `tree`, así que con esta vista no se mostrarían.

| `situation`    | Acción principal                                                                | Comando / mensaje                         |
|----------------|---------------------------------------------------------------------------------|-------------------------------------------|
| `no-review`    | How to start a review                                                           | (link a los README)                       |
| `out-of-range` | How to fix it                                                                   | `gitReview.showOutOfRangeHelp`            |
| `cli-missing`  | Bloque npm `npm install -g git-review-workflow` + Copy; *Other install options* | `copyCliInstall` / `gitReview.installCli` |
| `cli-outdated` | Bloque npm `…@latest` + Copy; *Other install options*                           | `copyCliInstall` / `gitReview.installCli` |
| `error`        | (ninguno)                                                                       | —                                         |

En `error`, `out-of-range`, `cli-missing` y `cli-outdated` el `stderr` de la CLI
se muestra íntegro y tal cual (FR-024).

#### El inventario de `no-review`

`no-review` es el único estado vacío con contenido propio: si el repositorio
tiene reviews en otras ramas, el panel las lista antes del párrafo y del link.
Salen de `list --porcelain`, la única fuente (ver `contracts/cli-invocation.md`).

```text
┌───────────────────────────────────────┐
│ Reviews in this repository            │
│                                       │
│ review/feature/checkout               │ ← activa: se lista, sin acción
│ walk · 3/9                            │
│                                       │
│ review/orphan               (current) │ ← sin metadata, y HEAD está ahí
│ no metadata                           │
│                                       │
│ review-saved/fix/quoting              │ ← guardada: el prefijo del nombre
│ step · 2/4              [ Continue ]  │   ya dice que lo está
├───────────────────────────────────────┤
│ No active review on this branch.      │ ← el estado vacío de siempre, que
│ How to start a review                 │   pasa a ser el pie del inventario
└───────────────────────────────────────┘
```

Reglas normativas:

- Una review **activa** en otra rama se muestra **sin acción**. No hay verbo para
  saltar a ella: sería `git checkout review/<x>`, git crudo, y el selector de
  rama del editor ya lo resuelve. Listarla es lo que resuelve el problema real,
  que es acordarse de que existe.
- Una review **guardada** lleva `Continue` → `gitReview.continueReview`, la
  única acción del inventario. Se deshabilita cuando la fila es huérfana
  (`orphan = 1`) o cuando existe además una activa para el mismo source: los dos
  casos en que el verbo fallaría, leídos del inventario y no re-derivados.
- El orden es el de la CLI, sin reordenar: activas primero, guardadas después,
  igual que `list` humano.
- Una fila huérfana se muestra igualmente, con `no metadata` donde iría el modo,
  porque son justo las que hay que limpiar (Acceptance Scenario 2 de US6 en la
  feature 001). `current` es la única marca del inventario: que una rama sea
  guardada ya lo dice su prefijo, y repetirlo en un badge sería una copia.
- Sin reviews en el repositorio, el estado vacío es el de siempre: el párrafo y
  el link, sin encabezado ni lista.
- El inventario **no** aparece en los otros estados vacíos. En `out-of-range` o
  `cli-missing` no hay inventario que mostrar: no se invocó.

### Protocolo con el webview

El webview **no ejecuta comandos**. Postea mensajes `{type}` de un conjunto
cerrado y el host decide qué hacer con cada uno; un `type` desconocido se
ignora. La lista es exactamente: `openEntry`, `openChange`, `openAllChanges`,
`showWhy`, `next`, `prev`, `refresh`, `installCli`, `copyCliInstall`,
`outOfRangeHelp`, `continueReview`, `startReview`, `setBase`, `setRemote`,
`undoFinish`, `resumeFinish`, `discardInventory`, `cleanReview`, `compareReview`,
`walkthroughInit`, `walkthroughBuild`, `openSupport`.

Finish / Save / Cancel **no** están en ese conjunto: se invocan como comandos
desde el título de la vista (`view/title`) o la paleta, no como mensajes del
webview. `undoFinish` / `resumeFinish` sí, porque viven en el banner del panel
(no en el chrome). `compareReview` / `walkthroughInit` / `walkthroughBuild` se
dibujan sólo en el empty state `no-review` **con base configurada** (sección
*Other actions*); la paleta sigue ofreciéndolos. `setBase` / `setRemote` se
dibujan en el **setup** (sin base: pantalla única de configuración) y, una vez
hay base, en la sección *Settings* del footer. `openSupport` también es sólo
del empty `no-review` configurado (sección *Support*, debajo de *Settings*): no
es un comando de la paleta ni de la CLI; el host abre una URL del allowlist con
`env.openExternal`.

`continueReview`, `openEntry` y `openChange` son los que llevan un dato además
del `type`, y es un **índice** (`{type, index}`), nunca el nombre de la rama ni
un path: en `continueReview` es la posición en `PanelModel.reviews`; en
`openEntry`/`openChange` es `PanelEntry.position` dentro de `PanelModel.files`
— sólo aplica en modo `whole` (004), que no tiene una entrada "actual" a la que
caer por default como sí tienen `step`/`walk`. El host lo resuelve contra su
propia copia del modelo y descarta lo que no caiga en rango: así el argumento
que termina en la CLI sale siempre del estado del host, y nada que venga del
webview se le pasa a un proceso. Un `index` ausente, no entero o fuera de rango
se ignora igual que un `type` desconocido — en `openEntry`/`openChange` eso
significa caer al comportamiento de siempre (la entrada actual, si la hay).

`openSupport` lleva un **`id`** (`{type: "openSupport", id}`), no un índice ni
una URL libre: el id es de un conjunto cerrado (`star`, …) y el host resuelve
la URL contra su allowlist. Un id desconocido se ignora. Sumar un destino nuevo
(LinkedIn, donaciones, rating de la extensión) es agregar el id al allowlist
del host y el botón en `renderSupport` del webview.

`copyCliInstall` lleva un **`kind`** (`{type: "copyCliInstall", kind}`),
`"install"` o `"update"`. El host resuelve el string npm allowlisteado y lo
escribe al clipboard; un `kind` desconocido se ignora. El panel muestra el
mismo comando y un botón Copy (feedback local "Copied"); no se confía texto
arbitrario del webview.

En `no-review` **sin base** (`noBaseConfigured`) el panel es sólo el setup
(base obligatoria + remote opcional): no hay inventario, Start ni footer.

En `no-review` **con base** el layout es un split vertical al estilo del Explorer
(Outline / Timeline): el cuerpo (inventario + Start) scrollea y las secciones
*Other actions* / *Settings* / *Support* viven en un footer anclado al borde
inferior (en ese orden); al abrir crecen hacia arriba sin abandonar el pie.

`openAllChanges` no lleva índice ni ningún otro dato: su unidad es el rango
entero de una review `whole`, no una de sus filas.

En el sentido inverso, el host postea el `PanelModel` entero
(`{type: "model", model}`) y el webview lo dibuja de cero. Todo el contenido
variable —paths, *why*, `stderr`— se inserta con `textContent`; el HTML se sirve
con CSP restrictiva y `nonce` para el único script inline (Decisión 4).

## Comandos

Los ids son interfaz pública.

| Command id                 | Título                 | Dónde aparece                           |
|----------------------------|------------------------|-----------------------------------------|
| `gitReview.openEntry`      | Open Entry             | panel (botón `File`), paleta            |
| `gitReview.openChange`     | Open Changes           | panel (botón `Diff`), paleta            |
| `gitReview.openAllChanges` | Open All Changes       | panel (botón `Diff` de whole), paleta   |
| `gitReview.showWhy`        | Show Why               | panel (link), paleta                    |
| `gitReview.next`           | Next Entry             | panel (ícono), paleta                   |
| `gitReview.prev`           | Previous Entry         | panel (ícono), paleta                   |
| `gitReview.goToEntry`      | Go to Entry            | paleta                                  |
| `gitReview.showUncovered`  | Show Uncovered Files   | panel (pie), paleta                     |
| `gitReview.refresh`        | Refresh                | título de la vista, paleta              |
| `gitReview.finishReview`   | Finish Review          | título de la vista, paleta              |
| `gitReview.saveReview`     | Save Review for Later  | título de la vista, paleta              |
| `gitReview.abortReview`    | Cancel Review          | título de la vista, paleta              |
| `gitReview.installCli`     | How to Install the CLI | panel (*Other install options*), paleta |
| `gitReview.continueReview` | Continue Saved Review  | panel (inventario de `no-review`)       |
| `gitReview.setBase`        | Set the Base Branch    | panel (setup / *Settings*), paleta      |
| `gitReview.setRemote`      | Set the Remote         | panel (setup / *Settings*), paleta      |
| `gitReview.undoFinish`     | Undo Finish            | panel (banner / finish-pending), paleta |
| `gitReview.resumeFinish`   | Resume Finish          | panel (banner finish-conflict), paleta  |
| `gitReview.showCliLog`     | Show CLI Log           | paleta (diagnóstico; no se auto-abre)   |

El título de la vista lleva el **ciclo de vida** de la review — `refresh`,
`finishReview`, `saveReview`, `abortReview` — como íconos. Navegar y saltar de
entrada tienen su lugar en el cuerpo del panel o en la paleta; repetirlos como
íconos arriba no agregaba una superficie, agregaba una copia. Finish / Save /
Cancel **no** se repiten dentro del webview: el chrome es su única superficie
de botón (además de la paleta).

Reglas normativas:

- Los botones `next`/`prev` del panel se deshabilitan con `busy` del
  `PanelModel` mientras hay una mutación en curso, pero quien garantiza FR-020
  es el `MutationLock`: una segunda invocación en vuelo se descarta, venga de
  donde venga.
- También se deshabilitan en los extremos de la secuencia, con `atFirst`/
  `atLast` del `PanelModel`: un control que no puede mover nada no se ofrece.
  Eso **no** decide si el cursor se mueve —sigue decidiéndolo el verbo
  (FR-016)—, es la lectura de la `position`/`total` que la CLI ya reportó, la
  misma que dibuja `2/3` en la barra. Invocar `next`/`prev` desde la paleta en
  un extremo sigue siendo posible, y ahí la respuesta es el aviso de la CLI
  propagado tal cual (ver contracts/cli-invocation.md).
- Los comandos de la paleta se ocultan con `when: gitReview.situation == review`
  — no tiene sentido ofrecer "entrada siguiente" donde no hay review.
- `gitReview.openEntry` abre el documento del working tree; con el archivo
  ausente (eliminado en el rango) cae en el diff (Decisión 10).
- `gitReview.openAllChanges` abre **todos** los archivos del rango en un solo
  multi-diff, y sólo existe en `whole`: es el equivalente del diff que `step`
  abre por commit, con el rango como unidad. Del lado derecho va el archivo del
  working tree y no un blob, así que el diff queda editable — en una review el
  working tree *es* el PR aplicado. Se oculta de la paleta fuera de whole
  (`gitReview.mode == whole`).
- `gitReview.goToEntry` y `gitReview.showUncovered` abren un `QuickPick` con la
  colección que les corresponde, en el orden de la CLI, y **abren** lo elegido
  (FR-005a, FR-008). No mueven el cursor: la CLI no tiene un verbo para saltar a
  una posición arbitraria, y sintetizarlo con `next`/`prev` sería inventar
  comportamiento propio (FR-002, FR-016). Mover el cursor sigue siendo
  `next`/`prev`.
- `gitReview.goToEntry` marca la entrada actual dentro del `QuickPick` y arranca
  posicionado en ella (FR-006).
- `gitReview.continueReview` es mutante y va por el `MutationLock`, igual que
  `next`/`prev`. A diferencia de ellos **pide confirmación**: cambia `HEAD` y
  reordena el editor entero, que no es el costo de un clic de navegación. No se
  ofrece en la paleta — sin el inventario delante no hay forma de elegir cuál
  resumir, y `git review continue` sin argumento ya hace eso mejor desde la
  terminal.

## Context keys

Publicadas con `setContext`. Son la única forma en que el estado influye en el
manifiesto. `gitReview.busy` ya no condiciona ninguna contribución —el título de
la vista quedó con `refresh` solo—, pero se sigue publicando: es el estado que
un keybinding propio necesita para no disparar una mutación sobre otra.

| Key                   | Valores                                                                                 |
|-----------------------|-----------------------------------------------------------------------------------------|
| `gitReview.situation` | `review` \| `no-review` \| `out-of-range` \| `error` \| `cli-missing` \| `cli-outdated` |
| `gitReview.mode`      | `whole` \| `step` \| `walk`                                                             |
| `gitReview.busy`      | booleano                                                                                |

## Configuración

| Clave            | Tipo   | Default | Para qué                                                                                   |
|------------------|--------|---------|--------------------------------------------------------------------------------------------|
| `gitReview.path` | string | `""`    | Ruta al dispatcher cuando `git` no lo descubre (Decisión 3). Vacío = invocar `git review`. |

Deliberadamente mínima. Nada de opciones de presentación ni de comportamiento:
lo que el panel muestra lo determina la CLI, y agregar ajustes crearía estado
del lado de la extensión que puede divergir de ella.

## Documento virtual del *why*

| Campo     | Valor                                  |
|-----------|----------------------------------------|
| Esquema   | `git-review-why`                       |
| Contenido | el payload de `status --why`, tal cual |
| Modo      | Markdown, sólo lectura                 |

El URI incorpora el path de la entrada; el contenido se resuelve en el momento,
sin caché (ver `data-model.md`, `Why`). Es la superficie de FR-017a: el mismo
texto que el panel muestra en crudo, acá renderizado y sin límite de espacio.

## Motor

`engines.vscode: ^1.75.0` (Decisión 12). Compatible con Windows, macOS y Linux
sin código específico por plataforma (FR-028) — la única diferencia por sistema
operativo es el descubrimiento del ejecutable, que resuelve `git`.
