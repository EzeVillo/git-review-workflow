/**
 * Genera el preview del panel: un HTML por estado más un índice que los muestra
 * lado a lado, para mirar el render en un navegador sin levantar un Extension
 * Development Host.
 *
 * El HTML de cada pane es el de `panelHtml()` **sin editar** — la misma función
 * que sirve el webview. Lo único que se le inyecta es un stub de
 * `acquireVsCodeApi` cuyo `getState()` devuelve el modelo de ejemplo, que es el
 * camino por el que el webview se redibuja al reconstruirse, y las variables de
 * tema que en VS Code pone el host.
 *
 * Lo que el preview NO puede afirmar: los botones no tienen extensión del otro
 * lado (`postMessage` es un no-op), y las variables de acá abajo son una copia
 * aproximada de los temas de VS Code, no los del usuario. Si el panel empieza a
 * usar una variable `--vscode-*` que no esté en esta lista, se va a ver mal acá
 * y bien en el editor: agregarla es parte del cambio.
 */
import * as fs from "node:fs";
import * as path from "node:path";
import {pathToFileURL} from "node:url";
import {panelHtml} from "../src/views/panelHtml";
import {PREVIEW_PANES} from "./fixtures";

const NONCE = "previewnonce";

/** Los tres temas por defecto de VS Code, aproximados. */
const THEMES: Record<string, Record<string, string>> = {
    dark: {
        "--vscode-foreground": "#cccccc",
        "--vscode-descriptionForeground": "#9d9d9d",
        "--vscode-panel-border": "#2b2b2b",
        "--vscode-badge-background": "#616161",
        "--vscode-badge-foreground": "#f8f8f8",
        "--vscode-textPreformat-foreground": "#d7ba7d",
        "--vscode-textLink-foreground": "#4daafc",
        "--vscode-textCodeBlock-background": "#202020",
        "--vscode-focusBorder": "#0078d4",
        "--vscode-button-background": "#0078d4",
        "--vscode-button-foreground": "#ffffff",
        "--vscode-button-hoverBackground": "#026ec1",
        "--vscode-button-secondaryBackground": "#313131",
        "--vscode-button-secondaryForeground": "#cccccc",
        "--vscode-button-secondaryHoverBackground": "#3c3c3c",
        "--vscode-list-hoverBackground": "#2a2d2e",
        "--vscode-toolbar-hoverBackground": "#5a5d5e50",
        "--vscode-list-inactiveSelectionBackground": "#37373d",
        "--vscode-sideBar-background": "#181818",
    },
    light: {
        "--vscode-foreground": "#3b3b3b",
        "--vscode-descriptionForeground": "#717171",
        "--vscode-panel-border": "#e5e5e5",
        "--vscode-badge-background": "#cccccc",
        "--vscode-badge-foreground": "#3b3b3b",
        "--vscode-textPreformat-foreground": "#a31515",
        "--vscode-textLink-foreground": "#005fb8",
        "--vscode-textCodeBlock-background": "#f8f8f8",
        "--vscode-focusBorder": "#005fb8",
        "--vscode-button-background": "#005fb8",
        "--vscode-button-foreground": "#ffffff",
        "--vscode-button-hoverBackground": "#0258a8",
        "--vscode-button-secondaryBackground": "#e5e5e5",
        "--vscode-button-secondaryForeground": "#3b3b3b",
        "--vscode-button-secondaryHoverBackground": "#cccccc",
        "--vscode-list-hoverBackground": "#e8e8e9",
        "--vscode-toolbar-hoverBackground": "#b8b8b850",
        "--vscode-list-inactiveSelectionBackground": "#e4e6f1",
        "--vscode-sideBar-background": "#f8f8f8",
    },
    "high-contrast": {
        "--vscode-foreground": "#ffffff",
        "--vscode-descriptionForeground": "#ffffff",
        "--vscode-panel-border": "#6fc3df",
        "--vscode-badge-background": "#000000",
        "--vscode-badge-foreground": "#ffffff",
        "--vscode-textPreformat-foreground": "#d7ba7d",
        "--vscode-textLink-foreground": "#3794ff",
        "--vscode-textCodeBlock-background": "#000000",
        "--vscode-focusBorder": "#f38518",
        "--vscode-button-background": "#0f4a85",
        "--vscode-button-foreground": "#ffffff",
        "--vscode-button-hoverBackground": "#0f4a85",
        "--vscode-button-secondaryBackground": "#000000",
        "--vscode-button-secondaryForeground": "#ffffff",
        "--vscode-button-secondaryHoverBackground": "#0f4a85",
        "--vscode-list-hoverBackground": "#000000",
        "--vscode-toolbar-hoverBackground": "#0f4a85",
        "--vscode-list-inactiveSelectionBackground": "#000000",
        "--vscode-sideBar-background": "#000000",
    },
};

const FONTS = {
    "--vscode-font-family": '"Segoe UI", system-ui, sans-serif',
    "--vscode-editor-font-family": "Consolas, \"Droid Sans Mono\", monospace",
    "--vscode-font-size": "13px",
};

function themeCss(): string {
    const blocks = Object.entries(THEMES).map(([name, vars]) => {
        const decls = Object.entries({...FONTS, ...vars})
            .map(([key, value]) => `    ${key}: ${value};`)
            .join("\n");
        // El primero es también el default, para que un pane abierto suelto
        // (sin `?theme=`) se vea igual que dentro del índice.
        const selector = name === "dark" ? `:root, :root[data-theme="dark"]` : `:root[data-theme="${name}"]`;
        return `  ${selector} {\n${decls}\n  }`;
    });
    return [...blocks, "  body { background: var(--vscode-sideBar-background); }"].join("\n");
}

/**
 * El tema llega por query string y lo aplica el propio pane: leerlo desde el
 * índice sería tocar el documento del iframe, y con `file://` los frames son
 * de origen opaco en la mayoría de los navegadores.
 */
function paneScript(model: unknown): string {
    return `
  document.documentElement.dataset.theme =
    new URLSearchParams(location.search).get("theme") || "dark";
  window.acquireVsCodeApi = function () {
    return {
      postMessage: function () {},
      setState: function () {},
      getState: function () { return ${JSON.stringify(model)}; }
    };
  };`;
}

function paneHtml(model: unknown): string {
    const html = panelHtml(NONCE);
    const openScript = `<script nonce="${NONCE}">`;
    if (!html.includes(openScript) || !html.includes("</style>")) {
        throw new Error("panelHtml() ya no tiene el <style>/<script> que el preview inyecta");
    }
    return html
        .replace("</style>", `${themeCss()}\n</style>`)
        .replace(openScript, `${openScript}${paneScript(model)}`);
}

function indexHtml(): string {
    const figures = PREVIEW_PANES.map(
        (pane) => `  <figure>
    <iframe data-pane="${pane.name}" src="./pane-${pane.name}.html" title="${pane.name}"></iframe>
    <figcaption><b>${pane.name}</b><br>${pane.caption}</figcaption>
  </figure>`
    ).join("\n");

    return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>git review — preview del panel</title>
<style>
  body {
    margin: 0;
    padding: 1.5rem;
    background: #1f1f1f;
    color: #cccccc;
    font: 13px/1.5 "Segoe UI", system-ui, sans-serif;
  }
  header { display: flex; align-items: baseline; gap: 1rem; margin-bottom: 1.2rem; }
  h1 { margin: 0; font-size: 1.1rem; font-weight: 600; }
  .panes { display: flex; flex-wrap: wrap; gap: 1.5rem; align-items: flex-start; }
  figure { margin: 0; width: 320px; }
  iframe { width: 320px; height: 420px; border: 1px solid #3c3c3c; }
  figcaption { margin-top: .5rem; color: #9d9d9d; }
  select { font: inherit; background: #313131; color: #cccccc; border: 1px solid #3c3c3c; padding: .2em .4em; }
</style>
</head>
<body>
<header>
  <h1>git review — preview del panel</h1>
  <label>tema
    <select id="theme">
      <option value="dark">Dark</option>
      <option value="light">Light</option>
      <option value="high-contrast">High Contrast</option>
    </select>
  </label>
  <span>320&nbsp;px de ancho, el de un sidebar. Generado por <code>npm run preview</code>.</span>
</header>
<div class="panes">
${figures}
</div>
<script>
  document.getElementById("theme").addEventListener("change", function (event) {
    const theme = event.target.value;
    document.querySelectorAll("iframe").forEach(function (frame) {
      frame.src = "./pane-" + frame.dataset.pane + ".html?theme=" + theme;
    });
  });
</script>
</body>
</html>
`;
}

function main(): void {
    // Sin argumento, junto al propio bundle: éste corre compilado, no desde
    // `preview/`, así que cualquier ruta relativa al fuente sería otra.
    const outDir = process.argv[2] ?? __dirname;
    fs.mkdirSync(outDir, {recursive: true});
    for (const pane of PREVIEW_PANES) {
        fs.writeFileSync(path.join(outDir, `pane-${pane.name}.html`), paneHtml(pane.model));
    }
    const index = path.join(outDir, "index.html");
    fs.writeFileSync(index, indexHtml());
    console.log(`preview: ${pathToFileURL(index).href}`);
}

main();
