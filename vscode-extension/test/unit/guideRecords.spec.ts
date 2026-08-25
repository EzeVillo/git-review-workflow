import * as assert from "node:assert";
import {parseConfigPorcelain} from "../../src/cli/configPorcelain";
import {parsePorcelain} from "../../src/cli/porcelain";
import {createGuideArgs, deleteGuideArgs} from "../../src/review/reviewIntent";
import {guideAt} from "../../src/views/panelModel";

const TAB = "\t";
const row = (...fields: string[]): string => fields.join(TAB);

describe("registro guide de config --porcelain", () => {
    it("parsea las dos guias, en el orden de la CLI", () => {
        const out = [
            row("config", "remote", "origin"),
            row("guide", "team", "/repo/.review/walkthrough-guide.md", "in-force"),
            row("guide", "own", "/repo/.git/review-walkthrough-guide.md", "absent"),
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.guides, [
            {kind: "team", path: "/repo/.review/walkthrough-guide.md", state: "in-force"},
            {kind: "own", path: "/repo/.git/review-walkthrough-guide.md", state: "absent"},
        ]);
    });

    it("distingue empty de absent: son dos ofertas distintas", () => {
        const out = [
            row("guide", "own", "/repo/.git/review-walkthrough-guide.md", "empty"),
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.strictEqual(result.guides[0]?.state, "empty");
    });

    it("sin registros el array esta vacio, no ausente", () => {
        // Es la degradacion contra una CLI que no conoce el registro: el bloque
        // entero no se dibuja, y nada explota.
        const result = parseConfigPorcelain(row("config", "remote", "origin") + "\n");
        assert.deepStrictEqual(result.guides, []);
    });

    it("ignora un registro con kind desconocido", () => {
        const out = [
            row("guide", "global", "/repo/x.md", "in-force"),
            row("guide", "own", "/repo/.git/review-walkthrough-guide.md", "in-force"),
            "",
        ].join("\n");
        assert.deepStrictEqual(parseConfigPorcelain(out).guides, [
            {kind: "own", path: "/repo/.git/review-walkthrough-guide.md", state: "in-force"},
        ]);
    });

    it("ignora un registro con estado desconocido o sin ruta", () => {
        const out = [
            row("guide", "own", "/repo/.git/review-walkthrough-guide.md", "maybe"),
            row("guide", "team", "", "in-force"),
            "",
        ].join("\n");
        assert.deepStrictEqual(parseConfigPorcelain(out).guides, []);
    });

    it("ignora campos extra al final, como cualquier registro conocido", () => {
        const out = row("guide", "own", "/x.md", "in-force", "algo-nuevo") + "\n";
        assert.deepStrictEqual(parseConfigPorcelain(out).guides, [
            {kind: "own", path: "/x.md", state: "in-force"},
        ]);
    });
});

describe("guideAt", () => {
    const guides = [
        {kind: "team" as const, path: "/a.md", state: "in-force" as const},
        {kind: "own" as const, path: "/b.md", state: "absent" as const},
    ];

    it("resuelve la fila por indice", () => {
        assert.strictEqual(guideAt(guides, 1)?.kind, "own");
    });

    it("rechaza lo que no es un entero en rango", () => {
        // El indice es lo unico que un mensaje del webview lleva: si no resuelve
        // contra el estado del host, no se invoca nada.
        assert.strictEqual(guideAt(guides, 2), undefined);
        assert.strictEqual(guideAt(guides, -1), undefined);
        assert.strictEqual(guideAt(guides, 1.5), undefined);
        assert.strictEqual(guideAt(guides, "0"), undefined);
        assert.strictEqual(guideAt(guides, undefined), undefined);
    });
});

describe("argv de las guias", () => {
    it("crear la propia no lleva flags", () => {
        assert.deepStrictEqual(createGuideArgs("own"), ["guide"]);
    });

    it("crear la compartida lleva --team", () => {
        assert.deepStrictEqual(createGuideArgs("team"), ["guide", "--team"]);
    });

    it("borrar es --delete y nunca --team", () => {
        // La compartida es un archivo trackeado: sacarla es git rm mas un commit,
        // y la CLI niega la combinacion.
        const args = deleteGuideArgs();
        assert.deepStrictEqual(args, ["guide", "--delete"]);
        assert.ok(!args.includes("--team"));
    });

    it("ninguno lleva --force", () => {
        // Pisar prosa escrita a mano con un archivo vacio no es algo que un flag
        // deba poder hacer; la CLI tambien lo rechaza.
        for (const args of [createGuideArgs("own"), createGuideArgs("team"), deleteGuideArgs()]) {
            assert.ok(!args.includes("--force"));
        }
    });
});

describe("el registro guide es de config --porcelain y de ningun otro verbo", () => {
    const line = (...fields: string[]): string => fields.join(TAB);
    const STATE = line("state", "review/feat/x", "feat/x", "abc123", "whole", "none");

    it("el parser del reporte de una review no lo conoce", () => {
        // Las guias se dibujan en el pie del panel y una review no tiene pie, asi
        // que el reporte que se lee adentro de una review no las nombra y el
        // parser no tiene por que reservarles un campo.
        const parsed = parsePorcelain(STATE + "\n") as unknown as Record<string, unknown>;
        assert.strictEqual("guides" in parsed, false);
    });
});
