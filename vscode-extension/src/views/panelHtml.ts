import {NPM_INSTALL_CMD, NPM_UPDATE_CMD} from "../cli/installHint";
import {MIN_CLI_VERSION} from "../cli/version";

/**
 * HTML del panel, separado del provider y sin depender de `vscode`: así se abre
 * en un navegador con un `PanelModel` de ejemplo y se verifica el render, algo
 * que ninguna suite de tests puede hacer (un webview corre en su propio contexto).
 *
 * Todo el color sale de variables `--vscode-*` (incluye alto contraste); los
 * controles son `<button>` reales para heredar tab order y foco del host. Script
 * único, inline, con `nonce`; el contenido variable se inserta con `textContent`,
 * nunca con `innerHTML`.
 *
 * **El texto visible va en inglés**, como el de la CLI: el panel muestra su
 * stderr al lado del propio y el `--porcelain` de donde sale todo habla en
 * inglés. Ícono solo donde alcanza (navegar); ícono + palabra donde desambigua
 * (archivo vs diff). Sin texto visible, el botón lleva `aria-label`.
 */
export function panelHtml(nonce: string): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}';">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style nonce="${nonce}">
  /* 100% del webview: no-review es un split vertical al estilo del Explorer
     (archivos arriba, Outline/Timeline abajo). El body scrollea; el footer
     (Walkthrough + Compare + Settings + Support) queda anclado al borde inferior y
     al abrir crece hacia arriba robándole alto al body — no salta al flujo
     de Start. El modo setup (sin base) no usa footer. */
  html, body { height: 100%; }
  body {
    margin: 0;
    padding: 0;
    color: var(--vscode-foreground);
    font-family: var(--vscode-font-family);
    font-size: var(--vscode-font-size);
  }
  #root { min-height: 100%; box-sizing: border-box; }
  /* Solo no-review fija el alto y recorta: el split body/footer maneja el scroll.
     En review el root sigue creciendo y el body del documento scrollea. */
  #root.fills {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 100%;
    overflow: hidden;
  }
  .pane-main {
    flex: 1 1 auto;
    display: flex;
    flex-direction: column;
    min-height: 0;
    height: 100%;
    overflow: hidden;
  }
  /* Contenido principal (inventario + Start/base): cede alto al footer. */
  .pane-body {
    flex: 1 1 auto;
    min-height: 0;
    overflow: auto;
  }
  /* Secciones secundarias al pie: headers siempre visibles; abiertas, el
     contenido crece dentro de un tope para no borrar el body.

     El pie es UN solo contenedor scrolleable: cada seccion pide el alto de su
     contenido y, cuando entre todas se pasan del tope, la barra que alcanza el
     resto es la del pie —una sola para todas—. Es lo mismo que hacen el
     JScrollPane del plugin de JetBrains y el ScrollViewer del de Visual
     Studio. Antes cada seccion abierta se repartia el alto del pie y scrolleaba
     por dentro: tres barras chiquitas, ninguna capaz de mostrar su seccion
     entera, y el pie sin barra propia. */
  .pane-footer {
    flex: 0 1 auto;
    min-height: 0;
    max-height: 55%;
    overflow-y: auto;
    overflow-x: hidden;
  }
  .bar {
    display: flex;
    align-items: baseline;
    gap: .5em;
    padding: .5em .8em;
    border-bottom: 1px solid var(--vscode-panel-border);
    font-family: var(--vscode-editor-font-family);
    font-size: .9em;
    color: var(--vscode-descriptionForeground);
  }
  .bar .mode { color: var(--vscode-textPreformat-foreground); }
  /* De quién es el orden de lectura. Va en el color del resto de la barra —no
     en el del modo— porque es una precisión sobre el modo, no otro dato: el
     mismo peso visual que le da la terminal escribiendo "walk (draft)". */
  .bar .draft { flex: none; }
  .bar .branch {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  /* El tip no se recorta: ya viene abreviado a siete caracteres, y es lo que se
     pega en una terminal. Quien cede el ancho es el nombre del origen. */
  .bar .tip { flex: none; }
  .bar .pos { margin-left: auto; font-variant-numeric: tabular-nums; }
  .note {
    padding: .5em .8em;
    border-bottom: 1px solid var(--vscode-panel-border);
    color: var(--vscode-descriptionForeground);
    font-size: .9em;
    line-height: 1.5;
  }
  /* Un cierre trabado no es una nota de paso (baseMoved/degraded): es lo único
     que puede hacer ahora mismo, así que lleva el color de advertencia del
     tema — nunca uno propio — y sus botones a ancho completo como el resto de
     los diálogos de riesgo del panel. */
  .note.finish-banner {
    color: var(--vscode-foreground);
    border-left: 3px solid var(--vscode-editorWarning-foreground);
    background: var(--vscode-inputValidation-warningBackground);
  }
  .note.finish-banner p { margin: 0 0 .6em; }
  .body { padding: .9em .8em .6em; }
  .head {
    display: flex;
    align-items: baseline;
    gap: .5em;
    margin-bottom: .2em;
    font-family: var(--vscode-editor-font-family);
    font-size: .9em;
    color: var(--vscode-descriptionForeground);
  }
  .head .n { font-variant-numeric: tabular-nums; }
  /* En step el head lleva además el SHA y el autor. El SHA no se recorta nunca
     —es el identificador que se pega en una terminal— y el autor cede primero:
     es el más largo y el menos exacto de los dos. */
  .head .sha { flex: none; }
  .head .who {
    flex: 0 1 auto;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  /* Dos marcas con peso distinto: "edits" es un estado propio del revisor y va
     en outline, del color del texto normal para separarse del gris del head;
     "key" es lo que el autor del walkthrough marcó como esencial y va sólido,
     con las variables badge-* — el mismo token que VS Code usa para sus
     contadores, así que el contraste ya está resuelto en todos los temas
     (incluidos los de alto contraste, FR-031). */
  .badge {
    margin-left: auto;
    padding: 0 .4em;
    border: 1px solid var(--vscode-panel-border);
    border-radius: 3px;
    font-size: .85em;
    color: var(--vscode-foreground);
  }
  .badge.key {
    border-color: transparent;
    background: var(--vscode-badge-background);
    color: var(--vscode-badge-foreground);
  }
  /* "not covered" no es un estado del revisor ni del autor del walkthrough: es
     un aviso, del mismo color que usan las notas del panel. */
  .badge.uncovered {
    border-color: transparent;
    color: var(--vscode-descriptionForeground);
  }
  .id {
    margin: 0 0 .9em;
    font-family: var(--vscode-editor-font-family);
    overflow-wrap: anywhere;
    line-height: 1.4;
  }
  /* Un asunto vacío: la ausencia dicha, no un bloque en blanco. */
  .id.quiet { color: var(--vscode-descriptionForeground); font-style: italic; }
  .why {
    margin: 0 0 1em;
    padding-left: .7em;
    border-left: 2px solid var(--vscode-panel-border);
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    line-height: 1.55;
  }
  .why { margin-bottom: .5em; }
  .why.quiet { color: var(--vscode-descriptionForeground); font-style: italic; }
  /* Los bloques del esqueleto de carga. El color sale de --vscode-foreground
     bajado de opacidad y no de un token de fondo: los de fondo (panel-border,
     textCodeBlock) desaparecen contra el sidebar en alguno de los temas, y éste
     contrasta por construcción en los tres (FR-031). */
  .sk {
    display: block;
    background: var(--vscode-foreground);
    border-radius: 3px;
    opacity: .16;
    animation: sk-pulse 1.4s ease-in-out infinite;
  }
  @keyframes sk-pulse {
    0%, 100% { opacity: .13; }
    50% { opacity: .3; }
  }
  /* El pulso es decoración: quien pidió menos movimiento igual tiene que ver
     que hay algo cargando, así que se apaga la animación, no el bloque. */
  @media (prefers-reduced-motion: reduce) {
    .sk { animation: none; opacity: .22; }
  }
  .sk-pos { width: 2.4em; height: .8em; }
  .sk-num { width: 1.5em; height: .8em; }
  .id.sk { width: 68%; height: 1.05em; }
  .why .sk { height: .8em; margin: .35em 0; }
  .why .sk:nth-of-type(1) { width: 100%; }
  .why .sk:nth-of-type(2) { width: 94%; }
  .why .sk:nth-of-type(3) { width: 62%; }
  /* Un esqueleto es invisible para un lector de pantalla: el texto va acá. */
  .sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
  .more { margin: 0 0 1em; font-size: .9em; }
  .row { display: flex; gap: .4em; margin-bottom: .4em; }
  .row button { flex: 1; }
  button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: .4em;
    font-family: inherit;
    font-size: inherit;
    padding: .35em .6em;
    border: none;
    border-radius: 2px;
    cursor: pointer;
    background: var(--vscode-button-secondaryBackground);
    color: var(--vscode-button-secondaryForeground);
  }
  /* Trazo currentColor: el ícono toma el color del botón que lo contiene, así
     que sirve igual sobre el fondo primario, el secundario y el de un tema de
     alto contraste, sin una regla por variante. */
  .icon {
    width: 1.05em;
    height: 1.05em;
    flex: none;
    fill: none;
    stroke: currentColor;
    stroke-width: 1.3;
    stroke-linecap: round;
    stroke-linejoin: round;
  }
  button:hover { background: var(--vscode-button-secondaryHoverBackground); }
  button.primary {
    background: var(--vscode-button-background);
    color: var(--vscode-button-foreground);
    width: 100%;
  }
  button.primary:hover { background: var(--vscode-button-hoverBackground); }
  button.link {
    background: none;
    color: var(--vscode-textLink-foreground);
    padding: 0;
  }
  button.link:hover { background: none; text-decoration: underline; }
  button:focus-visible, a:focus-visible {
    outline: 1px solid var(--vscode-focusBorder);
    outline-offset: 2px;
  }
  button[disabled] { opacity: .5; cursor: default; }
  .empty { padding: 1.2em .9em; line-height: 1.6; }
  .empty p { margin: 0 0 1em; }
  /* El inventario del estado vacío: una fila por review del repositorio. Va
     arriba del párrafo, porque "tenés esto abierto" contesta antes que "así se
     empieza una". El separador lo lleva el párrafo, no la lista, para que sin
     reviews el estado vacío quede exactamente como estaba. */
  .inv { padding: 1.2em .9em .2em; }
  /* Adentro de una seccion del pie el margen lateral ya lo puso .tools-inner:
     sumarle el del inventario sangraba las filas respecto del resto de la
     seccion, y dos bloques seguidos quedaban a sangrias distintas. */
  .tools-inner .inv { padding: .3em 0 .2em; }
  .inv h2 {
    margin: 0 0 .9em;
    font-size: .9em;
    font-weight: 600;
    color: var(--vscode-descriptionForeground);
  }
  .rev { margin-bottom: 1em; }
  .rev-head {
    display: flex;
    align-items: baseline;
    gap: .5em;
    margin-bottom: .25em;
  }
  .rev-name {
    font-family: var(--vscode-editor-font-family);
    overflow-wrap: anywhere;
  }
  /* Meta y acciones en filas distintas: en un sidebar angosto los botones no
     pelean con "step · 2/4" ni envuelven a medias la segunda línea. */
  .rev-meta {
    font-family: var(--vscode-editor-font-family);
    font-size: .9em;
    color: var(--vscode-descriptionForeground);
    margin-bottom: .35em;
  }
  /* Acciones del inventario: a la izquierda, ancho por el label (no flex:1 a
     todo el sidebar). "Delete leftover" es el más largo; el tope deja aire
     sin forzar una sola columna. */
  .rev-actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-start;
    gap: .4em;
    margin-bottom: 0;
  }
  .rev-actions button {
    flex: 0 1 auto;
    width: auto;
    max-width: 100%;
    white-space: nowrap;
  }
  /* La botonera de un borrador es una grilla de dos columnas y no una fila que
     envuelve: a ancho de sidebar dos etiquetas largas no entran en una línea
     de anchos libres, y envolviéndolas cada fila del bloque partía en un lugar
     distinto — ninguna se alineaba con la de al lado ni consigo misma. Celdas
     iguales se alinean siempre, y el peso visual queda libre para decir cuál
     es cuál. */
  .draft-actions {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: .4em;
  }
  /* Dos filas de borrador seguidas necesitan más aire entre sí que las del
     inventario: cada una es una cabecera con iconos más su botonera, y sin el
     hueco las dos se leen como un solo bloque de controles. */
  .rev.draft { margin-bottom: 1.5em; }
  .rev.draft .rev-head { margin-bottom: .45em; }
  .draft-actions button {
    width: auto;
    max-width: 100%;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  /* Los dos controles de la FILA, pegados al progreso que nombra su sujeto.
     Sin caja: en la cabecera, dos botones rellenos pesarían más que la botonera
     de abajo, que es la que sí mueve el flujo. El fondo aparece en hover, como
     en la toolbar de una vista de VS Code. */
  .rev-head-actions {
    display: flex;
    align-items: center;
    /* El grupo derecho de la cabecera arranca aca: los iconos toman el hueco y
       el badge, que va despues, lo pierde (regla de abajo). Sin esto los dos
       autos se repartian el espacio y el badge quedaba flotando en el medio. */
    margin-left: auto;
    /* .rev-head alinea por baseline, que es lo que quiere el nombre contra el
       badge y no lo que quiere un glifo: sin esto los dos iconos cuelgan por
       debajo del par que acompañan. */
    align-self: center;
    gap: .1em;
  }
  .rev-head-actions button {
    padding: .2em .3em;
    background: none;
    color: var(--vscode-descriptionForeground);
  }
  .rev-head-actions button:hover:not([disabled]) {
    background: var(--vscode-toolbar-hoverBackground);
    color: var(--vscode-foreground);
  }
  /* El badge SIEMPRE cierra la linea. En una fila sin iconos lo empuja su propio
     margin-left:auto; en una con iconos el hueco ya lo tomo el grupo de arriba,
     asi que el badge se queda pegado a el en vez de abrir un segundo hueco. */
  .rev-head-actions ~ .badge { margin-left: 0; }
  /* Badge "?" a la altura de current/orphan: el mensaje va solo en title. */
  .badge.help {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 1.15em;
    padding: 0 .25em;
    cursor: default;
    border-color: transparent;
    color: var(--vscode-descriptionForeground);
  }
  .badge.help .icon {
    width: .85em;
    height: .85em;
  }
  .empty.after-inv { border-top: 1px solid var(--vscode-panel-border); }
  /* Secciones del pie (Walkthrough / Compare / Support): mismo patrón que Outline y
     Timeline del Explorer — header fijo abajo, al abrir el body crece hacia
     arriba (el .pane-body de arriba se achica y scrollea). Nunca se "despegan"
     del fondo al abrir, y ninguna se recorta a si misma: quien scrollea es el
     pie entero. */
  .tools {
    border-top: 1px solid var(--vscode-sideBarSectionHeader-border, var(--vscode-panel-border));
  }
  .tools summary {
    cursor: pointer;
    font-size: .9em;
    font-weight: 600;
    list-style: none;
    padding: .45em .9em;
    color: var(--vscode-sideBarSectionHeader-foreground, var(--vscode-descriptionForeground));
    background: var(--vscode-sideBarSectionHeader-background, transparent);
  }
  .tools summary::-webkit-details-marker { display: none; }
  /* Twistie del sidebar de VS Code: chevron que gira al abrir (~120ms). */
  .tools summary::before {
    content: "";
    display: inline-block;
    width: .45em;
    height: .45em;
    margin-right: .45em;
    border-right: 1.5px solid currentColor;
    border-bottom: 1.5px solid currentColor;
    transform: rotate(-45deg);
    vertical-align: .15em;
  }
  .tools[open] summary::before {
    transform: rotate(45deg);
    vertical-align: .25em;
  }
  @media (prefers-reduced-motion: no-preference) {
    .tools summary::before { transition: transform .12s ease; }
  }
  /* Cuerpo de la sección: grid 0fr→1fr anima la apertura como el twistie.

     El track abierto va 1fr —o sea minmax(auto, 1fr)— justamente porque nunca
     baja del min-content: la sección se queda con el alto que pide su
     contenido y no lo recorta. Lo que no entra en el pie lo alcanza la barra
     del pie, que es una sola para todas las secciones. El overflow del inner
     se queda en hidden y es lo que recorta durante la animación. */
  .tools-body {
    display: grid;
    grid-template-rows: 0fr;
  }
  .tools[open] .tools-body {
    grid-template-rows: 1fr;
  }
  @media (prefers-reduced-motion: no-preference) {
    .tools-body { transition: grid-template-rows .12s ease; }
  }
  .tools-inner {
    overflow: hidden;
    min-height: 0;
  }
  .tools[open] .tools-inner {
    padding: .15em .9em .55em;
  }
  .tools-inner > button {
    display: flex;
    width: 100%;
    margin-bottom: .45em;
  }
  .tools-inner > button:last-child { margin-bottom: 0; }
  .tools-inner .row { margin-bottom: 0; }
  .tools-inner .row button { margin-bottom: 0; }
  /* El listado de whole (FR-010): mismo encabezado que el inventario, filas
     clickeables en vez de tarjetas — no hay estado por fila que mostrar. */
  .files { padding: 1.2em .9em; }
  .files h2 {
    margin: 0 0 .6em;
    font-size: .9em;
    font-weight: 600;
    color: var(--vscode-descriptionForeground);
  }
  .files .row { margin-bottom: .8em; }
  .file-row {
    display: flex;
    justify-content: flex-start;
    width: 100%;
    text-align: left;
    padding: .35em .4em;
    border-left: 2px solid transparent;
    background: none;
    color: var(--vscode-foreground);
    font-family: var(--vscode-editor-font-family);
    overflow-wrap: anywhere;
  }
  .file-row:hover { background: var(--vscode-list-hoverBackground); }
  /* La última fila abierta. Whole no tiene cursor, así que esto no es "dónde
     está el review" sino "por dónde iba yo": se marca con los tokens de
     selección inactiva —el mismo peso que VS Code le da a una fila elegida en
     una lista sin foco— más una barra al margen, porque en un tema de alto
     contraste el fondo solo puede no distinguirse (FR-031). */
  .file-row.opened {
    border-left-color: var(--vscode-textLink-foreground);
    background: var(--vscode-list-inactiveSelectionBackground);
  }
  .file-row.opened:hover { background: var(--vscode-list-hoverBackground); }
  .stderr {
    margin: 1em 0 0;
    padding: .6em;
    background: var(--vscode-textCodeBlock-background);
    font-family: var(--vscode-editor-font-family);
    font-size: .9em;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  /* Bloque copiable del empty state cli-missing/cli-outdated (estilo fenced
     code de un .md: fondo de code block + Copy al costado). */
  .code-block {
    display: flex;
    align-items: stretch;
    margin: 0 0 .8em;
    border-radius: 4px;
    overflow: hidden;
    background: var(--vscode-textCodeBlock-background);
    border: 1px solid var(--vscode-panel-border);
  }
  .code-block code {
    flex: 1 1 auto;
    min-width: 0;
    padding: .5em .65em;
    font-family: var(--vscode-editor-font-family);
    font-size: .9em;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .code-block .code-copy {
    flex: none;
    border-radius: 0;
    padding: .35em .65em;
    font-size: .85em;
  }
  /* Más específico que .empty p para no heredar el margin 1em de ahí. */
  .empty p.cli-install-hint {
    margin: 0 0 .4em;
    color: var(--vscode-descriptionForeground);
    font-size: .9em;
  }
  .empty p.cli-install-reload {
    margin: 0 0 .9em;
    color: var(--vscode-descriptionForeground);
    font-size: .85em;
  }
  /* La espera previa al primer modelo: un aviso, no contenido del panel. */
  .empty p.waiting { margin: 0; color: var(--vscode-descriptionForeground); }
  a { color: var(--vscode-textLink-foreground); }
</style>
</head>
<body>
<div id="root"></div>
<script nonce="${nonce}">
(function () {
  const vscode = acquireVsCodeApi();
  const root = document.getElementById("root");

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text !== undefined) { node.textContent = text; }
    return node;
  }

  // Los íconos son SVG inline y no codicons: la fuente de codicons es un
  // recurso que habría que servir desde la extensión y abrirle font-src a la
  // CSP, y este html se abre tal cual en un navegador para mirarlo. Los
  // trazos siguen el vocabulario del revisor (archivo, diff, chevrones) más
  // un ? de ayuda para las filas del inventario sin verbo.
  const SVG_NS = "http://www.w3.org/2000/svg";
  const ICONS = {
    file: ["M4 1.6h5l3 3v9.8H4z", "M9 1.6v3h3"],
    diff: ["M2.5 5.6h8.4", "M8.1 2.8 10.9 5.6 8.1 8.4", "M13.5 10.4H5.1", "M7.9 7.6 5.1 10.4 7.9 13.2"],
    prev: ["M10 3.4 5.4 8 10 12.6"],
    next: ["M6 3.4 10.6 8 6 12.6"],
    // Tapa, asa y cuerpo: el tacho de siempre. Es el único destructivo que se
    // dibuja como glifo, así que el trazo tiene que leerse a 1em sin la
    // etiqueta al lado.
    trash: [
      "M2.8 4.3h10.4",
      "M6.4 4.3V3.1a1 1 0 0 1 1-1h1.2a1 1 0 0 1 1 1v1.2",
      "M4.5 4.3v8.6a1 1 0 0 0 1 1h5a1 1 0 0 0 1-1V4.3"
    ],
    // Círculo + trazo del ? + punto: legible a 1em en el hint del inventario.
    help: [
      "M8 2.2a5.8 5.8 0 1 0 .01 11.6A5.8 5.8 0 0 0 8 2.2z",
      "M6.55 6.15c0-1.05.9-1.85 1.95-1.85s1.95.75 1.95 1.8c0 .9-.5 1.3-1.1 1.75-.55.4-.9.75-.9 1.4",
      "M8 10.85v.9"
    ]
  };

  function icon(name) {
    const svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "icon");
    svg.setAttribute("viewBox", "0 0 16 16");
    // El nombre del control lo da su texto o su aria-label; el ícono repetido
    // ahí sería ruido para un lector de pantalla.
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("focusable", "false");
    ICONS[name].forEach(function (d) {
      const path = document.createElementNS(SVG_NS, "path");
      path.setAttribute("d", d);
      svg.appendChild(path);
    });
    return svg;
  }

  function button(label, message, className, iconName, index) {
    const node = el("button", className);
    if (iconName) { node.appendChild(icon(iconName)); }
    if (label) { node.appendChild(el("span", null, label)); }
    node.addEventListener("click", function () {
      // Lo dibujado puede no ser el modelo vigente: durante la ventana de
      // gracia sigue en pantalla la entrada anterior, y "File"/"Diff" abrirían
      // el archivo equivocado. Deshabilitarlos no alcanza — el esqueleto entra
      // después que el clic ya es posible.
      // El índice es el único dato que un mensaje lleva además del type, y lo
      // valida el host contra su inventario (extension-surface.md § Protocolo).
      if (stale()) { return; }
      vscode.postMessage(index === undefined ? {type: message} : {type: message, index: index});
    });
    return node;
  }

  /**
   * Un control sin texto visible sigue necesitando nombre: el aria-label es
   * el que lee un lector de pantalla y el title el que aparece en hover.
   */
  function iconButton(iconName, message, label, index) {
    const node = button(null, message, null, iconName, index);
    node.setAttribute("aria-label", label);
    node.title = label;
    return node;
  }

  function note(text) { return el("div", "note", text); }

  function empty(text, action, stderr) {
    const box = el("div", "empty");
    box.appendChild(el("p", null, text));
    if (action) { box.appendChild(action); }
    if (stderr) { box.appendChild(el("pre", "stderr", stderr)); }
    return box;
  }

  /**
   * Empty state de cli-missing / cli-outdated: el camino recomendado es npm
   * con Copy (el host resuelve el string; acá solo viaja kind). "Other
   * install options" abre la guía completa (Homebrew / PowerShell / curl).
   */
  function cliInstallHint(kind) {
    const cmd = kind === "update"
      ? ${JSON.stringify(NPM_UPDATE_CMD)}
      : ${JSON.stringify(NPM_INSTALL_CMD)};
    const wrap = el("div", "cli-install");
    wrap.appendChild(el("p", "cli-install-hint",
      kind === "update"
        ? "Update with npm (recommended):"
        : "Install with npm (recommended):"));
    const codeRow = el("div", "code-block");
    codeRow.appendChild(el("code", null, cmd));
    const copyBtn = el("button", "code-copy");
    const copyLabel = el("span", null, "Copy");
    copyBtn.appendChild(copyLabel);
    copyBtn.title = "Copy to clipboard";
    copyBtn.setAttribute("aria-label", "Copy install command");
    copyBtn.addEventListener("click", function () {
      if (stale()) { return; }
      vscode.postMessage({type: "copyCliInstall", kind: kind});
      copyLabel.textContent = "Copied";
      setTimeout(function () { copyLabel.textContent = "Copy"; }, 1500);
    });
    codeRow.appendChild(copyBtn);
    wrap.appendChild(codeRow);
    wrap.appendChild(el("p", "cli-install-reload",
      "Reload the window after installing, or wait — the panel checks again every few seconds."));
    wrap.appendChild(button("Other install options", "installCli", "link"));
    return wrap;
  }

  function emptyCli(text, kind, stderr) {
    const box = el("div", "empty");
    box.appendChild(el("p", null, text));
    box.appendChild(cliInstallHint(kind));
    if (stderr) { box.appendChild(el("pre", "stderr", stderr)); }
    return box;
  }

  /** El modo y, en step/walk, la posición REGISTRADA — el inventario no la
   *  re-deriva (contracts/list-porcelain.md), a diferencia de la barra. */
  function reviewMeta(review) {
    if (review.orphan) {
      return "details are gone";
    }
    if (review.position !== undefined && review.total !== undefined) {
      return review.mode + " · " + review.position + "/" + review.total;
    }
    return review.mode;
  }

  /**
   * Hover del badge "?" cuando la fila no ofrece Continue/Discard: el inventario
   * lista la review para no olvidarla; el title dice por qué no hay verbo.
   */
  function inventoryHelpTitle(review) {
    if (review.finish) {
      const source = review.name.indexOf("review/") === 0 ? review.name.slice(7) : review.name;
      if (review.finish.state === "pending") {
        const dest = review.finish.onto ? source : "review-fixes/" + source;
        return "Finish waiting on " + dest + " — use Undo above.";
      }
      return "Finish stopped mid-conflict — switch to this branch to resolve or undo.";
    }
    return "Still active — switch to this branch to work on it.";
  }

  /**
   * Una review del repositorio. Tres capas: nombre (+ badges), meta, y debajo
   * acciones compactas a la izquierda. Guardadas: Continue + Discard. Orphans:
   * Discard. Activas en otra rama sin verbo: badge "?" con title al hover.
   */
  function renderReview(model, review, index) {
    const box = el("div", "rev");

    const head = el("div", "rev-head");
    head.appendChild(el("span", "rev-name", review.name));
    if (review.current) { head.appendChild(el("span", "badge", "current")); }
    if (review.orphan) { head.appendChild(el("span", "badge", "broken")); }

    // Discard: saved (incl. orphan saved) o orphan no-saved. Nunca la current
    // activa legible (abort cubre eso). Continue solo en saved.
    const canDiscard = review.saved || review.orphan;
    if (!canDiscard && !review.current) {
      const tip = inventoryHelpTitle(review);
      const help = el("span", "badge help");
      help.setAttribute("role", "img");
      help.setAttribute("aria-label", tip);
      help.title = tip;
      help.appendChild(icon("help"));
      head.appendChild(help);
    }
    box.appendChild(head);

    box.appendChild(el("div", "rev-meta", reviewMeta(review)));

    if (canDiscard) {
      const actions = el("div", "rev-actions");
      if (review.saved) {
        const go = button("Continue", "continueReview", null, null, index);
        go.disabled = model.busy || !review.resumable;
        if (!review.resumable) {
          go.title = review.orphan
            ? "This review cannot be resumed — its details are gone"
            : "You are already reviewing this branch";
        }
        actions.appendChild(go);
      }
      const discard = button(review.orphan ? "Delete leftover" : "Delete", "discardInventory", null, null, index);
      discard.disabled = model.busy;
      discard.title = review.saved
        ? "Delete this paused review and its edits"
        : "Delete this leftover branch";
      actions.appendChild(discard);
      box.appendChild(actions);
    }
    return box;
  }

  /**
   * Una fila del bloque de borradores: la rama, el avance tal como lo reporta
   * la CLI, y los cuatro controles sobre ESA fila. El progreso no se deriva ni
   * se reinterpreta acá — annotated/total llegan contados; lo único que se
   * decide con ellos es cuál de los controles lleva el énfasis, nunca cuál se
   * ofrece ni en qué orden.
   *
   * Los cuatro están siempre y en el mismo orden: cuando Validate and start
   * desaparecía —el caso de origen y rango unknown— cada fila armaba su propia
   * botonera y ninguna se alineaba con la de al lado. Apagado no adivina los
   * flags más que ausente, y encima dice por qué en el title.
   */
  function renderDraft(model, draft, index) {
    const box = el("div", "rev draft");

    // El avance va al lado del nombre y no en una línea propia: es un dato de
    // la rama, del largo de un badge, y una línea suelta por fila multiplicaba
    // el alto del bloque por nada.
    const head = el("div", "rev-head");
    head.appendChild(el("span", "rev-name", draft.branch));

    // Abrir y descartar son de la FILA, no del paso siguiente: no hacen avanzar
    // nada, se usan una vez cada tanto y su sujeto es el archivo que el badge
    // acaba de nombrar. Van pegados al progreso como iconos y dejan la botonera
    // de abajo con los dos controles del flujo, uno por columna y en una sola
    // línea — con cuatro, la fila medía el doble y el destructivo compartía
    // caja y peso con el que arranca la review.
    const rowIcons = el("div", "rev-head-actions");
    const open = iconButton("file", "openDraft", "Open the reading order", index);
    open.title = "Open the reading order for editing";
    rowIcons.appendChild(open);
    const discard = iconButton("trash", "discardDraft", "Discard the reading order", index);
    discard.disabled = model.busy;
    discard.title = "Delete this reading order";
    rowIcons.appendChild(discard);
    head.appendChild(rowIcons);
    // El badge cierra la linea, como en toda fila del panel: los estados de las
    // tres secciones caen asi en la misma columna del borde derecho, y los dos
    // iconos siguen pegados al progreso que nombra su sujeto.
    head.appendChild(el("span", "badge", draft.annotated + "/" + draft.total));

    box.appendChild(head);

    // Una fila cuya review ya terminó se queda acá: el par de abajo es el
    // flujo de escribir el orden y arrancar la review, y las dos cosas ya
    // pasaron. Copy for agent le pediría a un agente que complete lo que está
    // completo, y Validate and start ofrecería releer un rango que se cerró.
    // El archivo sigue existiendo y los dos iconos de arriba siguen siendo lo
    // que se quiere: abrirlo o tirarlo.
    if (draft.spent) {
      return box;
    }

    const actions = el("div", "draft-actions");
    // Un solo control enfático por fila, y el progreso decide cuál: mientras
    // falten entradas el paso siguiente es llenar el borrador, y recién con el
    // orden completo lo es arrancar la review. El ORDEN es fijo — mover el
    // objetivo del clic según el estado lo corre bajo el cursor.
    //
    // total == 0 es "el archivo no declara ninguna entrada", no "está
    // completo": la CLI reporta 0/0 tanto para un borrador vacío como para el
    // que un agente está escribiendo justo ahora (el watcher dispara con el
    // primer Changed, antes del primer "## N."). Sin el total > 0 esa fila se
    // dibuja como terminada y el énfasis va a Validate and start, que además
    // suele estar deshabilitado ahí (source/range unknown) — o sea que el
    // único control enfático de la fila no se puede ni apretar, justo en el
    // estado que más necesita que Copy for agent lidere.
    const filled = draft.total > 0 && draft.annotated >= draft.total;

    const copy = button("Copy for agent", "copyDraftPrompt", filled ? null : "primary", null, index);
    copy.title = "Copy an instruction naming this file";
    actions.appendChild(copy);

    // Siempre presente, apagado por dos motivos distintos que dicen lo suyo en
    // el title. El de los flags va primero: sin bloque de instrucciones el
    // build falla por deriva aunque el borrador esté completo, así que llenarlo
    // no es el paso siguiente ahí.
    //
    // Apagado por progreso es lo que le hace decir la verdad al par: el
    // esqueleto trae un placeholder por entrada Y uno de heads-up, y build los
    // rechaza a todos igual — dejarlo encendido ofrecía un start que moría en
    // "the heads-up placeholder is still there". El costo conocido es que el
    // conteo sale del disco: hasta que el borrador abierto se guarde (el
    // watcher del host refresca el panel con el Changed), el control sigue
    // gris. Guardar es un Ctrl+S, y arrancar sobre un orden a medio escribir
    // no tiene vuelta atrás.
    const go = button("Validate and start", "startFromDraft", filled ? "primary" : null, null, index);
    go.disabled = model.busy || !draft.startable || !filled;
    go.title = !draft.startable
      ? "This file lost its header, so it cannot be checked. Delete it and write a new one."
      : filled
        ? "Check the order, then start reading"
        : "Every file still needs a number and a line saying why it matters";
    actions.appendChild(go);

    box.appendChild(actions);
    return box;
  }

  /**
   * El bloque de borradores. Cada fila es un par [borrador, índice en
   * model.drafts]: el índice viaja al host y es el que resuelve de qué
   * archivo se habla, así que sigue siendo el de la lista COMPLETA aunque
   * acá se dibuje una parte.
   */
  function renderDrafts(model, rows, heading) {
    const box = el("div", "inv");
    // Sin encabezado propio en la sección plegada: ahí el título es el summary
    // del <details>, y un h2 abajo lo diría dos veces.
    if (heading) {
      box.appendChild(el("h2", null, heading));
    }
    rows.forEach(function (row) {
      box.appendChild(renderDraft(model, row[0], row[1]));
    });
    return box;
  }

  /** Los pares [borrador, índice] cuyo estado gastado es el pedido. */
  function draftRows(model, spent) {
    const rows = [];
    (model.drafts || []).forEach(function (draft, index) {
      if (Boolean(draft.spent) === spent) {
        rows.push([draft, index]);
      }
    });
    return rows;
  }

  /**
   * Una fila de guia de autoria. Las DOS filas estan siempre -- exista o no el
   * archivo -- y lo que cambia con el estado es el enabled, nunca la presencia:
   * dos filas que arman botoneras distintas no se alinean una con la otra, que
   * es la misma regla que las filas de borrador.
   *
   * Descartar es solo de la tuya. La compartida es un archivo trackeado, asi que
   * borrarla es git rm mas un commit: una decision sobre que entra al PR, que no
   * es de este boton, y la CLI dice lo mismo negando --delete --team.
   */
  function renderGuide(model, guide, index) {
    const box = el("div", "rev guide");

    const head = el("div", "rev-head");
    head.appendChild(el("span", "rev-name", guide.label));

    const rowIcons = el("div", "rev-head-actions");
    const open = iconButton("file", "openGuide", "Open the guide", index);
    open.disabled = !guide.exists;
    open.title = guide.exists
      ? guide.path
      : "There is no guide yet";
    rowIcons.appendChild(open);
    if (guide.kind === "own") {
      const discard = iconButton("trash", "discardGuide", "Discard the guide", index);
      discard.disabled = model.busy || !guide.discardable;
      discard.title = "Delete your guide";
      rowIcons.appendChild(discard);
    }
    head.appendChild(rowIcons);
    head.appendChild(el("span", "badge", guide.badge));
    box.appendChild(head);

    // Un solo control con etiqueta: mide lo que dice y arranca a la izquierda,
    // como Continue/Discard del inventario. La grilla de dos columnas es de las
    // botoneras de DOS -- con una sola celda ocupada estiraba el boton a media
    // pantalla y le centraba el texto, que se lee como un error de alineacion.
    const actions = el("div", "rev-actions");
    const create = button("Create", "createGuide", null, null, index);
    create.disabled = model.busy || guide.exists;
    create.title = guide.exists
      ? "It already exists; open it and edit it"
      : "Create it empty, then write the conventions into it";
    actions.appendChild(create);
    box.appendChild(actions);
    return box;
  }

  /**
   * La fila del walkthrough del autor: como se llama la rama que anota, en que
   * estado esta, cuanto lleva escrito y los CUATRO controles que actuan sobre el
   * archivo -- los dos verbos incluidos.
   *
   * Init y build viven aca y no sueltos encima de la fila porque su sujeto es
   * este archivo, igual que Create es de cada guia. Sueltos, la palabra
   * "Walkthrough" se decia tres veces seguidas (el titulo de la seccion, las dos
   * etiquetas con prefijo y el nombre de la fila) sin que ninguna agregara un
   * dato; por eso van sin prefijo y la fila se llama por su rama. En el menu y
   * la paleta siguen llevando el prefijo, que es donde no hay seccion que de
   * contexto.
   *
   * El badge dice "may be out of date" y no "out of date" a proposito: lo que
   * la CLI compara en cada refresco es barato y aproximado -- si el rango se
   * movio desde que el archivo se escribio --, y la respuesta exacta es de
   * build, que es lo que corre el boton de al lado. Un badge que afirma de mas
   * sobre un archivo que puede estar perfecto es peor que uno que sugiere mirar.
   *
   * Copy for agent copia un PUNTERO al archivo, nunca la consigna: esa vive
   * adentro del propio walkthrough, en el comentario de arriba de todo, que es
   * donde se mantiene sola. Dos copias de la consigna se irian una de otra y la
   * que se pondria vieja seria justo la que el agente lee.
   */
  function renderWalkthroughRow(model, walkthrough) {
    const box = el("div", "rev guide");

    const head = el("div", "rev-head");
    head.appendChild(el("span", "rev-name", walkthrough.label));
    if (walkthrough.exists && walkthrough.total > 0) {
      head.appendChild(el("span", "muted", walkthrough.annotated + "/" + walkthrough.total));
    }

    const rowIcons = el("div", "rev-head-actions");
    const open = iconButton("file", "openWalkthrough", "Open the walkthrough", 0);
    open.disabled = !walkthrough.exists;
    open.title = walkthrough.exists
      ? walkthrough.path
      : "There is no walkthrough to open yet";
    rowIcons.appendChild(open);
    head.appendChild(rowIcons);
    // El badge cierra la linea en TODAS las filas del panel: asi los estados de
    // las tres secciones caen en la misma columna del borde derecho. Los iconos
    // van antes, pegados a el, que es lo que los mantiene al lado del dato que
    // nombra su sujeto.
    head.appendChild(el("span", "badge", walkthrough.badge));
    box.appendChild(head);

    // El mismo verbo crea y actualiza, asi que la etiqueta sigue al estado que
    // reporto la CLI. "Init" sobre un archivo lleno de prosa prometia lo que ese
    // verbo justamente ya no hace.
    // Las tres literales enteras y no una concatenacion: la copy compartida se
    // verifica contra el canonico buscando la cadena, y un texto armado en
    // pedazos es justo el que ese check no puede ver.
    const initLabel = walkthrough.actionLabel === "Create"
      ? "Init"
      : walkthrough.actionLabel === "Start over"
        ? "Start over"
        : "Update";
    const actions = el("div", "rev-actions");
    const init = button(initLabel, "walkthroughInit", null, null, 0);
    init.disabled = model.busy;
    actions.appendChild(init);
    const build = button("Build", "walkthroughBuild", null, null, 0);
    build.disabled = model.busy;
    actions.appendChild(build);
    const copy = button("Copy for agent", "copyWalkthroughPrompt", null, null, 0);
    copy.disabled = !walkthrough.exists;
    copy.title = walkthrough.exists
      ? "Copy a pointer to the file; the instructions are inside it"
      : "Create the walkthrough first, then hand it to an agent";
    actions.appendChild(copy);
    box.appendChild(actions);
    return box;
  }

  /**
   * El bloque de las dos guias, dentro de la seccion Walkthrough. No lleva
   * encabezado propio: son dos filas debajo de Init/Build y el nombre de cada
   * una ya dice cual es.
   */
  function renderGuides(model, guides) {
    const box = el("div", "inv");
    guides.forEach(function (guide, index) {
      box.appendChild(renderGuide(model, guide, index));
    });
    return box;
  }

  function renderInventory(model, reviews) {
    const box = el("div", "inv");
    box.appendChild(el("h2", null, "Reviews in this repository"));
    reviews.forEach(function (review, index) {
      box.appendChild(renderReview(model, review, index));
    });
    return box;
  }

  // El panel redibuja el root en cada modelo; sin esto, expandir Walkthrough
  // / Compare / Settings / Support se pliega al primer refresh (busy, etc.).
  let compareSectionOpen = false;
  let walkthroughSectionOpen = false;
  let spentDraftsOpen = false;
  let fixesOpen = false;
  let settingsOpen = false;
  let supportOpen = false;

  /**
   * Envuelve el cuerpo de un <details> del pie para poder animar 0fr→1fr
   * (Outline/Timeline). El scroll no es suyo: cuando lo abierto no entra, el
   * que scrollea es el pie entero.
   */
  function toolsSection(summaryLabel, openFlag, setOpen, bodyChildren) {
    const box = el("details", "tools");
    if (openFlag) { box.open = true; }
    box.addEventListener("toggle", function () {
      setOpen(box.open);
    });
    box.appendChild(el("summary", null, summaryLabel));
    const body = el("div", "tools-body");
    const inner = el("div", "tools-inner");
    bodyChildren.forEach(function (child) { inner.appendChild(child); });
    body.appendChild(inner);
    box.appendChild(body);
    return box;
  }

  /**
   * Compare, en el empty state (no-review): monta fuera de una sesion de
   * lectura. No en finish-pending. Plegada por defecto: es secundaria respecto
   * de Start / base.
   *
   * Se llamaba "Other actions" y era la primera del pie. Un titulo que no
   * nombra su contenido, encima de las dos secciones que si lo nombran
   * (Walkthrough y los ordenes de lectura terminados), y ademas la unica de las
   * tres que monta algo FUERA de la review que estas por hacer: dos revisiones
   * cualesquiera, sin review que empezar ni orden que escribir. Por eso ahora
   * dice lo que hace y va ultima de las tres.
   */
  function renderCompareSection(model) {
    const compare = button("Compare revisions", "compareReview");
    compare.disabled = model.busy;
    return toolsSection("Compare", compareSectionOpen, function (open) {
      compareSectionOpen = open;
    }, [compare]);
  }

  /**
   * Todo lo del walkthrough junto: la fila del archivo del autor -- con init,
   * build y Copy for agent colgando de ella -- y las dos guias de autoria.
   * Vivia con Compare en una seccion "Other actions" y se separo cuando las
   * guias entraron -- cuatro controles sobre el mismo sustantivo mas uno ajeno
   * no es una lista de otras acciones, es un cajon. Agrupado asi el panel dice lo mismo que la CLI,
   * donde los cuatro cuelgan del verbo walkthrough.
   */
  function renderWalkthroughSection(model, guides) {
    // Tres filas y nada suelto arriba: init y build son la botonera de la fila
    // del walkthrough (renderWalkthroughRow), no un bloque encima de ella.
    // Las tres filas en UN solo contenedor: dos .inv seguidos ponen su padding
    // uno contra el otro y la fila del walkthrough queda a una sangria distinta
    // de las dos guias, que es justo lo que estas filas existen para no hacer.
    const rows = el("div", "inv");
    if (model.walkthrough) {
      rows.appendChild(renderWalkthroughRow(model, model.walkthrough));
    }
    guides.forEach(function (guide, index) {
      rows.appendChild(renderGuide(model, guide, index));
    });
    const children = [rows];
    return toolsSection("Walkthrough", walkthroughSectionOpen, function (open) {
      walkthroughSectionOpen = open;
    }, children);
  }

  /**
   * Links externos de apoyo al proyecto. El webview manda un id del conjunto
   * cerrado y el host abre la URL allowlisteada con openExternal. Hoy: star
   * (repo) y bug (issue form). Sumar linkedin / donate / rate es un par de
   * filas acá + el allowlist del host.
   */
  function supportButton(label, id) {
    const node = el("button", null);
    node.appendChild(el("span", null, label));
    node.addEventListener("click", function () {
      if (stale()) { return; }
      vscode.postMessage({type: "openSupport", id: id});
    });
    return node;
  }

  function renderSupport() {
    const row = el("div", "row");
    row.appendChild(supportButton("Star on GitHub", "star"));
    row.appendChild(supportButton("Report a bug", "bug"));
    return toolsSection("Support", supportOpen, function (open) {
      supportOpen = open;
    }, [row]);
  }

  /**
   * Modo setup: config llegó sin base. Solo base (obligatoria) y remote
   * (opcional con valor efectivo). Sin Start, inventario ni footer.
   * El párrafo de la base no es un "is required" vacío: dice para qué
   * sirve (dónde aterrizan los PRs y contra qué se arma el rango).
   */
  function renderSetup(model) {
    const box = empty(
      "Which branch do pull requests land on in this repo?",
      button("Choose the branch", "setBase", "primary")
    );
    box.appendChild(el("p", null,
      "Reviews compare the branch you are reading against it. Usually main or develop."));
    const remote = model.configuredRemote !== undefined ? model.configuredRemote : "origin";
    box.appendChild(el("p", null, "Remote: " + remote + " (optional)."));
    const changeRemote = button("Change remote", "setRemote", null);
    changeRemote.disabled = model.busy;
    box.appendChild(changeRemote);
    return box;
  }

  /**
   * Start del empty no-review ya configurado (base en Settings del pie).
   */
  function renderEmptyStartBlock(model) {
    return empty("No active review on this branch.", button("Start a review", "startReview", "primary"));
  }

  /**
   * Los borradores cuya review ya terminó, plegados al fondo. Siguen
   * existiendo —descartarlos es una decisión aparte, la del verbo forget—
   * pero no son trabajo pendiente, y arriba ocupaban el mismo lugar y el
   * mismo peso que un orden a medio escribir.
   *
   * Plegada, no escondida: un archivo que existe y ninguna superficie nombra
   * es justo el estado que este panel no deja pasar en ningún otro lado. Acá
   * están sus dos controles de siempre, que son los que quedan con sentido.
   */
  function renderSpentDrafts(model) {
    const rows = draftRows(model, true);
    if (rows.length === 0) {
      return null;
    }
    return toolsSection("Reading orders you finished with", spentDraftsOpen, function (open) {
      spentDraftsOpen = open;
    }, [
      el("p", null, "Their review is over; the files are still here"),
      renderDrafts(model, rows, null),
    ]);
  }

  /**
   * Las ramas de ediciones que dejo un finish, plegadas al fondo del pie.
   *
   * Es el ultimo estado del repositorio que ninguna superficie nombraba: list
   * no las enumeraba, el inventario sale de list, y el unico Clean del panel
   * vive en el banner de finish-pending. Una rama por review terminada, para
   * siempre, y sin forma de ver cuales hay ni de tirar una sin escribir su
   * nombre en una terminal.
   *
   * "Discard all" corre clean --fixes-only SIN rama: por diseño de clean eso
   * nunca toca review/* (sesiones vivas de otras ramas), a diferencia de un
   * git review clean a secas -- así que no tiene el problema de alcance que
   * bloqueaba este botón. Sigue habiendo confirmación con el detalle completo,
   * porque lo que hay acá es trabajo escrito a mano y no basura de máquina.
   */
  function renderFixesSection(model) {
    if (!model.fixes || model.fixes.length === 0) {
      return null;
    }
    const discardAll = button("Discard all", "discardAllFixes");
    discardAll.disabled = model.busy;
    return toolsSection("Edits you extracted", fixesOpen, function (open) {
      fixesOpen = open;
    }, [
      el("p", null, "One branch per finish; commit and push them from Source Control, or drop them here"),
      discardAll,
      renderFixesRows(model),
    ]);
  }

  function renderFixesRows(model) {
    const box = el("div", "inv");
    model.fixes.forEach(function (fixes, index) {
      box.appendChild(renderFixesRow(model, fixes, index));
    });
    return box;
  }

  /**
   * Una fila: la rama, su badge de estado y el unico control que tiene sentido
   * desde aca. Commitear y pushear son de Source Control, que es adonde el
   * finish ya manda.
   *
   * El badge dice cuanto cuesta tirarla, que es la unica pregunta de esta
   * seccion. Los cuatro estados salen de la CLI y no se pliegan entre si:
   * "empty" no es una variante de "seguro" (una rama intacta esta parada en
   * la punta del PR y no contiene NADA tuyo, que es distinto de estar
   * integrada), y "unknown" no es una variante de "unmerged" (sin base
   * configurada la pregunta no tiene respuesta, y contestar la peor de las
   * dos pinta de peligrosa una rama que puede estar vacia).
   */
  function renderFixesRow(model, fixes, index) {
    const box = el("div", "rev guide");

    const head = el("div", "rev-head");
    head.appendChild(el("span", "rev-name", fixes.name));

    const rowIcons = el("div", "rev-head-actions");
    const discard = iconButton("trash", "discardFixes", "Discard the extracted edits", index);
    // La fila en la que estas parado se dibuja igual y sin control: la CLI la
    // saltea con "skipping (currently checked out)", asi que ofrecer el boton
    // seria prometer algo que no va a pasar. Esconder la fila entera seria
    // peor: es una rama que existe y ninguna otra superficie nombra.
    discard.disabled = model.busy || fixes.current;
    discard.title = fixes.current
      ? "You are on this branch; switch away first"
      : "Delete this branch of edits";
    rowIcons.appendChild(discard);
    head.appendChild(rowIcons);
    head.appendChild(el("span", "badge", fixesBadge(fixes.state)));
    box.appendChild(head);
    return box;
  }

  function fixesBadge(state) {
    if (state === "empty") { return "empty"; }
    if (state === "merged") { return "merged"; }
    if (state === "unmerged") { return "unmerged"; }
    return "unknown";
  }

  /**
   * Base y remote del repo, plegados. Solo con base ya configurada (el setup
   * los muestra inline). Debajo de Compare, encima de Support.
   */
  function renderSettings(model) {
    const kids = [];
    if (model.configuredBase !== undefined) {
      kids.push(el("p", null, "Base: " + model.configuredBase + "."));
      const changeBase = button("Change the base branch", "setBase", null);
      changeBase.disabled = model.busy;
      kids.push(changeBase);
    }
    if (model.configuredRemote !== undefined) {
      kids.push(el("p", null, "Remote: " + model.configuredRemote + "."));
      const changeRemote = button("Change remote", "setRemote", null);
      changeRemote.disabled = model.busy;
      kids.push(changeRemote);
    }
    return toolsSection("Settings", settingsOpen, function (open) {
      settingsOpen = open;
    }, kids);
  }

  /**
   * Pie fijo: Walkthrough + los ordenes terminados + las ramas de ediciones +
   * Compare + Settings + Support (split Outline/Timeline). Las dos primeras son
   * de la review que estas por hacer -- el orden que escribis y los que ya
   * leiste --, asi que van arriba; las ediciones extraidas son restos de las que
   * ya pasaron y van detras; Compare monta algo aparte y queda debajo de todas.
   * Settings y Support al fondo, como estaban.
   */
  function renderPaneFooter(model) {
    const footer = el("div", "pane-footer");
    footer.appendChild(renderWalkthroughSection(model, model.guides || []));
    const spent = renderSpentDrafts(model);
    if (spent) {
      footer.appendChild(spent);
    }
    const fixes = renderFixesSection(model);
    if (fixes) {
      footer.appendChild(fixes);
    }
    footer.appendChild(renderCompareSection(model));
    footer.appendChild(renderSettings(model));
    footer.appendChild(renderSupport());
    return footer;
  }

  function renderEmptyState(model) {
    switch (model.situation) {
      case "no-review": {
        // Setup gate: sin base solo se dibuja la configuración.
        if (model.noBaseConfigured) {
          return renderSetup(model);
        }
        // El fallback a lista vacía no sobra: el webview redibuja el modelo que
        // guardó con setState, que puede venir de una versión sin este campo.
        // pane-main = body scrolleable + footer anclado (fills lo pone render).
        const reviews = model.reviews || [];
        // Sólo los que todavía tienen una review por delante. Los gastados
        // bajan a su propia sección del pie (renderSpentDrafts).
        const drafts = draftRows(model, false);
        const body = el("div", "pane-body");
        // Los borradores empezados van primero y el cuerpo de siempre sigue
        // entero debajo: un orden de lectura a medio escribir es lo que el
        // revisor dejó abierto, pero no reemplaza el inventario ni Start.
        if (drafts.length > 0) {
          body.appendChild(renderDrafts(model, drafts, "Reading orders you started"));
        }
        if (reviews.length > 0) {
          body.appendChild(renderInventory(model, reviews));
        }
        const start = renderEmptyStartBlock(model);
        if (drafts.length > 0 || reviews.length > 0) {
          start.className = "empty after-inv";
        }
        body.appendChild(start);
        const wrap = el("div", "pane-main");
        wrap.appendChild(body);
        wrap.appendChild(renderPaneFooter(model));
        return wrap;
      }
      // Cierre completo con undo vivo (contracts/finish-state.md): el finish
      // ya entregó las edits; esto no es empty state. Flujo: commit en SCM,
      // finish --abort, o clean del leftover (el delta no se toca).
      case "finish-pending": {
        const pending = model.pendingFinish;
        let source = "this branch";
        let destination = "review-fixes/...";
        if (pending) {
          source = pending.branch.indexOf("review/") === 0 ? pending.branch.slice(7) : pending.branch;
          destination = pending.onto ? source : "review-fixes/" + source;
        }
        const notice = el("div", "note finish-banner");
        notice.appendChild(el("p", null,
          "Your edits are on " + destination + ", staged and ready to commit."));
        notice.appendChild(el("p", null,
          "Commit and push them from Source Control. Until you clean up, this is still undoable."));
        const actions = el("div", "row");
        const clean = button("Done, clean up", "cleanReview", "primary");
        clean.disabled = model.busy;
        clean.title = "Delete the review branch; keep your edits";
        const undo = button("Undo", "undoFinish", null);
        undo.disabled = model.busy;
        undo.title = "Put the edits back and keep reviewing";
        actions.appendChild(clean);
        actions.appendChild(undo);
        notice.appendChild(actions);
        return notice;
      }
      case "out-of-range":
        return empty(
          "The cursor is out of range: the base moved.",
          button("How to fix it", "outOfRangeHelp", "primary"),
          model.stderr
        );
      case "cli-missing":
        return emptyCli(
          "The git-review CLI (${MIN_CLI_VERSION} or newer) was not found.",
          "install",
          model.stderr
        );
      case "cli-outdated":
        return emptyCli(
          "The installed git-review CLI is older than ${MIN_CLI_VERSION}.",
          "update",
          model.stderr
        );
      case "error":
        // Same pattern as out-of-range: the CLI stderr already names the fix
        // (abort / branch -D / forget --saved); re-show it on demand (FR-024).
        return empty(
          "Something went wrong reading the review state.",
          button("How to fix it", "outOfRangeHelp", "primary"),
          model.stderr
        );
      default:
        return empty("Something went wrong reading the review state.", null, model.stderr);
    }
  }

  /**
   * El modo y la rama no cambian al navegar, así que la barra es el único
   * chrome que sobrevive a la carga entera y le da al panel un punto fijo. La
   * posición sí cambia: cargando se dibuja como bloque, porque mostrar la
   * anterior sería afirmar un número que ya no vale.
   */
  function renderBar(model, loading) {
    const bar = el("div", "bar");
    bar.appendChild(el("span", "mode", model.mode));
    // El orden de lectura es el borrador del revisor, no el walkthrough del PR
    // (011). Sale del registro de presencia y de ningún otro lado; es texto en
    // un bloque que ya existe, no un control ni un bloque nuevo.
    if (model.draft) { bar.appendChild(el("span", "draft", "(draft)")); }
    // El ORIGEN en lugar de la rama, no además de ella (research.md Decisión 5):
    // la rama es siempre "review/<origen>", así que mostrar las dos es gastar dos
    // veces el recurso más escaso del panel en el mismo dato. El origen es
    // además el nombre que el revisor reconoce —es el PR— y el que la CLI pone
    // primero en su salida humana. Con una CLI que no lo reporte, la rama.
    const name = model.source !== undefined ? model.source : model.branch;
    bar.appendChild(el("span", "branch", model.repoLabel ? name + " · " + model.repoLabel : name));
    // Abreviado, como lo imprime la terminal: el contrato lo emite completo y
    // recortar para mostrar es presentación, no derivar estado.
    if (model.tip !== undefined) { bar.appendChild(el("span", "tip", model.tip.slice(0, 7))); }
    if (loading) {
      bar.appendChild(el("span", "pos sk sk-pos"));
    } else if (model.position !== undefined && model.total !== undefined) {
      bar.appendChild(el("span", "pos", model.position + "/" + model.total));
    }
    // La barra es solo identidad (modo, origen, tip, posición). El ciclo de
    // vida de la review — Finish, Save, Cancel, Refresh — vive en view/title
    // como iconos del chrome del panel, no acá: duplicarlos en el webview
    // gastaba el ancho del sidebar y partía el trio (Finish solo arriba).
    return bar;
  }

  /** El bloque del *why* mientras se lo espera: la misma gramática visual que
   *  el esqueleto de la entrada, para que la carga sea una sola cosa y no dos. */
  function whyLoading() {
    const box = el("div", "why");
    box.setAttribute("aria-busy", "true");
    box.appendChild(el("span", "sr-only", "Loading the why…"));
    box.appendChild(el("div", "sk"));
    box.appendChild(el("div", "sk"));
    box.appendChild(el("div", "sk"));
    return box;
  }

  // Una entrada no anotada nunca tiene un why que pedir (la CLI ya cae en
  // "entrada sin cuerpo"), pero el texto no es el mismo que el de una entrada
  // guiada sin explicación: una es una ausencia del walkthrough, la otra un
  // archivo que el walkthrough directamente no cubre.
  function renderWhy(why, annotated) {
    if (why.state === "present") { return el("div", "why", why.text); }
    if (why.state === "absent") {
      const text = annotated === false
        ? "This file changes in the review and the walkthrough does not annotate it."
        : "This entry has no explanation.";
      return el("div", "why quiet", text);
    }
    if (why.state === "failed") { return el("div", "why quiet", "Could not read the why for this entry."); }
    return whyLoading();
  }

  function pad(n) { return n < 10 ? "0" + n : String(n); }

  function renderEntry(model) {
    const body = el("div", "body");
    const head = el("div", "head");
    head.appendChild(el("span", "n", pad(model.current.position)));
    // En step el elemento grande pasa a ser el ASUNTO, y el SHA baja al head
    // junto al autor (research.md Decisión 4): el equivalente humano de un
    // commit es su asunto, igual que en walk lo es el path. El SHA no
    // desaparece — es lo que se pega en una terminal.
    // Sin asunto (una CLI anterior a esta feature) nada de esto ocurre y el
    // head queda exactamente como estaba: degradar es dibujar el panel de ayer,
    // no dejar un hueco (FR-003).
    const named = model.mode === "step" && model.current.subject !== undefined;
    if (named) {
      head.appendChild(el("span", "sha", model.current.display));
      if (model.current.author !== undefined) {
        head.appendChild(el("span", "who", model.current.author));
      }
    }
    // "key" es el marcador del propio walkthrough (la línea "> key"), no una
    // etiqueta inventada acá; "edits" sí necesita el título, porque abreviado
    // no dice cuáles son esas ediciones; "not covered" sólo aplica en walk — en
    // step "annotated" no significa nada y siempre vale true.
    if (model.current.essential) {
      head.appendChild(el("span", "badge key", "key"));
    } else if (model.mode === "walk" && !model.current.annotated) {
      head.appendChild(el("span", "badge uncovered", "not covered"));
    } else if (model.current.banked) {
      const banked = el("span", "badge", "edits");
      banked.title = "This entry has banked edits";
      head.appendChild(banked);
    }
    body.appendChild(head);

    // Un asunto vacío es un valor legítimo (un commit cuyo mensaje no tiene
    // primera línea), y se muestra como la ausencia que es — distinto de una
    // CLI que no reporta asuntos, que cae en la rama de arriba.
    if (named && model.current.subject.length === 0) {
      body.appendChild(el("p", "id quiet", "This commit has no subject."));
    } else {
      body.appendChild(el("p", "id", named ? model.current.subject : model.current.display));
    }

    if (model.why) {
      body.appendChild(renderWhy(model.why, model.mode === "walk" ? model.current.annotated : undefined));
      // El texto de acá arriba ya es el *why* entero: lo que abre el editor es
      // el mismo contenido renderizado como Markdown y a ancho de editor, así
      // que sólo se ofrece si hay algo que renderizar. Es un link y no un
      // botón porque abre otra superficie, no actúa sobre ésta.
      if (model.why.state === "present") {
        const more = el("div", "more");
        more.appendChild(button("open in editor", "showWhy", "link"));
        body.appendChild(more);
      }
    }

    body.appendChild(renderOpenRow(model));
    // Step: debajo del Diff del commit, la lista de archivos de ese commit
    // (misma UX de filas que whole). Vive dentro del body de la entrada porque
    // el cursor de commits sigue siendo el de arriba (prev/next).
    if (model.mode === "step") {
      body.appendChild(renderFiles(model));
    }
    // FR-027: un cierre trabado retira los controles de navegación del todo —
    // no basta con deshabilitarlos, porque eso deja ver una secuencia que ya
    // no corresponde recorrer. El banner de más arriba es la salida ofrecida
    // en su lugar (renderFinishConflictBanner).
    if (!model.navigationLocked) { body.appendChild(renderNavRow(model)); }
    return body;
  }

  /**
   * El cuerpo mientras se carga: la misma silueta que renderEntry —número,
   * path, why y las dos filas de controles— con el contenido en bloques. Los
   * botones son los reales y se dibujan deshabilitados: dejarlos afuera haría
   * saltar el alto del panel justo cuando termina la espera.
   */
  function renderPending(model) {
    const body = el("div", "body");
    body.setAttribute("role", "status");
    body.setAttribute("aria-busy", "true");
    body.appendChild(el("span", "sr-only", "Loading the entry…"));

    const head = el("div", "head");
    head.appendChild(el("span", "sk sk-num"));
    body.appendChild(head);
    body.appendChild(el("p", "id sk"));

    // El modo step no tiene explicaciones: su esqueleto tampoco.
    if (model.mode === "walk") { body.appendChild(whyLoading()); }

    body.appendChild(renderOpenRow(model));
    // Misma silueta que renderEntry en step: hueco del listado de archivos.
    if (model.mode === "step") {
      body.appendChild(renderFiles(model));
    }
    if (!model.navigationLocked) { body.appendChild(renderNavRow(model)); }
    return freeze(body);
  }

  /**
   * El banner de finish-conflict (contracts/finish-state.md): explica el
   * cierre trabado y ofrece deshacerlo o continuarlo — en vez de los
   * controles de navegación que renderEntry/renderPending retiran arriba.
   * undoFinish / resumeFinish / cleanReview viven en PANEL_MESSAGES y rutean
   * a gitReview.undoFinish / resumeFinish / cleanReview.
   */
  function renderFinishConflictBanner() {
    const box = el("div", "note finish-banner");
    box.appendChild(el("p", null,
      "This finish stopped at a conflict. Resolve the markers, then continue — or undo it to go back to editing."));
    const row = el("div", "row");
    row.appendChild(button("Undo", "undoFinish", null));
    row.appendChild(button("Continue", "resumeFinish", null));
    box.appendChild(row);
    return box;
  }

  /** Nada de lo dibujado durante la carga puede accionarse; ver stale(). */
  function freeze(node) {
    node.querySelectorAll("button").forEach(function (b) { b.disabled = true; });
    return node;
  }

  // En step la entrada es un commit: no hay "el archivo" que abrir, sólo sus
  // cambios. En walk son dos destinos distintos y el ícono es lo que los separa
  // de un vistazo — la palabra sola ("File"/"Diff") se lee igual pero se
  // distingue más lento en una columna angosta.
  function renderOpenRow(model) {
    const open = el("div", "row");
    if (model.mode === "step") {
      open.appendChild(button("Diff", "openChange", null, "diff"));
    } else {
      open.appendChild(button("File", "openEntry", null, "file"));
      open.appendChild(button("Diff", "openChange", null, "diff"));
    }
    return open;
  }

  // En un extremo de la secuencia el control no puede mover nada: se deshabilita
  // en vez de dejar un clic mudo. Quien decide si el cursor se mueve sigue
  // siendo la CLI — esto sólo refleja la position/total que ella ya reportó, la
  // misma que dibuja la barra de arriba.
  function renderNavRow(model) {
    const nav = el("div", "row");
    const prev = iconButton("prev", "prev", "Previous entry");
    const next = iconButton("next", "next", "Next entry");
    prev.disabled = model.busy || model.atFirst;
    next.disabled = model.busy || model.atLast;
    nav.appendChild(prev);
    nav.appendChild(next);
    return nav;
  }

  /**
   * Inventario de archivos seleccionables:
   * - whole (FR-010): paths del rango; Diff arriba abre todo el rango
   *   (openAllChanges); cada fila abre un path.
   * - step: paths del commit actual (registros file del porcelain); el Diff
   *   del commit vive en renderOpenRow (openChange sin indice); cada fila
   *   abre un path de ese commit. Sin openAllChanges aca para no duplicar
   *   el Diff del commit.
   * Sin cursor en la lista. Vacio se dice explicitamente (FR-007).
   */
  function renderFiles(model) {
    const step = model.mode === "step";
    if (model.files.length === 0) {
      return empty(step
        ? "This commit changes no files."
        : "This review's range does not touch any files.");
    }
    const box = el("div", "files");
    const n = model.files.length;
    const unit = step ? " in this commit" : " in this review";
    box.appendChild(el("h2", null, n + (n === 1 ? " file" : " files") + unit));

    if (!step) {
      const all = el("div", "row");
      const allButton = button("Diff", "openAllChanges", null, "diff");
      allButton.title = "Open every change in this review at once";
      all.appendChild(allButton);
      box.appendChild(all);
    }

    model.files.forEach(function (file) {
      const row = button(file.display, "openChange", "file-row", "diff", file.position);
      // Por dónde iba el revisor. El dato lo guarda el host —sobrevive a cerrar
      // el editor—, pero acá es una marca más: sale del modelo como todo lo
      // demás, y el panel no la recuerda por su cuenta (FR-019).
      if (file.display === model.lastOpened) {
        row.className = "file-row opened";
        row.setAttribute("aria-current", "true");
        row.title = "Last opened";
      }
      box.appendChild(row);
    });
    return box;
  }

  // Las notas van tanto en el dibujo normal como en el de carga: describen el
  // review, no la entrada, así que no cambian al navegar. Sacarlas mientras
  // carga haría saltar el panel dos veces por cada paso.
  function renderNotes(model) {
    if (model.readonly) {
      root.appendChild(note("Read-only compare: finish is not available. Use Cancel when done."));
    }
    if (model.keysOnly) {
      root.appendChild(note("Keys-only: reading order is restricted to walkthrough entries marked key."));
    }
    if (model.baseMoved) { root.appendChild(note("The base moved: fewer entries remain in range than when the review started.")); }
    if (model.degraded) {
      root.appendChild(note("The walkthrough does not cover the review's current range; showing the full range diff."));
    }
    // Sólo llega en whole, que es donde reemplaza a la secuencia como respuesta
    // a "¿contra qué estoy comparando?". Sin base registrada no se dibuja nada
    // en su lugar: ni un hueco, ni un vacío, ni un error (FR-009).
    if (model.base !== undefined) { root.appendChild(note("Range built against " + model.base + ".")); }
  }

  function render(model) {
    root.textContent = "";
    // fills solo en no-review configurado: body scrollea y el footer
    // (Walkthrough / Compare / Settings / Support) queda anclado abajo. Setup
    // (sin base) y el resto de situaciones no estiran en flex.
    root.className = model.situation === "no-review" && !model.noBaseConfigured ? "fills" : "";
    // finish-conflict sigue siendo una review legible (FR-027) — el estado
    // vacío es sólo para no-review/out-of-range/error/cli-*.
    if (model.situation !== "review" && model.situation !== "finish-conflict") {
      root.appendChild(renderEmptyState(model));
      return;
    }

    root.appendChild(renderBar(model, false));
    if (model.situation === "finish-conflict") { root.appendChild(renderFinishConflictBanner()); }
    renderNotes(model);

    if (model.mode === "whole") {
      root.appendChild(renderFiles(model));
    } else if (model.current) {
      root.appendChild(renderEntry(model));
    } else {
      root.appendChild(empty("The cursor does not point at any entry in the sequence."));
    }
  }

  /*
   * Navegar es UNA espera para el revisor, pero llega en dos tiempos: primero
   * el verbo más el status --porcelain (busy), y después el --why de la
   * entrada nueva. Dibujar los modelos intermedios dejaba la entrada anterior
   * en pantalla con sus botones apuntando a ella, y encima un segundo estado de
   * carga adentro del why. Mientras dure cualquiera de las dos fases se dibuja
   * el mismo esqueleto, y recién al final aparece la entrada entera.
   *
   * Los tiempos de acá abajo no son estado del review (FR-019): el modelo sigue
   * siendo lo único que decide QUÉ se muestra. Sólo deciden CUÁNDO se cambia de
   * dibujo, que es presentación pura y no se puede resolver del lado del host —
   * es este contexto el que sabe qué hay en pantalla.
   */
  const SKELETON_DELAY_MS = 120;  // por debajo de esto la espera no se percibe:
                                  // mostrar el esqueleto sería un parpadeo peor
  const WHY_WAIT_MS = 800;        // techo: un why lento no retiene la entrada
  const SKELETON = {};            // marca de "lo dibujado es el esqueleto"

  let model;            // el último modelo recibido
  let painted;          // lo que está en pantalla: un modelo, SKELETON, o nada
  let pendingSince = 0;
  let showTimer = 0;
  let capTimer = 0;

  /** Lo dibujado ya no corresponde al modelo vigente: los controles no valen. */
  function stale() { return painted !== model; }

  function pending(m) {
    if (m.situation !== "review" || (m.mode !== "walk" && m.mode !== "step")) { return false; }
    return m.busy === true || (m.why !== undefined && m.why.state === "loading");
  }

  function paint() {
    if (showTimer) { clearTimeout(showTimer); showTimer = 0; }
    if (capTimer) { clearTimeout(capTimer); capTimer = 0; }
    painted = model;
    render(model);
  }

  /*
   * Antes del primer modelo el panel no sabe nada, y decirlo es distinto de
   * quedarse en blanco: la vista se resuelve apenas se abre, el primer
   * git review --version + status --porcelain tarda lo que tarda un par de
   * procesos, y el hueco se ve sobre todo mientras el host arranca. Misma frase
   * que los otros dos paneles ("Reading the review state…").
   */
  const WAITING_TEXT = "Reading the review state…";

  /*
   * Las tres situaciones que NO se repintan de memoria al reconstruirse el
   * webview: son respuestas sobre el entorno —la CLI no está, es vieja, algo
   * falló— y volver a dibujarlas antes de que nadie haya vuelto a mirar es
   * exactamente el cartel que aparecía "mientras carga". El resto sí se
   * repinta: evita el parpadeo y no afirma nada del entorno.
   */
  const UNVERIFIED = ["cli-missing", "cli-outdated", "error"];

  function paintWaiting() {
    // painted queda en undefined a propósito: no hay ningún control dibujado
    // que un clic pueda tomar por vigente, y el primer modelo que llegue tiene
    // que poder entrar directo al esqueleto sin esperar el delay antiparpadeo.
    painted = undefined;
    root.textContent = "";
    root.className = "";
    const box = el("div", "empty");
    box.setAttribute("role", "status");
    box.setAttribute("aria-busy", "true");
    box.appendChild(el("p", "waiting", WAITING_TEXT));
    root.appendChild(box);
  }

  function paintSkeleton() {
    showTimer = 0;
    painted = SKELETON;
    root.textContent = "";
    root.className = "";
    root.appendChild(renderBar(model, true));
    renderNotes(model);
    root.appendChild(renderPending(model));
  }

  function receive(next) {
    model = next;
    if (!pending(next)) { paint(); return; }

    if (painted === SKELETON) {
      // Ya en carga: lo único que puede cambiar es que el verbo haya vuelto y
      // sólo falte el why. Pasado el techo se muestra la entrada —que ya es la
      // correcta— con el why todavía cargando adentro.
      if (!next.busy && Date.now() - pendingSince >= WHY_WAIT_MS) { paint(); }
      return;
    }
    if (showTimer) { return; }  // la fase ya arrancó; el esqueleto va en camino

    pendingSince = Date.now();
    if (painted === undefined) {
      // Nada dibujado todavía (el webview se acaba de reconstruir): no hay
      // parpadeo que evitar, y esperar dejaría el panel en blanco.
      paintSkeleton();
    } else {
      showTimer = setTimeout(paintSkeleton, SKELETON_DELAY_MS);
    }
    capTimer = setTimeout(function () {
      capTimer = 0;
      if (painted === SKELETON && !model.busy && pending(model)) { paint(); }
    }, WHY_WAIT_MS);
  }

  window.addEventListener("message", function (event) {
    if (event.data && event.data.type === "model") {
      // El modelo se guarda en el estado del webview: no es estado propio del
      // panel (FR-019), es la última copia de lo que mandó el host, para poder
      // redibujarla al recargarse sin una ida y vuelta.
      vscode.setState(event.data.model);
      receive(event.data.model);
    }
  });

  // Ocultar la vista destruye este contexto y volver a mostrarla lo reconstruye
  // de cero. Sin esto el panel arranca vacío hasta que llegue el primer modelo;
  // con el estado guardado se dibuja ya, y el modelo que sigue lo pisa.
  const saved = vscode.getState();
  if (saved && UNVERIFIED.indexOf(saved.situation) === -1) { receive(saved); } else { paintWaiting(); }

  // El host no puede postear el modelo hasta acá: un mensaje que llegue antes
  // de que exista el listener de arriba se pierde, y el panel se queda en
  // blanco sin ningún control para salir de ahí — sus botones son justamente
  // los que no se dibujaron. El handshake lo vuelve independiente del timing.
  vscode.postMessage({type: "ready"});
}());
</script>
</body>
</html>`;
}
