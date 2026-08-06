/**
 * El HTML del panel, aparte del provider y sin dependencia de `vscode`: es lo
 * que permite abrirlo en un navegador con un `PanelModel` de ejemplo y
 * verificar el render, que ninguna de las dos suites puede afirmar (un webview
 * corre en su propio contexto — research.md Decisión 11).
 *
 * Todo el color sale de variables `--vscode-*` (incluidos los temas de alto
 * contraste, FR-031); los controles son `<button>` reales para que el orden de
 * tab y el foco sean los del host. El único script es inline y va con `nonce`;
 * el contenido variable se inserta con `textContent`, nunca con `innerHTML`
 * (research.md Decisión 4).
 *
 * **El texto visible va en inglés**, igual que el de la CLI: el panel muestra
 * su stderr al lado del propio, y el `--porcelain` del que sale todo esto habla
 * en inglés. Donde el ícono alcanza (navegar) no hay palabra; donde desambigua
 * (archivo vs diff) acompaña a una. Un botón sin texto lleva `aria-label`: el
 * ícono saca la palabra de la vista, no del árbol de accesibilidad.
 */
export function panelHtml(nonce: string): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}';">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style nonce="${nonce}">
  /* 100% del webview: el empty state de no-review usa flex para clavar
     Other actions al borde inferior cuando está colapsado (no solo debajo
     del contenido, que en un sidebar alto deja un hueco vacío abajo). */
  html, body { height: 100%; }
  body {
    margin: 0;
    padding: 0;
    color: var(--vscode-foreground);
    font-family: var(--vscode-font-family);
    font-size: var(--vscode-font-size);
  }
  #root { min-height: 100%; box-sizing: border-box; }
  #root.fills {
    display: flex;
    flex-direction: column;
    min-height: 100%;
  }
  /* Inventario + Start: el bloque Start crece y empuja Other actions al fondo. */
  .pane-main {
    flex: 1 1 auto;
    display: flex;
    flex-direction: column;
    min-height: 100%;
  }
  #root.fills > .empty,
  .pane-main > .empty {
    flex: 1 1 auto;
    display: flex;
    flex-direction: column;
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
  /* "uncovered" no es un estado del revisor ni del autor del walkthrough: es
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
     todo el sidebar). "Discard orphan" es el más largo; el tope deja aire
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
  /* Acciones del empty state que no son "empezar un PR": compare (review
     de solo lectura) y autoría del walkthrough. No aparecen con review
     activa — ambos verbos necesitan un working tree sin review montada.
     Colapsadas: margin-top:auto las clava al borde inferior del panel
     (el empty crece con #root.fills / .pane-main), sin divider.
     Abiertas: vuelven al flujo bajo Start/base, con el separador de sección. */
  .tools {
    flex-shrink: 0;
    margin-top: auto;
  }
  .tools[open] {
    margin-top: 1.2em;
    padding-top: 1.2em;
    border-top: 1px solid var(--vscode-panel-border);
  }
  .tools summary {
    cursor: pointer;
    font-size: .9em;
    font-weight: 600;
    color: var(--vscode-descriptionForeground);
    list-style: none;
  }
  .tools summary::-webkit-details-marker { display: none; }
  /* Chevron al estilo de las secciones del sidebar: el triángulo nativo
     varía por motor y en webviews a veces se ve tosco; éste usa el color
     del summary y gira al abrir. */
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
  .tools[open] summary {
    margin-bottom: .6em;
  }
  .tools[open] summary::before {
    transform: rotate(45deg);
    vertical-align: .25em;
  }
  @media (prefers-reduced-motion: no-preference) {
    .tools summary::before { transition: transform .12s ease; }
  }
  .tools > button {
    display: flex;
    width: 100%;
    margin-bottom: .45em;
  }
  .tools .row { margin-bottom: 0; }
  .tools .row button { margin-bottom: 0; }
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
    left: ["M10 3.4 5.4 8 10 12.6"],
    right: ["M6 3.4 10.6 8 6 12.6"],
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
  function iconButton(iconName, message, label) {
    const node = button(null, message, null, iconName);
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

  function docsLink(label) {
    const a = document.createElement("a");
    a.href = "https://github.com/EzeVillo/git-review-workflow#readme";
    a.textContent = label;
    return a;
  }

  /** El modo y, en step/walk, la posición REGISTRADA — el inventario no la
   *  re-deriva (contracts/list-porcelain.md), a diferencia de la barra. */
  function reviewMeta(review) {
    if (review.orphan) {
      return "no metadata";
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
    if (review.orphan) { head.appendChild(el("span", "badge", "orphan")); }

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
            ? "This branch has no review metadata — use Discard"
            : "A review of this branch is already active";
        }
        actions.appendChild(go);
      }
      const discard = button(review.orphan ? "Discard orphan" : "Discard", "discardInventory", null, null, index);
      discard.disabled = model.busy;
      discard.title = review.saved
        ? "git review forget --saved (with confirmation)"
        : "git review clean (with confirmation)";
      actions.appendChild(discard);
      box.appendChild(actions);
    }
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

  // El panel redibuja el root en cada modelo; sin esto, expandir Other
  // actions se pliega al primer refresh (busy, inventario, etc.).
  let otherActionsOpen = false;

  /**
   * Compare y walkthrough init/build en el empty state (no-review): montan
   * o escriben fuera de una sesion de lectura. No en finish-pending.
   * Van plegadas por defecto: son secundarias respecto de Start / base.
   */
  function renderOtherActions(model) {
    const box = el("details", "tools");
    if (otherActionsOpen) { box.open = true; }
    box.addEventListener("toggle", function () {
      otherActionsOpen = box.open;
    });
    box.appendChild(el("summary", null, "Other actions"));
    const compare = button("Compare revisions", "compareReview");
    compare.disabled = model.busy;
    box.appendChild(compare);
    const walk = el("div", "row");
    const init = button("Walkthrough: Init", "walkthroughInit");
    const build = button("Walkthrough: Build", "walkthroughBuild");
    init.disabled = model.busy;
    build.disabled = model.busy;
    walk.appendChild(init);
    walk.appendChild(build);
    box.appendChild(walk);
    return box;
  }

  /**
   * Empty state de no-review: Start, base, Other actions.
   */
  function renderEmptyStartBlock(model) {
    const box = empty("No active review on this branch.", button("Start a review", "startReview", "primary"));
    if (model.configuredBase !== undefined) {
      box.appendChild(el("p", null, "Compares against " + model.configuredBase + "."));
      box.appendChild(button("Change the base branch", "setBase", null));
    } else if (model.noBaseConfigured) {
      box.appendChild(el("p", null, "No base branch is configured for a full review."));
      box.appendChild(button("Set the base branch", "setBase", null));
    }
    box.appendChild(renderOtherActions(model));
    return box;
  }

  function renderEmptyState(model) {
    switch (model.situation) {
      case "no-review": {
        // El fallback a lista vacía no sobra: el webview redibuja el modelo que
        // guardó con setState, que puede venir de una versión sin este campo.
        // #root.fills (lo pone render) hace que el empty crezca a la altura del
        // panel y Other actions colapsado se clave al fondo con margin-top:auto.
        const reviews = model.reviews || [];
        const box = renderEmptyStartBlock(model);
        if (reviews.length === 0) { return box; }
        // Con reviews abiertas el párrafo pasa a ser el pie del inventario, no
        // el contenido: lleva el separador y va debajo. .pane-main reparte el
        // alto: inventario arriba, Start+Other actions crecen al resto.
        box.className = "empty after-inv";
        const wrap = el("div", "pane-main");
        wrap.appendChild(renderInventory(model, reviews));
        wrap.appendChild(box);
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
          "Finished. Your edits are staged on " + destination + "."));
        notice.appendChild(el("p", null,
          "Commit them from Source Control. The review branch is kept so you can undo with git review finish --abort, or clean --keep-fixes when you no longer need the undo."));
        const actions = el("div", "row");
        const clean = button("Clean", "cleanReview", "primary");
        clean.disabled = model.busy;
        clean.title = pending
          ? "git review clean --keep-fixes " + source
          : "git review clean --keep-fixes";
        const undo = button("Undo finish", "undoFinish", null);
        undo.disabled = model.busy;
        undo.title = "git review finish --abort";
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
        return empty(
          "The git-review CLI (0.4.0 or newer) was not found.",
          button("Install the CLI", "installCli", "primary"),
          model.stderr
        );
      case "cli-outdated":
        return empty(
          "The installed git-review CLI is older than 0.4.0.",
          button("Update the CLI", "installCli", "primary"),
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
  // curada sin explicación: una es una ausencia del walkthrough, la otra un
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
    // no dice cuáles son esas ediciones; "uncovered" sólo aplica en walk — en
    // step "annotated" no significa nada y siempre vale true.
    if (model.current.essential) {
      head.appendChild(el("span", "badge key", "key"));
    } else if (model.mode === "walk" && !model.current.annotated) {
      head.appendChild(el("span", "badge uncovered", "uncovered"));
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
    const prev = iconButton("left", "prev", "Previous entry");
    const next = iconButton("right", "next", "Next entry");
    prev.disabled = model.busy || model.atFirst;
    next.disabled = model.busy || model.atLast;
    nav.appendChild(prev);
    nav.appendChild(next);
    return nav;
  }

  /**
   * El listado de whole (FR-010): un inventario, no una secuencia — sin
   * cursor, sin controles de navegación. Cada fila abre el diff de su propia
   * entrada por su posición (no la "actual": whole no tiene una), reusando
   * el mismo helper button() que ya postea type+index para el inventario del
   * estado vacío. El diff y no el archivo del working tree: acá el objetivo
   * es revisar el cambio, no editar el resultado aplicado. Un rango sin
   * archivos MUST decirlo explícitamente (FR-007) — nunca una lista en
   * blanco sin explicación.
   *
   * Arriba de la lista va el mismo control que step tiene por commit, y por la
   * misma razón: la unidad de revisión del modo, entera y de un vistazo. Acá esa
   * unidad es el rango completo, así que abre todos los archivos juntos en un
   * multi-diff. Lleva title porque en esta pantalla "Diff" sin más se confunde
   * con el de cada fila.
   */
  function renderFiles(model) {
    if (model.files.length === 0) {
      return empty("This review's range does not touch any files.");
    }
    const box = el("div", "files");
    const n = model.files.length;
    box.appendChild(el("h2", null, n + (n === 1 ? " file" : " files") + " in this review"));

    const all = el("div", "row");
    const allButton = button("Diff", "openAllChanges", null, "diff");
    allButton.title = "Open every change in this review at once";
    all.appendChild(allButton);
    box.appendChild(all);

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
    // fills solo en no-review: Other actions colapsado se clava al fondo del
    // panel. En el resto de situaciones el root no debe estirar en flex.
    root.className = model.situation === "no-review" ? "fills" : "";
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
  if (saved) { receive(saved); }

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
