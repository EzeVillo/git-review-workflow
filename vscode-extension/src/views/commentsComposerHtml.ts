import {COMMENTS_COPY as copy} from "../review/userCopy";

/** A compact editor form: VS Code exposes webview tabs, not custom modal dialogs. */
export function commentsComposerHtml(nonce: string): string {
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
    width: 100%; max-width: 640px; max-height: calc(100vh - 48px); overflow: auto;
    padding: 24px; border: 1px solid var(--vscode-widget-border, var(--vscode-panel-border, transparent));
    border-radius: 6px; background: var(--vscode-editorWidget-background, var(--vscode-editor-background));
    box-shadow: var(--vscode-shadow-lg, 0 4px 16px var(--vscode-widget-shadow, transparent));
}
h1 { margin: 0 0 20px; font-size: 16px; font-weight: 600; }
form { display: flex; flex-direction: column; gap: 16px; }
.field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
select, textarea, button { font: inherit; }
select, textarea {
    display: block; width: 100%; min-width: 0; margin: 0;
    border: 1px solid var(--vscode-input-border, transparent); border-radius: 2px;
}
select, option {
    background: var(--vscode-dropdown-background, var(--vscode-input-background));
    color: var(--vscode-dropdown-foreground, var(--vscode-input-foreground));
}
select { min-height: 32px; padding: 5px 8px; border-color: var(--vscode-dropdown-border, var(--vscode-input-border, transparent)); }
textarea {
    height: clamp(140px, 28vh, 240px); min-height: 100px; padding: 8px 10px; resize: vertical;
    line-height: 1.5; background: var(--vscode-input-background); color: var(--vscode-input-foreground);
}
select:focus, textarea:focus, button:focus-visible { outline: 1px solid var(--vscode-focusBorder); outline-offset: -1px; }
select:disabled { opacity: .6; }
#context { max-height: 150px; overflow: auto; }
#warning { margin: 0; color: var(--vscode-descriptionForeground); line-height: 1.5; }
pre {
    margin: 0; padding: 8px 10px; white-space: pre-wrap; overflow-wrap: anywhere;
    font-family: var(--vscode-editor-font-family); font-size: var(--vscode-editor-font-size);
    background: var(--vscode-textCodeBlock-background, var(--vscode-editor-background));
    border: 1px solid var(--vscode-panel-border, transparent);
}
#warning:not([hidden]) + pre:not([hidden]) { margin-top: 10px; }
#error { margin: 0; color: var(--vscode-errorForeground); white-space: pre-wrap; overflow-wrap: anywhere; }
.actions { display: flex; justify-content: flex-end; gap: 8px; }
button {
    min-width: 80px; min-height: 32px; padding: 6px 14px; cursor: pointer;
    border: 1px solid var(--vscode-button-border, transparent); border-radius: 2px;
    background: var(--vscode-button-background); color: var(--vscode-button-foreground);
}
button:hover:not(:disabled) { background: var(--vscode-button-hoverBackground); }
button:disabled { opacity: .5; cursor: default; }
.secondary { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); }
.secondary:hover:not(:disabled) { background: var(--vscode-button-secondaryHoverBackground); }
[hidden] { display: none !important; }
@media (max-width: 480px), (max-height: 560px) {
    body { padding: 12px; }
    main { padding: 16px; max-height: calc(100vh - 24px); }
    h1 { margin-bottom: 16px; }
    form { gap: 12px; }
}
</style></head><body>
<main aria-labelledby="title">
    <h1 id="title">${copy.add}</h1>
    <form id="form">
        <div class="field"><label for="scope">${copy.scope}</label><select id="scope"></select></div>
        <div id="context" hidden><p id="warning" role="status" hidden></p><pre id="preview" hidden></pre></div>
        <select id="destination" aria-label="${copy.destination}" hidden></select>
        <div class="field"><label for="text">${copy.body}</label><textarea id="text"></textarea></div>
        <p id="error" role="alert" hidden></p>
        <div class="actions"><button id="cancel" class="secondary" type="button">${copy.cancel}</button><button id="save" type="submit" disabled>${copy.submit}</button></div>
    </form>
</main>
<script nonce="${nonce}">
const api=acquireVsCodeApi(),text=document.getElementById('text'),destination=document.getElementById('destination'),scope=document.getElementById('scope'),save=document.getElementById('save'),cancel=document.getElementById('cancel');let busy=false,capture,copy;
function update(){save.disabled=busy||!destination.value||!text.value.trim();cancel.disabled=busy;destination.disabled=busy;scope.disabled=busy;text.readOnly=busy;save.textContent=busy?copy.saving:copy.submit}
function preview(){const block=document.getElementById('preview'),warning=document.getElementById('warning');block.hidden=scope.value!=='selection';block.textContent=block.hidden?'':capture.snippet||'';document.getElementById('context').hidden=block.hidden&&warning.hidden}
function scopeLabel(value){if(value==='general')return copy.general;return (value==='selection'?copy.selection:copy.file)+' · '+capture.path+(value==='selection'?':'+capture.start+(capture.startColumn!==undefined?':'+capture.startColumn:'')+'–'+capture.end+(capture.endColumn!==undefined?':'+capture.endColumn:''):'')+' ('+(capture.side==='base'?copy.baseSide:copy.headSide)+')'}
text.oninput=update;destination.onchange=update;scope.onchange=preview;
document.getElementById('form').onsubmit=e=>{e.preventDefault();if(save.disabled)return;busy=true;const error=document.getElementById('error');error.textContent='';error.hidden=true;update();api.postMessage({type:'save',kind:destination.value,text:text.value,scope:scope.value})};cancel.onclick=()=>{if(!busy)api.postMessage({type:'cancel'})};
text.onkeydown=e=>{if((e.ctrlKey||e.metaKey)&&e.key==='Enter'){e.preventDefault();save.click()}};document.onkeydown=e=>{if(e.key==='Escape'&&!busy){e.preventDefault();api.postMessage({type:'cancel'})}};
window.addEventListener('message',e=>{if(e.data.type==='capture'){capture=e.data.capture;copy=e.data.copy;destination.replaceChildren();if(e.data.destinations.length>1){const prompt=new Option(copy.destination,'',true,true);prompt.disabled=true;prompt.hidden=true;destination.add(prompt);}for(const kind of e.data.destinations)destination.add(new Option(kind==='local'?copy.localDestination:copy.sharedDestination,kind));destination.hidden=e.data.destinations.length===1;const warning=document.getElementById('warning');warning.textContent=[e.data.warning,capture&&capture.unversioned?copy.unversioned:''].filter(Boolean).join(' ');warning.hidden=!warning.textContent;scope.textContent='';for(const value of e.data.scopes){const option=document.createElement('option');option.value=value;option.textContent=scopeLabel(value);scope.appendChild(option)}preview();update()}if(e.data.type==='error'){busy=false;const error=document.getElementById('error');error.textContent=e.data.text;error.hidden=!e.data.text;update()}});api.postMessage({type:'ready'});text.focus();
</script></body></html>`;
}
