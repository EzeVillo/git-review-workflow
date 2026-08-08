# Contrato: disposición del panel, por situación

**Feature**: `010-panel-intellij-acciones`

Este documento es la fuente de la que se escribe el bloque `panel_layout:` del
canónico `contracts/client-product-surface.yaml`. Cada fila se verificó contra
`vscode-extension/src/views/panelHtml.ts` en esta sesión; la referencia de línea
está para poder re-verificarla cuando el panel cambie.

**Cómo leerlo**: el orden de las filas *es* el orden de la pantalla, de arriba
abajo. `Row[a | b]` es una fila horizontal con los controles repartidos.
**Negrita** = control accionable. El resto es copy.

---

## `cli-missing` / `cli-outdated`

| # | Bloque | Contenido | Ref |
|---|---|---|---|
| 1 | Paragraph | `The git-review CLI ({min} or newer) was not found.` / `The installed git-review CLI is older than {min}.` | 911, 917 |
| 2 | Paragraph | `Install with npm (recommended):` / `Update with npm (recommended):` | 583 |
| 3 | CodeCommand | `npm install -g git-review-workflow` (o `@latest`) + **Copy** | 587 |
| 4 | Paragraph | `Reload the window after installing, or wait — the panel checks again every few seconds.` | 602 |
| 5 | Row | **Other install options** (`LINK`) | 604 |
| 6 | Stderr | si hay | 612 |

**Copy**: al accionar, el rótulo cambia a `Copied` por 1500 ms y vuelve
(panelHtml.ts:597). Es parte del contrato: FR-028 pide confirmación visible y
transitoria.

## `no-review` sin base configurada (setup)

| # | Bloque | Contenido | Ref |
|---|---|---|---|
| 1 | Paragraph | `Configure git review for this repository.` | 795 |
| 2 | Row | **Set the base branch** (`PRIMARY`) | 797 |
| 3 | Paragraph | `The base is where PRs land in this repo (main, develop, …). Full reviews compare the branch under review against it.` | 799 |
| 4 | Paragraph | `Remote: {remote} (optional).` | 802 |
| 5 | Row | **Change remote** | 803 |

Sin inventario, sin pie y sin arrancar review: la pantalla de setup es sólo esto.

## `no-review` con base configurada

| # | Bloque | Contenido | Ref |
|---|---|---|---|
| 1 | Heading | `Reviews in this repository` — sólo si hay alguna | 714 |
| 2 | InventoryRows | una fila por review (ver abajo) | 665 |
| 3 | Paragraph | `No active review on this branch.` | 813 |
| 4 | Row | **Start a review** (`PRIMARY`) | 813 |
| 5 | ToolsSection | `Other actions`: **Compare revisions**; `Row[`**Walkthrough: Init**`|`**Walkthrough: Build**`]` | 751 |
| 6 | ToolsSection | `Settings`: `Base: {base}.` + **Change the base branch**; `Remote: {remote}.` + **Change remote** | 820 |
| 7 | ToolsSection | `Support`: **Star on GitHub** | 782 |

Las tres secciones van plegadas y ancladas al pie; el cuerpo estira
(`fillsHeight = true`, panelHtml.ts:1208).

### Fila del inventario

| Parte | Contenido | Ref |
|---|---|---|
| Nombre | el de la rama | 669 |
| Badges | `current`, `orphan` | 670 |
| Meta | `{mode} · {pos}/{total}`, o `{mode}`, o `no metadata` | 634 |
| Controles | **Continue** (sólo guardadas; deshabilitado si no es reanudable) y **Discard** / **Discard orphan** (guardadas u huérfanas) | 692, 701 |
| Ayuda | ícono `?` con tooltip cuando no hay ningún control | 677 |

Tooltips (contrato, no decoración): `Continue` deshabilitado explica
`This branch has no review metadata — use Discard` o
`A review of this branch is already active`; `Discard` explica el verbo real que
se va a ejecutar.

## `finish-pending`

| # | Bloque | Contenido | Ref |
|---|---|---|---|
| 1 | Paragraph | `Finished. Your edits are staged on {destination}.` | 885 |
| 2 | Paragraph | `Commit and push them from Source Control. The review branch is kept so you can undo…` | 887 |
| 3 | Row | **Clean** (`PRIMARY`) \| **Undo finish** | 889 |

Todo dentro de un `Banner`. Sin pie, sin inventario, sin arrancar review.

## `out-of-range` y `error`

| # | Bloque | Contenido | Ref |
|---|---|---|---|
| 1 | Paragraph | `The cursor is out of range: the base moved.` / `Something went wrong reading the review state.` | 905, 925 |
| 2 | Row | **How to fix it** (`PRIMARY`) | 906, 926 |
| 3 | Stderr | el de la CLI | 907 |

## `review` — cabecera común a los tres modos

| # | Bloque | Contenido | Ref |
|---|---|---|---|
| 1 | IdentityBar | modo · origen (`+ · repo` en multi-raíz) · tip a 7 · posición/total | 940 |
| 2 | Note ×n | solo lectura, solo claves, base movida, degradado, `Range built against {base}.` — en ese orden | 1186 |

Las notas describen la review, no la entrada: se dibujan igual durante la carga
(panelHtml.ts:1183).

## `review` modo walk

| # | Bloque | Contenido | Ref |
|---|---|---|---|
| 3 | EntryHead | número con cero a la izquierda + una marca: `key`, o `uncovered`, o `edits` | 998 |
| 4 | EntryTitle | el path | 1034 |
| 5 | Why | presente / ausente / fallido / cargando, con su texto propio | 981 |
| 6 | Row | **open in editor** (`LINK`) — sólo con *why* presente | 1045 |
| 7 | Row | **File** \| **Diff** | 1117 |
| 8 | Row | **◀** \| **▶** — nombres accesibles `Previous entry` / `Next entry` | 1129 |

## `review` modo step

Igual que walk, con tres diferencias: el `EntryHead` lleva además el sha y el
autor (1008); el `EntryTitle` es el **asunto** del commit, y `This commit has no
subject.` cuando está vacío (1031); no hay bloque `Why` ni **open in editor**; y
la fila de apertura tiene un solo control, **Diff** (1115).

## `review` modo whole

| # | Bloque | Contenido | Ref |
|---|---|---|---|
| 3 | Heading | `{n} file` / `{n} files in this review` | 1160 |
| 4 | Row | **Diff** — tooltip `Open every change in this review at once` | 1163 |
| 5 | FileRows | una fila accionable por archivo; la última abierta marcada, tooltip `Last opened` | 1169 |

Rango vacío: en lugar de 3–5, un `EmptyMessage` con `This review's range does
not touch any files.` (1156).

## `finish-conflict`

Es una review legible, con dos diferencias:

| # | Bloque | Contenido | Ref |
|---|---|---|---|
| 2 | Banner | `This finish stopped at a conflict. Resolve the markers, then continue — or undo it to go back to editing.` + `Row[`**Undo**`|`**Continue**`]` — **antes** de las notas | 1091, 1217 |
| — | Row de navegación | **no se dibuja** (no basta con deshabilitarla) | 1055 |

## Cursor sin entrada

`EmptyMessage`: `The cursor does not point at any entry in the sequence.` (1225).

## Estado de carga (esqueleto)

Misma silueta que la entrada, con los bloques de contenido reemplazados por
`Skeleton` y **los controles reales deshabilitados** (panelHtml.ts:1065): barra
de identidad con la posición en bloque, notas normales, cabecera y título en
bloque, *why* en bloque sólo en walk, y las dos filas de controles.

Umbrales (panelHtml.ts:1242): 120 ms antes de mostrar el esqueleto —por debajo
la espera no se percibe y el esqueleto sería un parpadeo peor— y 800 ms de techo
para el *why*, pasado el cual se muestra la entrada con el *why* cargando
adentro.

## Barra de título del tool window

| Orden | Control | Condición | Ref |
|---|---|---|---|
| 1 | **Refresh** | siempre | package.json `view/title` |
| 2 | **Finish** | `review` && !solo lectura && !ocupado | ídem |
| 3 | **Save** | `review` && !ocupado | ídem |
| 4 | **Cancel** | (`review` \| `finish-conflict`) && !ocupado | ídem |
| 5 | **Preview edits** | (`review` \| `finish-conflict`) && !ocupado | ídem |

## Lo que el panel NO tiene

`goToEntry`, `forgetReview`, `previewEditsStat` y `showCliLog` **no** se dibujan
en ninguna situación: en la extensión existen sólo en la paleta de comandos. En
el plugin viven sólo en `Tools → git review`. Un control con cualquiera de esos
ids en el layout es un fallo de contrato, igual que la falta de uno de los que sí
están.

---

## Bloque a agregar al canónico

En `contracts/client-product-surface.yaml`, después de `actions:`. Forma
(abreviada al primer caso; el resto sigue el mismo molde):

```yaml
# Disposición del panel, en orden. Normativo para:
#   - intellij: PanelLayoutContractTest compara estructura completa
#   - vscode:   check-client-product-surface.mjs compara pertenencia de rótulos
panel_layout:
  cli-missing:
    - {block: paragraph, key: cli_missing_title}
    - {block: paragraph, key: npm_install_hint}
    - {block: code_command, control: copyCliInstall, label: "Copy"}
    - {block: paragraph, key: reload_or_wait}
    - {block: row, controls: [{id: installCli, label: "Other install options", emphasis: link}]}
    - {block: stderr, when: present}
  # … una entrada por situación, más las variantes de modo de `review`
title_actions:
  - {id: refresh,       label: "Refresh"}
  - {id: finishReview,  label: "Finish",        when: "review && !readonly && !busy"}
  - {id: saveReview,    label: "Save",          when: "review && !busy"}
  - {id: abortReview,   label: "Cancel",        when: "(review|finish-conflict) && !busy"}
  - {id: previewEdits,  label: "Preview edits", when: "(review|finish-conflict) && !busy"}
panel_excluded:  # existen como acción, nunca como control del panel
  [goToEntry, forgetReview, previewEditsStat, showCliLog]
```

## Verificación

**IntelliJ (estructural, completa)** — `PanelLayoutContractTest` lee este bloque
y, para cada situación, compara contra `panelLayout(fixture)`: identidad de los
controles, orden, agrupación en filas, énfasis, rótulo y habilitación. Corre en
`./gradlew test`, o sea en los tres sistemas operativos de CI.

**VS Code (pertenencia)** — `scripts/check-client-product-surface.mjs`:

1. cada `label` del canónico aparece literalmente en `panelHtml.ts`;
2. cada `id` de control del canónico está en `PANEL_MESSAGES`
   (o en `contributes.menus.view/title` si es de `title_actions`);
3. **ningún** literal de botón de `panelHtml.ts` queda fuera del canónico;
4. ningún id de `panel_excluded` aparece en `PANEL_MESSAGES`.

El punto 3 es el que atrapa el drift más probable: agregar un botón al panel de
la extensión sin registrarlo obliga a decidir explícitamente si el plugin lo
lleva también.
