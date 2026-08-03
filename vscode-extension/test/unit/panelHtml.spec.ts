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
        assert.ok(/const saved = vscode\.getState\(\);\s*if \(saved\) \{ render\(saved\); \}/.test(html));
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
