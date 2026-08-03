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

| Campo        | Valor                            |
|--------------|----------------------------------|
| Container id | `gitReview`                      |
| View id      | `gitReview.walkthrough`          |
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
│ [ ver cambios ]                       │
│ [ ‹ prev ]  [ next › ]                │
├───────────────────────────────────────┤
│ 3 sin cobertura                       │ ← pie: abre su QuickPick; sin
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
- "trabajando…" mientras hay una invocación en vuelo (FR-030) va en la barra; no
  reemplaza el contenido.
- Esencial (walk) y con ediciones guardadas (step) se distinguen por **texto**
  además del color (FR-007, FR-027, FR-031).
- El identificador que se muestra es `PathRef.display` en walk y el SHA corto en
  step (FR-012).
- En `mode = whole` sin walkthrough el panel lo explica y no ofrece secuencia ni
  navegación (FR-026); no es un error.
- El *why* de la entrada actual es el cuerpo, con sus saltos de línea (FR-017).
  Sus cuatro estados —en vuelo, presente, ausente, fallido— se muestran
  distinguibles (FR-018, `data-model.md` § `PanelModel`).
- El panel muestra la entrada actual y **no** ofrece acceso a la secuencia
  completa: ésa vive en `gitReview.goToEntry`, desde la paleta. Los archivos sin
  cobertura siguen siendo una superficie **separada** de la secuencia, nunca
  mezclada con ella (FR-008).
- El *why* del panel es el texto entero, no un recorte: el link a `showWhy` abre
  el mismo contenido renderizado como Markdown en un editor, y por eso se
  anuncia como "abrir en el editor" y no como una lectura más completa.

### Estados vacíos

Uno por valor de `Situation` distinto de `review`, renderizado por el propio
panel: párrafo explicativo y un botón, salvo `error` (Decisión 5). **No** son
contribuciones `viewsWelcome` del manifiesto — el host sólo las renderiza en
vistas de tipo `tree`, así que con esta vista no se mostrarían.

| `situation`    | Botón                | Comando                       |
|----------------|----------------------|-------------------------------|
| `no-review`    | Cómo iniciar una review | (link a los README)        |
| `out-of-range` | Cómo arreglarlo      | `gitReview.showOutOfRangeHelp` |
| `cli-missing`  | Instalar la CLI      | `gitReview.installCli`        |
| `cli-outdated` | Actualizar la CLI    | `gitReview.installCli`        |
| `error`        | (ninguno)            | —                             |

En `error`, `out-of-range`, `cli-missing` y `cli-outdated` el `stderr` de la CLI
se muestra íntegro y tal cual (FR-024).

### Protocolo con el webview

El webview **no ejecuta comandos**. Postea mensajes `{type}` de un conjunto
cerrado y el host decide qué hacer con cada uno; un `type` desconocido se
ignora. La lista es exactamente: `openEntry`, `openChange`, `showWhy`, `next`,
`prev`, `refresh`, `showUncovered`, `installCli`, `outOfRangeHelp`.

En el sentido inverso, el host postea el `PanelModel` entero
(`{type: "model", model}`) y el webview lo dibuja de cero. Todo el contenido
variable —paths, *why*, `stderr`— se inserta con `textContent`; el HTML se sirve
con CSP restrictiva y `nonce` para el único script inline (Decisión 4).

## Comandos

Los ids son interfaz pública.

| Command id                | Título                  | Dónde aparece                     |
|---------------------------|-------------------------|-----------------------------------|
| `gitReview.openEntry`     | Abrir entrada           | panel (identificador), paleta     |
| `gitReview.openChange`    | Ver cambios             | panel (botón), paleta             |
| `gitReview.showWhy`       | Ver el porqué           | panel (botón), paleta             |
| `gitReview.next`          | Entrada siguiente       | panel (botón), paleta             |
| `gitReview.prev`          | Entrada anterior        | panel (botón), paleta             |
| `gitReview.goToEntry`     | Ir a una entrada        | paleta                            |
| `gitReview.showUncovered` | Archivos sin cobertura  | panel (pie), paleta               |
| `gitReview.refresh`       | Refrescar               | título de la vista, paleta        |
| `gitReview.installCli`    | Instalar la CLI         | panel (estados sin CLI), paleta   |

El título de la vista lleva **sólo** `refresh`: navegar y saltar de entrada
tienen su lugar en el cuerpo del panel o en la paleta, y repetirlos como íconos
arriba no agregaba una superficie, agregaba una copia.

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
- `gitReview.goToEntry` y `gitReview.showUncovered` abren un `QuickPick` con la
  colección que les corresponde, en el orden de la CLI, y **abren** lo elegido
  (FR-005a, FR-008). No mueven el cursor: la CLI no tiene un verbo para saltar a
  una posición arbitraria, y sintetizarlo con `next`/`prev` sería inventar
  comportamiento propio (FR-002, FR-016). Mover el cursor sigue siendo
  `next`/`prev`.
- `gitReview.goToEntry` marca la entrada actual dentro del `QuickPick` y arranca
  posicionado en ella (FR-006).

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
