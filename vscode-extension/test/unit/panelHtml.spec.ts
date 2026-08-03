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
});
