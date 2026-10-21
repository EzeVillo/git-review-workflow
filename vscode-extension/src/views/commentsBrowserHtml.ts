import {COMMENTS_COPY as copy} from "../review/userCopy";

export function commentsBrowserHtml(nonce: string): string {
    return `<!doctype html>
<html lang="en"><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'">
<style>
* { box-sizing: border-box; }
html { color-scheme: light; }
html:has(body.vscode-dark), html:has(body.vscode-high-contrast) { color-scheme: dark; }
body {
    margin: 0; padding: 24px; min-height: 100vh;
    display: flex; align-items: center; justify-content: center;
    font-family: var(--vscode-font-family); font-size: var(--vscode-font-size);
    color: var(--vscode-foreground); background: var(--vscode-editor-background);
}
main {
    width: 100%; max-width: 800px; height: min(640px, calc(100vh - 48px)); overflow: auto;
    display: flex; flex-direction: column; gap: 16px; padding: 24px;
    border: 1px solid var(--vscode-widget-border, var(--vscode-panel-border, transparent));
    border-radius: 6px; background: var(--vscode-editorWidget-background, var(--vscode-editor-background));
    box-shadow: var(--vscode-shadow-lg, 0 4px 16px var(--vscode-widget-shadow, transparent));
}
h1 { margin: 0; font-size: 16px; font-weight: 600; flex-shrink: 0; }
button {
    font: inherit; min-width: 80px; min-height: 32px; padding: 6px 14px; cursor: pointer;
    border: 1px solid var(--vscode-button-border, transparent); border-radius: 2px;
    background: var(--vscode-button-background); color: var(--vscode-button-foreground);
}
button:hover:not(:disabled) { background: var(--vscode-button-hoverBackground); }
button:focus-visible, summary:focus-visible, pre:focus-visible { outline: 1px solid var(--vscode-focusBorder); outline-offset: -1px; }
button:disabled { opacity: .5; cursor: default; }
#list { flex: 0 1 auto; min-height: 0; max-height: 30%; overflow: auto; display: grid; grid-auto-rows: min-content; gap: 2px; padding: 2px; }
#list button { min-width: 0; text-align: left; background: transparent; color: inherit; padding: 10px; border-color: transparent; }
#list button:hover:not(:disabled):not([aria-pressed=true]) { background: var(--vscode-list-hoverBackground); }
#list button[aria-pressed=true] {
    background: var(--vscode-list-activeSelectionBackground); color: var(--vscode-list-activeSelectionForeground);
    border-color: var(--vscode-contrastActiveBorder, transparent);
}
#list strong, #list small { display: block; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
#list strong { font-weight: 500; }
#list small { margin-top: 5px; opacity: .8; }
#detail { flex: 1; min-height: 80px; overflow: auto; display: flex; flex-direction: column; gap: 10px; border-top: 1px solid var(--vscode-panel-border); padding-top: 16px; }
#body { flex: none; margin: 0; padding: 4px; line-height: 1.55; }
pre { font: inherit; white-space: pre-wrap; overflow-wrap: anywhere; }
#version { max-height: 100px; overflow: auto; color: var(--vscode-descriptionForeground); }
summary { cursor: pointer; color: var(--vscode-descriptionForeground); width: fit-content; }
#warning { color: var(--vscode-editorWarning-foreground); margin: 0; white-space: pre-wrap; overflow-wrap: anywhere; }
#error { color: var(--vscode-errorForeground); margin: 0; white-space: pre-wrap; overflow-wrap: anywhere; max-height: 15vh; overflow: auto; flex-shrink: 0; }
.actions { display: flex; justify-content: flex-end; gap: 8px; flex-shrink: 0; }
#delete { margin-right: auto; }
.secondary { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); }
.secondary:hover:not(:disabled) { background: var(--vscode-button-secondaryHoverBackground); }
[hidden] { display: none !important; }
@media (max-width: 480px), (max-height: 560px) {
    body { padding: 12px; }
    main { padding: 16px; gap: 12px; height: min(640px, calc(100vh - 24px)); }
    #detail { padding-top: 12px; }
}
</style></head><body>
<main aria-labelledby="title">
    <h1 id="title">${copy.entries}</h1>
    <nav id="list" aria-label="${copy.entries}"></nav>
    <section id="detail"><p id="warning" hidden></p><details id="details"><summary>${copy.details}</summary><pre id="version"></pre></details><pre id="body" tabindex="0" aria-label="${copy.body}"></pre></section>
    <p id="error" role="alert" hidden></p>
    <div class="actions"><button id="delete" class="secondary" hidden>${copy.delete}</button><button id="close" class="secondary">${copy.close}</button><button id="open" hidden>${copy.openDiff}</button></div>
</main>
<script nonce="${nonce}">
const api=acquireVsCodeApi(),list=document.getElementById('list'),open=document.getElementById('open'),remove=document.getElementById('delete');
let entries=[],selected,busy=false,canDelete=false;
function controls(){open.hidden=!selected?.canOpenDiff;open.disabled=busy||!selected?.canOpenDiff;remove.hidden=!canDelete;remove.disabled=busy||!selected;document.getElementById('close').disabled=busy;for(const button of list.children)button.disabled=busy}
function select(entry){selected=entry;const details=document.getElementById('details'),warning=document.getElementById('warning'),body=document.getElementById('body');details.open=false;details.hidden=!entry?.version;document.getElementById('version').textContent=entry?.version||'';warning.textContent=entry?.warning||'';warning.hidden=!entry?.warning;body.textContent=entry?.body||${JSON.stringify(copy.empty)};document.getElementById('detail').scrollTop=0;for(const button of list.children)button.setAttribute('aria-pressed',String(button.dataset.ordinal===String(entry?.ordinal)));controls()}
window.addEventListener('message',e=>{
    if(e.data.type==='entries'){
        const previous=selected?entries.indexOf(selected):0;
        entries=e.data.entries;canDelete=!!e.data.canDelete;list.replaceChildren();
        for(const entry of entries){const button=document.createElement('button');button.dataset.ordinal=entry.ordinal;button.title=entry.label;const heading=document.createElement('strong');heading.textContent=entry.label;button.appendChild(heading);const preview=document.createElement('small');preview.textContent=entry.preview;button.appendChild(preview);button.onclick=()=>{if(!busy)select(entry)};list.appendChild(button)}
        select(entries[Math.min(previous,entries.length-1)]);
    }
    if(e.data.type==='settled'){busy=false;controls();const error=document.getElementById('error');error.textContent=e.data.error||'';error.hidden=!e.data.error}
});
function activate(type){if(!selected||busy||(type==='open'&&!selected.canOpenDiff)||(type==='delete'&&!canDelete))return;busy=true;controls();api.postMessage({type,ordinal:selected.ordinal})}
function close(){if(!busy)api.postMessage({type:'close'})}
document.getElementById('close').onclick=close;
window.addEventListener('keydown',event=>{if(event.key==='Escape'&&!busy){event.preventDefault();close()}});
open.onclick=()=>activate('open');remove.onclick=()=>activate('delete');api.postMessage({type:'ready'});
</script></body></html>`;
}
