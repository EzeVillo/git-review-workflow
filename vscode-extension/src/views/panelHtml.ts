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
 */
export function panelHtml(nonce: string): string {
    return `<!DOCTYPE html>
<html lang="es">
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
  .badge {
    margin-left: auto;
    padding: 0 .4em;
    border: 1px solid var(--vscode-panel-border);
    border-radius: 3px;
    font-size: .85em;
    color: var(--vscode-textPreformat-foreground);
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
    font-family: inherit;
    font-size: inherit;
    padding: .35em .6em;
    border: none;
    border-radius: 2px;
    cursor: pointer;
    background: var(--vscode-button-secondaryBackground);
    color: var(--vscode-button-secondaryForeground);
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
  .foot .spacer { margin-left: auto; }
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

  function button(label, message, className) {
    const node = el("button", className, label);
    node.addEventListener("click", function () { vscode.postMessage({type: message}); });
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
        return empty("No hay una review activa en este repositorio.", docsLink("Cómo iniciar una review"));
      case "out-of-range":
        return empty(
          "El cursor quedó fuera de rango: la base se movió.",
          button("Cómo arreglarlo", "outOfRangeHelp", "primary"),
          model.stderr
        );
      case "cli-missing":
        return empty(
          "No se encontró la CLI git-review (≥ 0.3.0).",
          button("Instalar la CLI", "installCli", "primary"),
          model.stderr
        );
      case "cli-outdated":
        return empty(
          "La CLI git-review instalada es anterior a 0.3.0.",
          button("Actualizar la CLI", "installCli", "primary"),
          model.stderr
        );
      default:
        return empty("Ocurrió un error al leer el estado de la review.", null, model.stderr);
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
    if (why.state === "absent") { return el("div", "why quiet", "Esta entrada no tiene explicación."); }
    if (why.state === "failed") { return el("div", "why quiet", "No se pudo obtener el porqué de esta entrada."); }
    return el("div", "why quiet", "Cargando el porqué…");
  }

  function pad(n) { return n < 10 ? "0" + n : String(n); }

  function renderEntry(model) {
    const body = el("div", "body");
    const head = el("div", "head");
    head.appendChild(el("span", "n", pad(model.current.position)));
    if (model.current.essential) {
      head.appendChild(el("span", "badge", "esencial"));
    } else if (model.current.banked) {
      head.appendChild(el("span", "badge", "ediciones guardadas"));
    }
    body.appendChild(head);

    const id = el("p", "id", model.current.display);
    body.appendChild(id);

    if (model.why) {
      body.appendChild(renderWhy(model.why));
      // La lectura completa sólo tiene sentido si hay algo que leer, y es un
      // link y no un botón porque abre otra superficie, no actúa sobre ésta.
      if (model.why.state === "present") {
        const more = el("div", "more");
        more.appendChild(button("ver el porqué completo", "showWhy", "link"));
        body.appendChild(more);
      }
    }

    const open = el("div", "row");
    if (model.mode === "step") {
      open.appendChild(button("Ver los cambios", "openChange"));
    } else {
      open.appendChild(button("Abrir archivo", "openEntry"));
      open.appendChild(button("Ver cambios", "openChange"));
    }
    body.appendChild(open);

    const nav = el("div", "row");
    const prev = button("‹ Anterior", "prev");
    const next = button("Siguiente ›", "next");
    prev.disabled = model.busy;
    next.disabled = model.busy;
    nav.appendChild(prev);
    nav.appendChild(next);
    body.appendChild(nav);
    return body;
  }

  function renderFoot(model) {
    const foot = el("div", "foot");
    if (model.entryCount > 0) {
      foot.appendChild(button("Ir a una entrada… (" + model.entryCount + ")", "goToEntry", "link"));
    }
    if (model.uncoveredCount > 0) {
      const uncovered = button(model.uncoveredCount + " sin cobertura", "showUncovered", "link");
      uncovered.classList.add("spacer");
      foot.appendChild(uncovered);
    }
    return foot;
  }

  function render(model) {
    root.textContent = "";
    if (model.situation !== "review") {
      root.appendChild(renderEmptyState(model));
      return;
    }

    root.appendChild(renderBar(model));
    if (model.busy) { root.appendChild(note("trabajando…")); }
    if (model.baseMoved) { root.appendChild(note("La base se movió: el total cambió desde que empezó la review.")); }
    if (model.degraded) {
      root.appendChild(note("El walkthrough no cubre el rango actual de la review; se muestra el diff completo del rango."));
    }

    if (model.mode === "whole") {
      root.appendChild(empty("Esta review no tiene walkthrough: no hay un recorrido de lectura curado para este PR."));
    } else if (model.current) {
      root.appendChild(renderEntry(model));
    } else {
      root.appendChild(empty("El cursor no apunta a ninguna entrada de la secuencia."));
    }

    root.appendChild(renderFoot(model));
  }

  window.addEventListener("message", function (event) {
    if (event.data && event.data.type === "model") { render(event.data.model); }
  });
}());
</script>
</body>
</html>`;
}
