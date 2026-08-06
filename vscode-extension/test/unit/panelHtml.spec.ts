import * as assert from "node:assert";
import {panelHtml} from "../../src/views/panelHtml";

const html = panelHtml("TESTNONCE");

/**
 * Propiedades estructurales del HTML del panel. No prueban cómo se ve —eso se
 * mira a ojo (quickstart §8)—, sino las tres cosas que un webview puede romper
 * en silencio: el tema, la accesibilidad y la CSP (research.md Decisión 4).
 */
describe("panelHtml", () => {
    it("declara la CSP con el nonce y sin permitir orígenes externos", () => {
        assert.ok(html.includes("default-src 'none'"));
        assert.ok(html.includes("script-src 'nonce-TESTNONCE'"));
        assert.ok(html.includes("style-src 'nonce-TESTNONCE'"));
        assert.ok(!html.includes("unsafe-inline"), "unsafe-inline anularía el nonce");
        assert.ok(!html.includes("unsafe-eval"));
    });

    it("el único script y el único style llevan el nonce", () => {
        const scripts = html.match(/<script[^>]*>/g) ?? [];
        const styles = html.match(/<style[^>]*>/g) ?? [];
        assert.strictEqual(scripts.length, 1);
        assert.strictEqual(styles.length, 1);
        assert.ok(scripts[0].includes('nonce="TESTNONCE"'));
        assert.ok(styles[0].includes('nonce="TESTNONCE"'));
        assert.ok(!html.includes("<script src"), "nada se carga de un origen remoto");
    });

    it("no hardcodea colores: todo sale del tema del host (FR-031)", () => {
        const literals = html.match(/#[0-9a-fA-F]{3,8}\b/g) ?? [];
        assert.deepStrictEqual(literals, [], `un color literal no se adapta al tema: ${literals.join(", ")}`);
        assert.ok(!/\brgb\(/.test(html));
        assert.ok(html.includes("var(--vscode-foreground)"));
        assert.ok(html.includes("var(--vscode-focusBorder)"), "el foco por teclado necesita ser visible");
    });

    it("el contenido variable nunca se inserta como HTML", () => {
        assert.ok(!html.includes("innerHTML"));
        assert.ok(!html.includes("outerHTML"));
        assert.ok(!html.includes("insertAdjacentHTML"));
        assert.ok(!html.includes("document.write"));
        assert.ok(html.includes("textContent"));
    });

    it("los controles son botones reales, no divs clickeables", () => {
        assert.ok(html.includes('createElement("button")') || html.includes('el("button"'));
        assert.ok(!/onclick=/.test(html), "nada de handlers en atributos: la CSP los bloquearía");
    });

    it("un boton sin texto visible igual tiene nombre accesible", () => {
        // Los controles de navegar son sólo un ícono: sin esto un lector de
        // pantalla anuncia un botón mudo, y el hover no dice a dónde va.
        assert.ok(/node\.setAttribute\("aria-label", label\)/.test(html));
        assert.ok(/node\.title = label/.test(html));
        assert.ok(
            /iconButton\("left", "prev", "[^"]+"\)/.test(html) && /iconButton\("right", "next", "[^"]+"\)/.test(html),
            "prev/next se dibujan con el helper que exige la etiqueta"
        );
        assert.ok(html.includes('svg.setAttribute("aria-hidden", "true")'), "el ícono no se anuncia dos veces");
    });

    it("los iconos son svg inline: nada que cargar desde afuera", () => {
        // Los codicons son una fuente: usarlos obligaría a servir el .ttf como
        // recurso del webview y a abrirle `font-src` a la CSP de arriba.
        assert.ok(html.includes("createElementNS"), "los paths se crean en el namespace de SVG");
        assert.ok(!html.includes("@font-face"));
        const csp = /content="([^"]*)"/.exec(html)?.[1] ?? "";
        assert.ok(csp.includes("default-src"), "no se encontró la CSP para afirmar sobre ella");
        assert.ok(!csp.includes("font-src"), "una fuente de íconos obligaría a ampliar la CSP");
        assert.ok(!html.includes("codicon.ttf"));
        assert.ok(html.includes("stroke: currentColor"), "el ícono toma el color del botón, no uno propio");
    });

    it("los controles de navegación se deshabilitan también en los extremos", () => {
        // No hay DOM acá (el webview corre en su propio contexto), así que se
        // afirma sobre el origen del `disabled`: si alguien vuelve a atarlo sólo
        // a `busy`, el clic en el último paso queda mudo otra vez.
        assert.ok(/prev\.disabled\s*=\s*model\.busy\s*\|\|\s*model\.atFirst/.test(html));
        assert.ok(/next\.disabled\s*=\s*model\.busy\s*\|\|\s*model\.atLast/.test(html));
        assert.ok(html.includes("button[disabled]"), "y el estado tiene que verse, no sólo existir");
    });

    it("pide el modelo recién después de registrar el listener que lo recibe", () => {
        // Ocultar la vista destruye el contexto del webview, así que esto corre
        // de nuevo en cada reapertura. Si el `ready` sale antes del listener, el
        // modelo que el host postea en respuesta llega al vacío y el panel queda
        // en blanco — y sin sus botones no hay forma de pedir otro.
        const listener = html.indexOf('window.addEventListener("message"');
        const ready = html.indexOf('postMessage({type: "ready"})');
        assert.ok(listener !== -1, "el webview tiene que escuchar el modelo");
        assert.ok(ready !== -1, "el webview tiene que anunciar que ya escucha");
        assert.ok(ready > listener, "el handshake no puede adelantarse a su propio listener");
    });

    it("guarda el modelo recibido y redibuja el guardado al recargarse", () => {
        assert.ok(html.includes("vscode.setState(event.data.model)"));
        assert.ok(/const saved = vscode\.getState\(\);\s*if \(saved\) \{ receive\(saved\); \}/.test(html));
    });

    it("la carga es una sola fase: el why en vuelo tambien cuenta como pendiente", () => {
        // Sin el segundo término, el panel vuelve a las dos fases: primero
        // `working…` sobre la entrada vieja y después "Loading the why…" sobre
        // la nueva, que es exactamente lo que se sentía como tildado.
        assert.ok(
            /m\.busy === true \|\| \(m\.why !== undefined && m\.why\.state === "loading"\)/.test(html),
            "el estado pendiente tiene que cubrir busy y el why en vuelo"
        );
        assert.ok(!html.includes('note("working…")'), "la nota de working la reemplaza el esqueleto");
    });

    it("el esqueleto no se dibuja antes del delay que evita el parpadeo", () => {
        // Sin el delay, una navegación rápida muestra el esqueleto un frame y
        // desaparece: peor que no mostrar nada.
        assert.ok(/const SKELETON_DELAY_MS = \d+;/.test(html));
        assert.ok(/showTimer = setTimeout\(paintSkeleton, SKELETON_DELAY_MS\)/.test(html));
        // Y con el panel todavía en blanco no hay parpadeo que evitar: ahí el
        // esqueleto entra ya, o la vista recién reabierta se queda vacía.
        assert.ok(/if \(painted === undefined\) \{\s*\/\/[^]*?paintSkeleton\(\);/.test(html));
    });

    it("un why lento no retiene la entrada indefinidamente", () => {
        assert.ok(/const WHY_WAIT_MS = \d+;/.test(html));
        assert.ok(/Date\.now\(\) - pendingSince >= WHY_WAIT_MS/.test(html), "falta el techo de espera del why");
    });

    it("los controles no actuan sobre una entrada que ya no es la dibujada", () => {
        // El `disabled` no alcanza: entre el clic y el esqueleto hay una ventana
        // en la que sigue en pantalla la entrada anterior, y "File" abriría el
        // archivo equivocado.
        assert.ok(/function stale\(\) \{ return painted !== model; \}/.test(html));
        assert.ok(/if \(stale\(\)\) \{ return; \}\s*vscode\.postMessage/.test(html));
    });

    it("el esqueleto se anuncia a un lector de pantalla y respeta reduced-motion", () => {
        // Bloques grises son invisibles para quien no los ve: sin el texto, el
        // panel queda mudo justo mientras carga.
        assert.ok(/body\.setAttribute\("role", "status"\)/.test(html));
        assert.ok(/body\.setAttribute\("aria-busy", "true"\)/.test(html));
        assert.ok(/el\("span", "sr-only", "Loading the entry…"\)/.test(html));
        assert.ok(/el\("span", "sr-only", "Loading the why…"\)/.test(html));
        assert.ok(html.includes("prefers-reduced-motion: reduce"), "el pulso es decoración, no información");
    });

    it("dibuja los cuatro estados del why y los cinco estados vacíos", () => {
        for (const state of ["present", "absent", "failed"]) {
            assert.ok(html.includes(`"${state}"`), `falta el estado ${state} del why`);
        }
        for (const situation of ["no-review", "out-of-range", "cli-missing", "cli-outdated"]) {
            assert.ok(html.includes(`"${situation}"`), `falta el estado vacío ${situation}`);
        }
    });

    it("el inventario solo ofrece Continue sobre una fila guardada y resumible", () => {
        // Las dos guardas son lo que evita ofrecer una accion que el verbo
        // rechazaria; sin ellas el boton queda para cualquier fila.
        assert.ok(/if \(review\.saved\) \{/.test(html), "solo las guardadas llevan accion");
        assert.ok(
            /go\.disabled = model\.busy \|\| !review\.resumable/.test(html),
            "una fila no resumible, o una mutacion en curso, deshabilitan el boton"
        );
        assert.ok(/button\("Continue", "continueReview", null, null, index\)/.test(html));
    });

    it("las acciones del inventario van en una fila debajo de la meta", () => {
        // No en la misma flex que "step · 2/4": en sidebar angosto eso
        // partía los botones a medias. Meta, y debajo .rev-actions compactas.
        assert.ok(html.includes('el("div", "rev-meta", reviewMeta(review))'));
        assert.ok(html.includes('el("div", "rev-actions")'));
        assert.ok(html.includes(".rev-actions"), "estilo de la fila de botones");
        assert.ok(html.includes("flex: 0 1 auto") || html.includes("width: auto"),
            "botones del inventario no toman todo el ancho del sidebar");
    });

    it("un Continue deshabilitado dice por que lo esta", () => {
        assert.ok(/go\.title = review\.orphan/.test(html), "el motivo depende de la fila");
        assert.ok(html.includes("use Discard") || html.includes("Discard"),
            "huerfana guardada: apunta a Discard en el panel");
        assert.ok(html.includes("A review of this branch is already active"));
    });

    it("orphan en el inventario ofrece Discard a un clic", () => {
        assert.ok(/function reviewMeta\(review\)/.test(html));
        assert.ok(html.includes('button(review.orphan ? "Discard orphan" : "Discard", "discardInventory"'),
            "orphan/saved llevan boton discardInventory");
        assert.ok(html.includes("git review forget --saved") || html.includes("git review clean"),
            "title del boton nombra el verbo");
    });

    it("una review activa en otra rama explica por que no hay botones", () => {
        // Sin saved ni orphan no hay verbo seguro: badge ? con title al hover
        // (sandbox: review/feature/shipping o conflict desde develop).
        assert.ok(html.includes("function inventoryHelpTitle(review)"));
        assert.ok(html.includes("Still active — switch to this branch to work on it."));
        assert.ok(html.includes("Finish waiting on") || html.includes("use Undo above"));
        assert.ok(html.includes("badge help") || html.includes('"badge help"'));
        assert.ok(/help:\s*\[/.test(html), "el ? de ayuda es un path SVG inline");
    });

    it("una review readonly (compare) avisa y no sugiere finish en el panel", () => {
        // Finish vive en view/title y se oculta con gitReview.readonly; el
        // webview solo muestra la nota para que el revisor entienda por que.
        assert.ok(
            /if \(model\.readonly\) \{/.test(html) || /model\.readonly/.test(html),
            "el panel lee readonly del modelo"
        );
        assert.ok(
            html.includes("read-only") || html.includes("Read-only") || html.includes("compare"),
            "nota visible de compare de solo lectura"
        );
    });

    it("no-review ofrece compare y walkthrough bajo Other actions; finish-pending no", () => {
        // Empty state sin review activa: compare/walkthrough viven en
        // renderEmptyStartBlock (solo no-review). finish-pending es una
        // pantalla propia de post-cierre, sin empty state ni Other actions.
        // Other actions es un <details> plegado por defecto para no pelear
        // por alto con Start / base / inventario.
        assert.ok(html.includes('function renderOtherActions(model)'));
        assert.ok(html.includes('function renderEmptyStartBlock(model)'));
        assert.ok(html.includes('el("details", "tools")'));
        assert.ok(html.includes('el("summary", null, "Other actions")'));
        assert.ok(html.includes("otherActionsOpen"), "el toggle sobrevive al redibujado del modelo");
        // Colapsado: al fondo del panel (no solo del contenido). Abierto: flujo
        // bajo Start. El empty crece con #root.fills / .pane-main.
        assert.ok(html.includes('#root.fills') || html.includes('root.className = model.situation === "no-review" ? "fills"'));
        assert.ok(html.includes("margin-top: auto"), "colapsado se clava al borde inferior del panel");
        assert.ok(html.includes('el("div", "pane-main")'), "con inventario el alto se reparte Start+tools");
        assert.ok(html.includes('button("Compare revisions", "compareReview")'));
        assert.ok(html.includes('button("Walkthrough: Init", "walkthroughInit")'));
        assert.ok(html.includes('button("Walkthrough: Build", "walkthroughBuild")'));
        const startBlock = /function renderEmptyStartBlock\(model\) \{([^]*?)\n {2}\}/.exec(html)?.[1] ?? "";
        assert.ok(startBlock.includes("renderOtherActions"), "Other actions salen del bloque compartido");
        assert.ok(html.includes('case "no-review"') && html.includes("renderEmptyStartBlock"));
        const pendingBranch = /case "finish-pending": \{([^]*?)\n {6}case "out-of-range"/.exec(html)?.[1] ?? "";
        assert.ok(pendingBranch.length > 0, "no se encontro el caso finish-pending");
        assert.ok(
            !pendingBranch.includes("renderEmptyStartBlock") && !pendingBranch.includes("renderOtherActions"),
            "finish-pending no reutiliza el empty state de no-review"
        );
    });

    it("error y out-of-range ofrecen How to fix it con el stderr de la CLI", () => {
        assert.ok(html.includes('case "out-of-range"'));
        assert.ok(html.includes('case "error"'));
        // Ambos empty states cablean el mismo boton: el stderr de la CLI ya
        // trae el how-to y el host lo re-muestra (FR-024).
        const howTo = 'button("How to fix it", "outOfRangeHelp", "primary")';
        const outOfRangeIdx = html.indexOf('case "out-of-range"');
        const errorIdx = html.indexOf('case "error"');
        assert.ok(outOfRangeIdx >= 0 && errorIdx >= 0);
        assert.ok(html.includes(howTo));
        assert.ok(
            html.slice(errorIdx, errorIdx + 400).includes("outOfRangeHelp"),
            "error debe ofrecer How to fix it como out-of-range"
        );
    });

    it("el mensaje del inventario lleva un indice, nunca el nombre de la rama", () => {
        // El nombre viaja al panel para mostrarlo; lo que vuelve es la posicion,
        // que el host resuelve contra su propio inventario.
        assert.ok(
            /\{type: message, index: index\}/.test(html),
            "el unico dato de un mensaje es el indice"
        );
        assert.ok(
            !/postMessage\([^)]*\bname\b/.test(html),
            "el nombre de la rama no vuelve del webview"
        );
    });

    it("modo whole dibuja la lista de archivos, no un mensaje fijo de 'sin walkthrough' (FR-010)", () => {
        // El mensaje incondicional que reemplazó esta feature: si sigue estando
        // sin condicionarlo a model.files, la lista nunca se dibuja.
        assert.ok(
            !/appendChild\(empty\("This review has no walkthrough[^)]*\)\);\s*\}\s*else if \(model\.current\)/.test(
                html
            ),
            "el mensaje de 'sin walkthrough' ya no puede ser incondicional en whole"
        );
        assert.ok(/model\.files\.forEach/.test(html), "falta el recorrido de la lista de archivos");
        assert.ok(
            /button\(file\.display, "openChange", [^,]+, "diff", file\.position\)/.test(html),
            "cada fila tiene que abrir el diff de su propia entrada por posición, no la actual"
        );
    });

    it("whole marca la ultima fila abierta, y solo desde el modelo", () => {
        // La marca sale de `lastOpened` del modelo: si alguien la ata a una
        // variable del propio webview, muere cada vez que la vista se reconstruye
        // y deja de sobrevivir al cierre del editor.
        assert.ok(
            /if \(file\.display === model\.lastOpened\) \{/.test(html),
            "la marca tiene que decidirse comparando contra el modelo"
        );
        assert.ok(/row\.className = "file-row opened"/.test(html));
        assert.ok(/row\.setAttribute\("aria-current", "true"\)/.test(html), "la marca no puede ser sólo visual");
        assert.ok(html.includes(".file-row.opened"), "y necesita su regla de estilo");
        assert.ok(
            /\.file-row\.opened \{[^}]*border-left-color: var\(--vscode-textLink-foreground\)/.test(html),
            "en alto contraste el fondo solo no alcanza: hace falta la barra del margen"
        );
    });

    it("whole ofrece abrir todos los cambios juntos, sin indice de fila", () => {
        // El equivalente del diff que step abre por commit. Sin índice: la
        // unidad acá es el rango entero, no una de las filas.
        assert.ok(
            /button\("Diff", "openAllChanges", null, "diff"\)/.test(html),
            "falta el control que abre el rango completo"
        );
        assert.ok(/allButton\.title = "[^"]+"/.test(html), "en esta pantalla 'Diff' a secas se confunde con el de la fila");
        const filesBody = /function renderFiles\(model\) \{([^]*?)\n  \}/.exec(html)?.[1] ?? "";
        assert.ok(filesBody.length > 0, "no se encontró renderFiles para afirmar sobre él");
        assert.ok(filesBody.includes('"openAllChanges"'), "el control vive en la lista de whole");
        assert.ok(
            !/openAllChanges", null, "diff", /.test(html),
            "abrir todo el rango no lleva índice de entrada"
        );
    });

    it("un rango sin archivos en whole dice explícitamente que no hay nada, sin lista rota (FR-007)", () => {
        assert.ok(
            html.includes("This review's range does not touch any files."),
            "falta el mensaje explícito del rango vacío"
        );
        assert.ok(/model\.files\.length === 0/.test(html), "el vacío tiene que decidirse por files, no por el modo");
    });

    it("whole no dibuja controles de navegación ni posición de cursor", () => {
        // La lista es un inventario: renderNavRow (prev/next) sólo puede llamarse
        // fuera de la rama de whole.
        const wholeBranch = /if \(model\.mode === "whole"\) \{([^]*?)\} else if \(model\.current\)/.exec(html)?.[1] ?? "";
        assert.ok(!wholeBranch.includes("renderNavRow"), "whole no tiene extremos que deshabilitar");
    });

    it("sin reviews en el repositorio el estado vacio queda como estaba", () => {
        assert.ok(
            /if \(reviews\.length === 0\) \{ return box; \}/.test(html),
            "sin inventario no se dibuja ni el encabezado ni el separador"
        );
        assert.ok(html.includes("Reviews in this repository"));
    });

    // ── finish (005 US3, contracts/finish-state.md) ─────────────────────────

    it("finish-conflict entra por la rama de review, no por el estado vacio (FR-027)", () => {
        assert.ok(
            /if \(model\.situation !== "review" && model\.situation !== "finish-conflict"\) \{/.test(html),
            "finish-conflict tiene que seguir mostrando mode/branch/current, no un estado vacio"
        );
        assert.ok(
            /if \(model\.situation === "finish-conflict"\) \{ root\.appendChild\(renderFinishConflictBanner\(\)\); \}/.test(html),
            "falta insertar el banner cuando el situation es finish-conflict"
        );
    });

    it("el banner de finish-conflict ofrece deshacer y continuar, sin controles de navegacion", () => {
        const bannerBody = /function renderFinishConflictBanner\(\) \{([^]*?)\n {2}\}/.exec(html)?.[1] ?? "";
        assert.ok(bannerBody.length > 0, "no se encontro renderFinishConflictBanner para afirmar sobre el");
        assert.ok(bannerBody.includes('"Undo", "undoFinish"'));
        assert.ok(bannerBody.includes('"Continue", "resumeFinish"'));
        // Los controles de navegacion se retiran, no solo se deshabilitan
        // (FR-027): un boton disabled sigue dejando ver una secuencia que ya
        // no corresponde recorrer.
        assert.ok(
            /if \(!model\.navigationLocked\) \{ body\.appendChild\(renderNavRow\(model\)\); \}/.test(html),
            "renderEntry/renderPending tienen que retirar renderNavRow bajo navigationLocked"
        );
    });

    it("finish-pending es pantalla propia: staged edits, Undo finish y Clean, sin empty state", () => {
        const pendingBranch = /case "finish-pending": \{([^]*?)\n {6}case "out-of-range"/.exec(html)?.[1] ?? "";
        assert.ok(pendingBranch.length > 0, "no se encontro el caso finish-pending en renderEmptyState");
        // Cierre ya hecho: el panel ancla al destino de las edits y al undo,
        // no a un empty state de "empezá otra cosa".
        assert.ok(
            pendingBranch.includes("staged") || pendingBranch.includes("Source Control"),
            "el copy tiene que anclar a edits staged / SCM"
        );
        assert.ok(
            pendingBranch.includes("Commit and push"),
            "tiene que recordar commitear y pushear las edits staged"
        );
        assert.ok(pendingBranch.includes('"Undo finish", "undoFinish"') || pendingBranch.includes("undoFinish"));
        assert.ok(
            pendingBranch.includes('"Clean", "cleanReview"') || pendingBranch.includes("cleanReview"),
            "Clean (git review clean --keep-fixes) cierra el limbo del undo"
        );
        assert.ok(
            pendingBranch.includes("clean --keep-fixes") || pendingBranch.includes("--keep-fixes"),
            "el copy/tooltip tiene que nombrar --keep-fixes"
        );
        assert.ok(
            !pendingBranch.includes("renderEmptyStartBlock") && !pendingBranch.includes("startReview"),
            "Start no va en finish-pending (palette / terminal si hace falta)"
        );
        assert.ok(
            !pendingBranch.includes("renderInventory"),
            "sin inventario: el flujo mental es cerrar o deshacer este finish"
        );
    });

    it("finish-pending nombra el destino real de las ediciones, no la rama de la review (M2)", () => {
        const pendingBranch = /case "finish-pending": \{([^]*?)\n {6}case "out-of-range"/.exec(html)?.[1] ?? "";
        assert.ok(pendingBranch.length > 0, "no se encontro el caso finish-pending en renderEmptyState");
        // El mismo computo que finishReview.ts: onto -> la rama del PR,
        // sin onto -> review-fixes/<x>, nunca "review/<x>" a secas.
        assert.ok(
            pendingBranch.includes('"review-fixes/" + source'),
            "sin --onto-source el destino tiene que ser review-fixes/<x>"
        );
        assert.ok(
            /pending\.onto \? source/.test(pendingBranch),
            "con --onto-source el destino tiene que ser la propia rama del PR, no review/<x>"
        );
    });

    it("el ciclo de vida no se dibuja en el webview: vive en view/title", () => {
        // Finish / Save / Cancel son iconos del chrome del panel (package.json
        // view/title). Duplicarlos acá partía el trio y gastaba el sidebar.
        const barBody = /function renderBar\(model, loading\) \{([^]*?)\n  \}/.exec(html)?.[1] ?? "";
        assert.ok(barBody.length > 0, "no se encontro renderBar para afirmar sobre el");
        assert.ok(!barBody.includes("saveReview"), "Save no va en la barra del webview");
        assert.ok(!barBody.includes("abortReview"), "Cancel no va en la barra del webview");
        assert.ok(!barBody.includes("finishReview"), "Finish no va en la barra del webview");
        assert.ok(!html.includes("Save for later"));
        assert.ok(!html.includes("Cancel review"));
    });
});
