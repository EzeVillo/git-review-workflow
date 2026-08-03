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
  body {
    margin: 0;
    padding: 0;
    color: var(--vscode-foreground);
    font-family: var(--vscode-font-family);
    font-size: var(--vscode-font-size);
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
  .bar .pos { margin-left: auto; font-variant-numeric: tabular-nums; }
  .note {
    padding: .5em .8em;
    border-bottom: 1px solid var(--vscode-panel-border);
    color: var(--vscode-descriptionForeground);
    font-size: .9em;
    line-height: 1.5;
  }
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
  .id {
    margin: 0 0 .9em;
    font-family: var(--vscode-editor-font-family);
    overflow-wrap: anywhere;
    line-height: 1.4;
  }
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
  .foot {
    display: flex;
    gap: .8em;
    padding: .5em .8em;
    border-top: 1px solid var(--vscode-panel-border);
    font-size: .9em;
  }
  .empty { padding: 1.2em .9em; line-height: 1.6; }
  .empty p { margin: 0 0 1em; }
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
  // CSP, y este html se abre tal cual en un navegador para mirarlo. Cuatro
  // trazos alcanzan, y siguen el vocabulario que el revisor ya conoce de la
  // vista Source Control: archivo, diff, y los chevrones de navegar.
  const SVG_NS = "http://www.w3.org/2000/svg";
  const ICONS = {
    file: ["M4 1.6h5l3 3v9.8H4z", "M9 1.6v3h3"],
    diff: ["M2.5 5.6h8.4", "M8.1 2.8 10.9 5.6 8.1 8.4", "M13.5 10.4H5.1", "M7.9 7.6 5.1 10.4 7.9 13.2"],
    left: ["M10 3.4 5.4 8 10 12.6"],
    right: ["M6 3.4 10.6 8 6 12.6"]
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

  function button(label, message, className, iconName) {
    const node = el("button", className);
    if (iconName) { node.appendChild(icon(iconName)); }
    if (label) { node.appendChild(el("span", null, label)); }
    node.addEventListener("click", function () { vscode.postMessage({type: message}); });
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

  function renderEmptyState(model) {
    switch (model.situation) {
      case "no-review":
        return empty("No active review in this repository.", docsLink("How to start a review"));
      case "out-of-range":
        return empty(
          "The cursor is out of range: the base moved.",
          button("How to fix it", "outOfRangeHelp", "primary"),
          model.stderr
        );
      case "cli-missing":
        return empty(
          "The git-review CLI (0.3.0 or newer) was not found.",
          button("Install the CLI", "installCli", "primary"),
          model.stderr
        );
      case "cli-outdated":
        return empty(
          "The installed git-review CLI is older than 0.3.0.",
          button("Update the CLI", "installCli", "primary"),
          model.stderr
        );
      default:
        return empty("Something went wrong reading the review state.", null, model.stderr);
    }
  }

  function renderBar(model) {
    const bar = el("div", "bar");
    bar.appendChild(el("span", "mode", model.mode));
    const branch = model.repoLabel ? model.branch + " · " + model.repoLabel : model.branch;
    bar.appendChild(el("span", "branch", branch));
    if (model.position !== undefined && model.total !== undefined) {
      bar.appendChild(el("span", "pos", model.position + "/" + model.total));
    }
    return bar;
  }

  function renderWhy(why) {
    if (why.state === "present") { return el("div", "why", why.text); }
    if (why.state === "absent") { return el("div", "why quiet", "This entry has no explanation."); }
    if (why.state === "failed") { return el("div", "why quiet", "Could not read the why for this entry."); }
    return el("div", "why quiet", "Loading the why…");
  }

  function pad(n) { return n < 10 ? "0" + n : String(n); }

  function renderEntry(model) {
    const body = el("div", "body");
    const head = el("div", "head");
    head.appendChild(el("span", "n", pad(model.current.position)));
    // "key" es el marcador del propio walkthrough (la línea "> key"), no una
    // etiqueta inventada acá; "edits" sí necesita el título, porque abreviado
    // no dice cuáles son esas ediciones.
    if (model.current.essential) {
      head.appendChild(el("span", "badge key", "key"));
    } else if (model.current.banked) {
      const banked = el("span", "badge", "edits");
      banked.title = "This entry has banked edits";
      head.appendChild(banked);
    }
    body.appendChild(head);

    const id = el("p", "id", model.current.display);
    body.appendChild(id);

    if (model.why) {
      body.appendChild(renderWhy(model.why));
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

    // En step la entrada es un commit: no hay "el archivo" que abrir, sólo sus
    // cambios. En walk son dos destinos distintos y el ícono es lo que los
    // separa de un vistazo — la palabra sola ("File"/"Diff") se lee igual pero
    // se distingue más lento en una columna angosta.
    const open = el("div", "row");
    if (model.mode === "step") {
      open.appendChild(button("Diff", "openChange", null, "diff"));
    } else {
      open.appendChild(button("File", "openEntry", null, "file"));
      open.appendChild(button("Diff", "openChange", null, "diff"));
    }
    body.appendChild(open);

    // En un extremo de la secuencia el control no puede mover nada: se
    // deshabilita en vez de dejar un clic mudo. Quien decide si el cursor se
    // mueve sigue siendo la CLI — esto sólo refleja la position/total que ella
    // ya reportó, la misma que dibuja la barra de arriba.
    const nav = el("div", "row");
    const prev = iconButton("left", "prev", "Previous entry");
    const next = iconButton("right", "next", "Next entry");
    prev.disabled = model.busy || model.atFirst;
    next.disabled = model.busy || model.atLast;
    nav.appendChild(prev);
    nav.appendChild(next);
    body.appendChild(nav);
    return body;
  }

  // El pie tiene una sola entrada: los archivos que el walkthrough no anota.
  // La secuencia completa se alcanza por la paleta (gitReview.goToEntry); el
  // panel muestra la entrada actual y nada más. Sin nada que mostrar no se
  // dibuja, para no dejar un borde suelto abajo de todo.
  function renderFoot(model) {
    if (model.uncoveredCount <= 0) { return null; }
    const foot = el("div", "foot");
    foot.appendChild(button(model.uncoveredCount + " uncovered", "showUncovered", "link"));
    return foot;
  }

  function render(model) {
    root.textContent = "";
    if (model.situation !== "review") {
      root.appendChild(renderEmptyState(model));
      return;
    }

    root.appendChild(renderBar(model));
    if (model.busy) { root.appendChild(note("working…")); }
    if (model.baseMoved) { root.appendChild(note("The base moved: the total changed since the review started.")); }
    if (model.degraded) {
      root.appendChild(note("The walkthrough does not cover the review's current range; showing the full range diff."));
    }

    if (model.mode === "whole") {
      root.appendChild(empty("This review has no walkthrough: there is no curated reading order for this PR."));
    } else if (model.current) {
      root.appendChild(renderEntry(model));
    } else {
      root.appendChild(empty("The cursor does not point at any entry in the sequence."));
    }

    const foot = renderFoot(model);
    if (foot) { root.appendChild(foot); }
  }

  window.addEventListener("message", function (event) {
    if (event.data && event.data.type === "model") {
      // El modelo se guarda en el estado del webview: no es estado propio del
      // panel (FR-019), es la última copia de lo que mandó el host, para poder
      // redibujarla al recargarse sin una ida y vuelta.
      vscode.setState(event.data.model);
      render(event.data.model);
    }
  });

  // Ocultar la vista destruye este contexto y volver a mostrarla lo reconstruye
  // de cero. Sin esto el panel arranca vacío hasta que llegue el primer modelo;
  // con el estado guardado se dibuja ya, y el modelo que sigue lo pisa.
  const saved = vscode.getState();
  if (saved) { render(saved); }

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
