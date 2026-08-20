# Jerarquía de botones de la fila del borrador

**Fecha:** 2026-08-19
**Alcance:** los tres clientes (VS Code, JetBrains, Visual Studio) + el contrato canónico.
**No toca:** la CLI, la copy compartida, el conteo de 27 acciones.

## El problema

La fila del bloque *Reading orders you started* ofrece cuatro controles con dos
niveles de énfasis, y los cuatro son clases semánticas distintas:

| control | qué hace | énfasis hoy |
|---|---|---|
| Open | abre el borrador para editarlo | secondary |
| Copy for agent | pone un puntero al archivo en el portapapeles | secondary |
| Validate and start | valida y arranca la review | primary |
| Discard | borra prosa escrita a mano | secondary |

Tres problemas medidos contra el código:

1. **El primary no sigue al estado.** `startFromDraft` es primary con sólo mirar
   `startable` (que la CLI sepa el origen y el rango), no el progreso. Un borrador
   recién generado con `0/8` anotadas muestra el azul en *Validate and start*,
   cuando el paso siguiente real es llenarlo. Como un borrador vive incompleto casi
   toda su vida, el control enfático es el equivocado la mayor parte del tiempo.

2. **La destructiva es adyacente a la de compromiso.** *Discard* comparte estilo y
   vecindad con el resto y, con el wrap del sidebar, cae pegada al botón azul. La
   confirmación la hace recuperable, no la jerarquiza.

3. **Cuatro etiquetas de texto fuerzan el wrap.** *Copy for agent* es la más larga
   y empuja a *Validate and start* a la segunda línea, donde el primary arranca
   detrás de dos secundarios y la jerarquía visual se pierde.

Un cuarto detalle explica la sensación de "esto no encaja": `button.primary` está
definido con `width: 100%` porque es el botón full-width del cuerpo (*Start a
review*, *Set the base branch*, *Clean*); en `.rev-actions` se lo pisa con
`width: auto`. El azul de la fila es un primary prestado de otro contexto.

## Decisiones de producto

Dos, tomadas con el usuario:

**Open sobrevive como icono, no desaparece.** `openDraft`
(`vscode-extension/src/commands/draftActions.ts`) es el único lugar de los tres
clientes que abre ese archivo: el borrador vive en
`<gitdir>/review-walkthrough/<src>.md`, fuera del árbol versionado, y los editores
ocultan `.git` por defecto. Sin ese control queda inalcanzable — incluso para leer
lo que escribió el agente o arreglar un `unfilled entries remain`. Pasa a
`Emphasis.ICON` con el glifo `file`, que los tres clientes ya dibujan: saca el peso
textual, que era el problema, sin perder la acción, el tooltip ni el nombre
accesible.

**Discard se separa por espacio, no por icono.** Sigue siendo texto y sigue último,
con un hueco mayor que el gap normal entre controles. Un destructivo sin etiqueta es
más fácil de apretar por accidente, no menos, y un glifo `trash` nuevo costaría tres
dibujos (SVG inline, icono Swing, moniker WPF) para empeorar la legibilidad.

## Diseño

### Orden fijo, énfasis móvil

El orden de los controles **no cambia nunca**: mover el objetivo del click según el
estado es hostil. Lo que se mueve es el énfasis.

| control | forma | incompleto (`annotated < total`) | completo (`annotated == total`) |
|---|---|---|---|
| copyDraftPrompt | texto | **primary** | secondary |
| startFromDraft | texto | secondary | **primary** |
| openDraft | icono `file` | icon | icon |
| discardDraft | texto, separado | secondary | secondary |

Con `startable == false` (el bloque de instrucciones se borró a mano) la fila pierde
`startFromDraft`, como hoy: quedan Copy *primary*, el icono y Discard separado.

### La regla que no es obvia

**`startFromDraft` nunca se deshabilita por progreso, sólo por `busy`.** El conteo
`annotated/total` sale de la CLI leyendo el disco, y el revisor puede tener el
borrador abierto con cambios sin guardar: `saveOpenDraft` guarda el documento antes
de validar, así que la acción funciona cuando el conteo todavía dice que no. Grisarlo
mentiría justo en el momento en que el revisor acaba de terminar de escribir. El
progreso decide el **énfasis**; nunca el **enabled**.

### Contrato

```yaml
draft_controls:
  copyDraftPrompt: {label: "Copy for agent", emphasis: secondary, emphasis_unfilled: primary, confirms: false}
  startFromDraft:  {label: "Validate and start", emphasis: primary, emphasis_unfilled: secondary, confirms: true}
  openDraft:       {label: null, accessible_name: "Open the reading order", emphasis: icon, confirms: false}
  discardDraft:    {label: "Discard", emphasis: secondary, confirms: true, separated: true}
```

`emphasis:` sigue siendo el escalar que los tres parsers ya leen — es el valor con el
borrador completo — y `emphasis_unfilled:` es opcional: sin la clave, el énfasis no
depende del progreso. Así los verificadores se extienden en vez de reescribirse, y
una divergencia futura se sigue declarando en el contrato y no en un cliente.

### Capas

**Dominio (×3):** `panelModel.ts` / `PanelLayout.kt` / `PanelLayout.cs`.
- `Control` gana `separated: Boolean` (default `false`).
- La construcción de la fila elige el énfasis con `annotated == total`.
- `openDraft` pasa a `label = null` + `accessibleName` + `Emphasis.ICON`. El
  invariante que ya existe (label nulo ⟹ ICON ⟹ accessibleName no vacío) lo cubre.

**Renderers (×3):** hueco mayor antes del control marcado `separated` (gap en CSS,
strut en Swing, margen en WPF). En el webview, `iconButton()` gana el parámetro
`index` — hoy no lo acepta y los controles de fila lo necesitan.

**Verificadores:** el regex de `draft_controls` y el de `iconButton` en
`scripts/check-client-product-surface.mjs`, más `PanelLayoutContractTest.kt` y
`PanelLayoutContractTests.cs`, que hoy afirman el orden
`[openDraft, copyDraftPrompt, startFromDraft, discardDraft]` y un `emphasis` escalar.

**Fixtures (×3):** una tercera fila **completa** en `noReviewDrafts` (`1/1`). Hoy las
fixtures tienen `3/9` y `0/5`: ninguna cubre el borrador terminado, que es
exactamente el estado donde el primary cambia de manos. Agregarla la mete sola en el
preview del webview, en `runPanelPreview` y en la galería `--preview` de Visual
Studio.

**Docs:** los cuatro bullets y la fila de tabla de `vscode-extension/README.md`, y el
CHANGELOG de los tres clientes. Los README de la raíz no se tocan: esto es superficie
de cliente, no de CLI.

## Tests

Por cliente, contra el dominio (no contra el render):

1. Fila incompleta → `copyDraftPrompt` primary, `startFromDraft` secondary.
2. Fila completa → invertido.
3. `startFromDraft` habilitado con `annotated < total` y `busy == false`.
4. `openDraft` es ICON, con `accessibleName` no vacío y el índice de su fila.
5. `discardDraft` es el último y lleva `separated`.
6. Contrato: labels, orden y los dos énfasis contra el YAML.

Más `node scripts/check-client-product-surface.mjs` en CI, que ata las tres puntas.

## Fuera de alcance

- La copy compartida (`draft_agent_prompt`) y las etiquetas visibles.
- El conteo fijo de 27 acciones: los cuatro siguen siendo controles del cuerpo.
- Un icono `trash` nuevo.
- La CLI y sus dos README.
