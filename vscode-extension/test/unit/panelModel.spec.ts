import * as assert from "node:assert";
import {parsePorcelain} from "../../src/cli/porcelain";
// `import type`: `review/state.ts` importa `vscode`, que no existe fuera del
// host — el tipo se borra en compilación y el módulo no llega a cargarse.
import type {ReviewState} from "../../src/review/state";
import {buildPanelModel, entryPickLabel} from "../../src/views/panelModel";

/**
 * Arma el `ReviewState` desde salida porcelain real en vez de a mano: el modelo
 * del panel es una proyección de lo que la CLI reporta, y escribir los records
 * a mano probaría la proyección contra una copia del contrato en vez de contra
 * el contrato.
 */
function reviewState(stdout: string): ReviewState {
    const parsed = parsePorcelain(stdout);
    return {
        situation: "review",
        state: parsed.state,
        entries: parsed.entries,
        uncovered: parsed.uncovered,
    };
}

const WALK = [
    "state\treview/feat\torigin/feat\tabc123\twalk\tapplied\t2\t3\t3\tsrc/b.ts\t0",
    "entry\t1\tsrc/a.ts\t0",
    "entry\t2\tsrc/b.ts\t0",
    "entry\t3\tsrc/c.ts\t1",
    "uncovered\tsrc/d.ts",
    "",
].join("\n");

describe("buildPanelModel", () => {
    it("modo walk: entrada actual por position, contadores y why en vuelo", () => {
        const model = buildPanelModel(reviewState(WALK), {busy: false});

        assert.strictEqual(model.situation, "review");
        assert.strictEqual(model.mode, "walk");
        assert.strictEqual(model.branch, "review/feat");
        assert.strictEqual(model.position, 2);
        assert.strictEqual(model.total, 3);
        assert.strictEqual(model.baseMoved, false);
        assert.strictEqual(model.degraded, false);
        assert.strictEqual(model.entryCount, 3);
        assert.strictEqual(model.uncoveredCount, 1);
        assert.deepStrictEqual(model.current, {
            position: 2,
            display: "src/b.ts",
            essential: false,
            banked: false,
        });
        // Sin `why` en los inputs, el modelo dice "en vuelo" — no "sin explicación".
        assert.deepStrictEqual(model.why, {state: "loading"});
    });

    it("la entrada actual sale de position, no del primer entry ni del id", () => {
        const stdout = [
            // Cursor en 3, y el path del cursor se repite en la entrada 1: elegir
            // por `id` daría la 1.
            "state\treview/feat\torigin/feat\tabc123\twalk\tapplied\t3\t3\t3\tsrc/dup.ts\t0",
            "entry\t1\tsrc/dup.ts\t0",
            "entry\t2\tsrc/b.ts\t0",
            "entry\t3\tsrc/dup.ts\t0",
            "",
        ].join("\n");

        const model = buildPanelModel(reviewState(stdout), {busy: false});
        assert.strictEqual(model.current?.position, 3);
    });

    it("sin entrada que coincida con position no hay current, y no cae en la primera", () => {
        const stdout = [
            "state\treview/feat\torigin/feat\tabc123\twalk\tapplied\t9\t2\t2\tsrc/x.ts\t0",
            "entry\t1\tsrc/a.ts\t0",
            "entry\t2\tsrc/b.ts\t0",
            "",
        ].join("\n");

        const model = buildPanelModel(reviewState(stdout), {busy: false});
        assert.strictEqual(model.current, undefined);
        assert.strictEqual(model.why, undefined, "sin entrada actual no hay why que pedir");
        assert.strictEqual(model.entryCount, 2, "la secuencia sigue siendo alcanzable");
    });

    it("el raw de un path citado no cruza al modelo; sí el display", () => {
        const stdout = [
            'state\treview/feat\torigin/feat\tabc123\twalk\tapplied\t1\t1\t1\t"src/a\\303\\261o.ts"\t1',
            'entry\t1\t"src/a\\303\\261o.ts"\t1',
            "",
        ].join("\n");

        const model = buildPanelModel(reviewState(stdout), {busy: false});
        assert.strictEqual(model.current?.display, "src/año.ts");
        assert.strictEqual(model.current?.essential, true);
        assert.ok(
            !JSON.stringify(model).includes("\\303"),
            "el path crudo es sólo para volver a la CLI, no para el webview"
        );
    });

    it("baseMoved cuando total != recorded", () => {
        const moved = "state\treview/feat\torigin/feat\tabc123\twalk\tapplied\t1\t4\t7\tsrc/a.ts\t0\nentry\t1\tsrc/a.ts\t0\n";
        assert.strictEqual(buildPanelModel(reviewState(moved), {busy: false}).baseMoved, true);
    });

    it("en el medio de la secuencia no hay ningun extremo", () => {
        const model = buildPanelModel(reviewState(WALK), {busy: false});
        assert.strictEqual(model.atFirst, false);
        assert.strictEqual(model.atLast, false);
    });

    it("atFirst en la primera y atLast en la ultima, cada uno por su lado", () => {
        const first = "state\tr\ts\tt\twalk\tapplied\t1\t3\t3\tsrc/a.ts\t0\nentry\t1\tsrc/a.ts\t0\n";
        const last = "state\tr\ts\tt\twalk\tapplied\t3\t3\t3\tsrc/c.ts\t0\nentry\t3\tsrc/c.ts\t0\n";
        const firstModel = buildPanelModel(reviewState(first), {busy: false});
        const lastModel = buildPanelModel(reviewState(last), {busy: false});

        assert.strictEqual(firstModel.atFirst, true);
        assert.strictEqual(firstModel.atLast, false);
        assert.strictEqual(lastModel.atFirst, false);
        assert.strictEqual(lastModel.atLast, true);
    });

    it("una secuencia de una sola entrada es a la vez el principio y el final", () => {
        const only = "state\tr\ts\tt\twalk\tapplied\t1\t1\t1\tsrc/only.ts\t0\nentry\t1\tsrc/only.ts\t0\n";
        const model = buildPanelModel(reviewState(only), {busy: false});
        assert.strictEqual(model.atFirst, true);
        assert.strictEqual(model.atLast, true);
    });

    it("un cursor pasado del total re-derivado tambien es un extremo", () => {
        // La base se movio y el total bajo: seguir avanzando no lleva a ningun
        // lado, aunque `position === total` sea falso.
        const past = "state\tr\ts\tt\twalk\tapplied\t5\t2\t7\tsrc/x.ts\t0\nentry\t1\tsrc/a.ts\t0\nentry\t2\tsrc/b.ts\t0\n";
        const model = buildPanelModel(reviewState(past), {busy: false});
        assert.strictEqual(model.atLast, true);
        assert.strictEqual(model.atFirst, false);
    });

    it("modo step tambien reporta los extremos", () => {
        const stdout = [
            "state\treview/feat\torigin/feat\tabc123\tstep\tnone\t2\t2\t2\t9fe1c0d",
            "entry\t1\tabc1234\t1",
            "entry\t2\t9fe1c0d\t0",
            "",
        ].join("\n");
        const model = buildPanelModel(reviewState(stdout), {busy: false});
        assert.strictEqual(model.atLast, true);
        assert.strictEqual(model.atFirst, false);
    });

    it("sin cursor no hay extremo que marcar", () => {
        const whole = "state\treview/feat\torigin/feat\tabc123\twhole\tnone\nuncovered\tsrc/a.ts\n";
        const model = buildPanelModel(reviewState(whole), {busy: false});
        assert.strictEqual(model.atFirst, false);
        assert.strictEqual(model.atLast, false);

        const noReview = buildPanelModel(
            {situation: "no-review", entries: [], uncovered: []},
            {busy: false}
        );
        assert.strictEqual(noReview.atFirst, false);
        assert.strictEqual(noReview.atLast, false);
    });

    it("modo step: banked se refleja y no se pide why", () => {
        const stdout = [
            "state\treview/feat\torigin/feat\tabc123\tstep\tnone\t2\t2\t2\t9fe1c0d",
            "entry\t1\tabc1234\t1",
            "entry\t2\t9fe1c0d\t0",
            "",
        ].join("\n");

        const model = buildPanelModel(reviewState(stdout), {busy: true});
        assert.strictEqual(model.mode, "step");
        assert.strictEqual(model.busy, true);
        assert.strictEqual(model.current?.display, "9fe1c0d");
        assert.strictEqual(model.current?.banked, false);
        assert.strictEqual(model.why, undefined, "el modo step no tiene explicaciones");
        assert.strictEqual(model.uncoveredCount, 0);
    });

    it("modo whole degradado: sin secuencia, con los archivos del rango alcanzables", () => {
        const stdout = [
            "state\treview/feat\torigin/feat\tabc123\twhole\tdegraded",
            "uncovered\tsrc/a.ts",
            "uncovered\tsrc/b.ts",
            "",
        ].join("\n");

        const model = buildPanelModel(reviewState(stdout), {busy: false});
        assert.strictEqual(model.degraded, true);
        assert.strictEqual(model.entryCount, 0);
        assert.strictEqual(model.uncoveredCount, 2);
        assert.strictEqual(model.current, undefined);
        assert.strictEqual(model.position, undefined);
        assert.strictEqual(model.why, undefined);
    });

    it("una situación que no es review no lleva nada de la review, y sí el stderr", () => {
        const state: ReviewState = {
            situation: "out-of-range",
            entries: [],
            uncovered: [],
            stderr: "error: the cursor is out of range\n",
        };
        const model = buildPanelModel(state, {busy: false});

        assert.strictEqual(model.situation, "out-of-range");
        assert.strictEqual(model.mode, undefined);
        assert.strictEqual(model.branch, undefined);
        assert.strictEqual(model.current, undefined);
        assert.strictEqual(model.stderr, "error: the cursor is out of range\n");
    });

    it("un stderr en blanco no se propaga como diagnóstico", () => {
        const state: ReviewState = {situation: "error", entries: [], uncovered: [], stderr: "  \n"};
        assert.strictEqual(buildPanelModel(state, {busy: false}).stderr, undefined);
    });

    it("repoLabel sólo cuando el llamador lo pasa (multi-root)", () => {
        const withLabel = buildPanelModel(reviewState(WALK), {busy: false, repoLabel: "api"});
        assert.strictEqual(withLabel.repoLabel, "api");
        assert.strictEqual(buildPanelModel(reviewState(WALK), {busy: false}).repoLabel, undefined);
    });

    it("los cuatro estados del why se propagan tal cual", () => {
        const state = reviewState(WALK);
        assert.deepStrictEqual(
            buildPanelModel(state, {busy: false, why: {state: "present", text: "porque sí"}}).why,
            {state: "present", text: "porque sí"}
        );
        assert.deepStrictEqual(buildPanelModel(state, {busy: false, why: {state: "absent"}}).why, {state: "absent"});
        assert.deepStrictEqual(buildPanelModel(state, {busy: false, why: {state: "failed"}}).why, {state: "failed"});
    });
});

describe("entryPickLabel", () => {
    const {entries} = parsePorcelain(WALK);

    it("numera con dos dígitos y muestra el path legible", () => {
        assert.strictEqual(entryPickLabel(entries[0], 2).label, "01  src/a.ts");
    });

    it("marca la actual y la esencial con texto, no sólo con color", () => {
        assert.strictEqual(entryPickLabel(entries[1], 2).description, "actual");
        assert.strictEqual(entryPickLabel(entries[2], 2).description, "esencial");
    });

    it("una entrada actual Y esencial lleva las dos marcas", () => {
        assert.strictEqual(entryPickLabel(entries[2], 3).description, "actual · esencial");
    });

    it("una entrada sin marcas no lleva descripción", () => {
        assert.strictEqual(entryPickLabel(entries[0], 2).description, "");
    });

    it("en step la marca es la de ediciones guardadas", () => {
        const step = parsePorcelain("state\tr\ts\tt\tstep\tnone\t1\t1\t1\tabc1234\nentry\t1\tabc1234\t1\n");
        assert.strictEqual(entryPickLabel(step.entries[0], 2).description, "con ediciones guardadas");
        assert.strictEqual(entryPickLabel(step.entries[0], 2).label, "01  abc1234");
    });

    it("posiciones de dos dígitos no se rellenan", () => {
        const wide = parsePorcelain("state\tr\ts\tt\tstep\tnone\t10\t10\t10\tabc\nentry\t10\tabc1234\t0\n");
        assert.strictEqual(entryPickLabel(wide.entries[0], 10).label, "10  abc1234");
    });
});
