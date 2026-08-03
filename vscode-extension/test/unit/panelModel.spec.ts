import * as assert from "node:assert";
import {parseListPorcelain, parsePorcelain} from "../../src/cli/porcelain";
// `import type`: `review/state.ts` importa `vscode`, que no existe fuera del
// host — el tipo se borra en compilación y el módulo no llega a cargarse.
import type {ReviewState} from "../../src/review/state";
import {buildPanelModel, entryPickLabel, resumableSourceAt} from "../../src/views/panelModel";

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
        branches: [],
    };
}

const WALK = [
    "state\treview/feat\torigin/feat\tabc123\twalk\tapplied\t2\t4\t4\tsrc/b.ts\t0",
    "entry\t1\tsrc/a.ts\t0\t1",
    "entry\t2\tsrc/b.ts\t0\t1",
    "entry\t3\tsrc/c.ts\t1\t1",
    // src/d.ts cambia en el rango pero no tiene entrada propia: al final del
    // orden de lectura, essential siempre 0, annotated en 0.
    "entry\t4\tsrc/d.ts\t0\t0",
    "",
].join("\n");

describe("buildPanelModel", () => {
    it("modo walk: entrada actual por position, contadores y why en vuelo", () => {
        const model = buildPanelModel(reviewState(WALK), {busy: false});

        assert.strictEqual(model.situation, "review");
        assert.strictEqual(model.mode, "walk");
        assert.strictEqual(model.branch, "review/feat");
        assert.strictEqual(model.position, 2);
        assert.strictEqual(model.total, 4);
        assert.strictEqual(model.baseMoved, false);
        assert.strictEqual(model.degraded, false);
        assert.strictEqual(model.entryCount, 4);
        assert.deepStrictEqual(model.current, {
            position: 2,
            display: "src/b.ts",
            essential: false,
            annotated: true,
            banked: false,
        });
        // Sin `why` en los inputs, el modelo dice "en vuelo" — no "sin explicación".
        assert.deepStrictEqual(model.why, {state: "loading"});
    });

    it("una entrada no anotada llega al modelo con annotated en false", () => {
        const stdout = [
            "state\treview/feat\torigin/feat\tabc123\twalk\tapplied\t4\t4\t4\tsrc/d.ts\t0",
            ...WALK.split("\n").filter((l) => l.startsWith("entry")),
            "",
        ].join("\n");
        const model = buildPanelModel(reviewState(stdout), {busy: false});
        assert.strictEqual(model.current?.annotated, false);
        assert.strictEqual(model.current?.essential, false);
    });

    it("la entrada actual sale de position, no del primer entry ni del id", () => {
        const stdout = [
            // Cursor en 3, y el path del cursor se repite en la entrada 1: elegir
            // por `id` daría la 1.
            "state\treview/feat\torigin/feat\tabc123\twalk\tapplied\t3\t3\t3\tsrc/dup.ts\t0",
            "entry\t1\tsrc/dup.ts\t0\t1",
            "entry\t2\tsrc/b.ts\t0\t1",
            "entry\t3\tsrc/dup.ts\t0\t1",
            "",
        ].join("\n");

        const model = buildPanelModel(reviewState(stdout), {busy: false});
        assert.strictEqual(model.current?.position, 3);
    });

    it("sin entrada que coincida con position no hay current, y no cae en la primera", () => {
        const stdout = [
            "state\treview/feat\torigin/feat\tabc123\twalk\tapplied\t9\t2\t2\tsrc/x.ts\t0",
            "entry\t1\tsrc/a.ts\t0\t1",
            "entry\t2\tsrc/b.ts\t0\t1",
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
            'entry\t1\t"src/a\\303\\261o.ts"\t1\t1',
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

    it("baseMoved cuando total < recorded (la secuencia se achico)", () => {
        const moved = "state\treview/feat\torigin/feat\tabc123\twalk\tapplied\t1\t4\t7\tsrc/a.ts\t0\nentry\t1\tsrc/a.ts\t0\t1\n";
        assert.strictEqual(buildPanelModel(reviewState(moved), {busy: false}).baseMoved, true);
    });

    it("total > recorded no es baseMoved: es la secuencia creciendo (el upgrade de los no anotados)", () => {
        // Un review walk abierto antes de que los archivos no anotados entraran
        // al orden de lectura: su reviewwalkcount grabado queda por debajo del
        // total recien derivado. Eso no es la base moviendose.
        const grown = "state\treview/feat\torigin/feat\tabc123\twalk\tapplied\t1\t4\t3\tsrc/a.ts\t0\nentry\t1\tsrc/a.ts\t0\t1\n";
        assert.strictEqual(buildPanelModel(reviewState(grown), {busy: false}).baseMoved, false);
    });

    it("en el medio de la secuencia no hay ningun extremo", () => {
        const model = buildPanelModel(reviewState(WALK), {busy: false});
        assert.strictEqual(model.atFirst, false);
        assert.strictEqual(model.atLast, false);
    });

    it("atFirst en la primera y atLast en la ultima, cada uno por su lado", () => {
        const first = "state\tr\ts\tt\twalk\tapplied\t1\t3\t3\tsrc/a.ts\t0\nentry\t1\tsrc/a.ts\t0\t1\n";
        const last = "state\tr\ts\tt\twalk\tapplied\t3\t3\t3\tsrc/c.ts\t0\nentry\t3\tsrc/c.ts\t0\t1\n";
        const firstModel = buildPanelModel(reviewState(first), {busy: false});
        const lastModel = buildPanelModel(reviewState(last), {busy: false});

        assert.strictEqual(firstModel.atFirst, true);
        assert.strictEqual(firstModel.atLast, false);
        assert.strictEqual(lastModel.atFirst, false);
        assert.strictEqual(lastModel.atLast, true);
    });

    it("una secuencia de una sola entrada es a la vez el principio y el final", () => {
        const only = "state\tr\ts\tt\twalk\tapplied\t1\t1\t1\tsrc/only.ts\t0\nentry\t1\tsrc/only.ts\t0\t1\n";
        const model = buildPanelModel(reviewState(only), {busy: false});
        assert.strictEqual(model.atFirst, true);
        assert.strictEqual(model.atLast, true);
    });

    it("un cursor pasado del total re-derivado tambien es un extremo", () => {
        // La base se movio y el total bajo: seguir avanzando no lleva a ningun
        // lado, aunque `position === total` sea falso.
        const past = "state\tr\ts\tt\twalk\tapplied\t5\t2\t7\tsrc/x.ts\t0\nentry\t1\tsrc/a.ts\t0\t1\nentry\t2\tsrc/b.ts\t0\t1\n";
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
        const whole = "state\treview/feat\torigin/feat\tabc123\twhole\tnone\n";
        const model = buildPanelModel(reviewState(whole), {busy: false});
        assert.strictEqual(model.atFirst, false);
        assert.strictEqual(model.atLast, false);

        const noReview = buildPanelModel(
            {situation: "no-review", entries: [], branches: []},
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
        // En step "annotated" no significa nada: siempre true por ausencia de campo.
        assert.strictEqual(model.current?.annotated, true);
        assert.strictEqual(model.why, undefined, "el modo step no tiene explicaciones");
    });

    it("modo whole degradado: sin secuencia — no hay como enumerar el rango por porcelain", () => {
        // Antes esto emitia registros `uncovered`, uno por archivo del rango; se
        // elimino porque el degradado ya equivale a "todo el diff" (redundante
        // con lo que el working tree ya muestra), y whole nunca tuvo `entry`.
        const stdout = "state\treview/feat\torigin/feat\tabc123\twhole\tdegraded\n";

        const model = buildPanelModel(reviewState(stdout), {busy: false});
        assert.strictEqual(model.degraded, true);
        assert.strictEqual(model.entryCount, 0);
        assert.strictEqual(model.current, undefined);
        assert.strictEqual(model.position, undefined);
        assert.strictEqual(model.why, undefined);
    });

    it("una situación que no es review no lleva nada de la review, y sí el stderr", () => {
        const state: ReviewState = {
            situation: "out-of-range",
            entries: [],
            branches: [],
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
        const state: ReviewState = {
            situation: "error",
            entries: [],
            branches: [],
            stderr: "  \n",
        };
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
        assert.strictEqual(entryPickLabel(entries[1], 2).description, "current");
        assert.strictEqual(entryPickLabel(entries[2], 2).description, "key");
    });

    it("una entrada actual Y esencial lleva las dos marcas", () => {
        assert.strictEqual(entryPickLabel(entries[2], 3).description, "current · key");
    });

    it("una entrada sin marcas no lleva descripción", () => {
        assert.strictEqual(entryPickLabel(entries[0], 2).description, "");
    });

    it("una entrada no anotada lleva la marca uncovered", () => {
        assert.strictEqual(entryPickLabel(entries[3], 2).description, "uncovered");
    });

    it("en step la marca es la de ediciones guardadas", () => {
        const step = parsePorcelain("state\tr\ts\tt\tstep\tnone\t1\t1\t1\tabc1234\nentry\t1\tabc1234\t1\n");
        assert.strictEqual(entryPickLabel(step.entries[0], 2).description, "banked edits");
        assert.strictEqual(entryPickLabel(step.entries[0], 2).label, "01  abc1234");
    });

    it("posiciones de dos dígitos no se rellenan", () => {
        const wide = parsePorcelain("state\tr\ts\tt\tstep\tnone\t10\t10\t10\tabc\nentry\t10\tabc1234\t0\n");
        assert.strictEqual(entryPickLabel(wide.entries[0], 10).label, "10  abc1234");
    });
});

/**
 * El inventario del estado vacio. Igual que arriba, las filas salen de salida
 * `list --porcelain` real pasada por el parser: escribir los records a mano
 * probaria la proyeccion contra una copia del contrato.
 */
function inventoryState(rows: string[]): ReviewState {
    return {
        situation: "no-review",
        entries: [],
        branches: parseListPorcelain(rows.join("\n") + "\n"),
    };
}

const INVENTORY = [
    "branch\treview/feature/checkout\t0\t0\t0\twalk\t3\t9",
    "branch\treview/fix/quoting\t0\t0\t0\twhole",
    "branch\treview/orphan\t0\t1\t1",
    "branch\treview-saved/perf/index\t1\t0\t0\tstep\t2\t4",
    "branch\treview-saved/fix/quoting\t1\t0\t0\twalk\t1\t6",
];

describe("buildPanelModel — inventario", () => {
    it("proyecta cada fila con su modo y su posicion registrada, en el orden de la CLI", () => {
        const model = buildPanelModel(inventoryState(INVENTORY), {busy: false});
        assert.deepStrictEqual(
            model.reviews.map((r) => r.name),
            [
                "review/feature/checkout",
                "review/fix/quoting",
                "review/orphan",
                "review-saved/perf/index",
                "review-saved/fix/quoting",
            ]
        );
        assert.deepStrictEqual(model.reviews[0], {
            name: "review/feature/checkout",
            saved: false,
            current: false,
            orphan: false,
            mode: "walk",
            position: 3,
            total: 9,
            resumable: false,
        });
        assert.strictEqual(model.reviews[1].mode, "whole");
        assert.strictEqual(model.reviews[1].position, undefined);
    });

    it("solo una guardada es resumible; una activa nunca lo es", () => {
        const model = buildPanelModel(inventoryState(INVENTORY), {busy: false});
        assert.strictEqual(model.reviews[0].resumable, false, "activa: no hay verbo para saltar");
        assert.strictEqual(model.reviews[3].resumable, true, "guardada sin activa gemela");
    });

    it("una guardada con su activa gemela no se ofrece: el verbo la rechazaria", () => {
        // review/fix/quoting esta activa, asi que continue fallaria con
        // "is already active" sobre review-saved/fix/quoting.
        const model = buildPanelModel(inventoryState(INVENTORY), {busy: false});
        const twin = model.reviews[4];
        assert.strictEqual(twin.name, "review-saved/fix/quoting");
        assert.strictEqual(twin.saved, true);
        assert.strictEqual(twin.resumable, false);
    });

    it("una huerfana se lista marcada y sin accion", () => {
        const model = buildPanelModel(inventoryState(INVENTORY), {busy: false});
        const orphan = model.reviews[2];
        assert.strictEqual(orphan.orphan, true);
        assert.strictEqual(orphan.current, true);
        assert.strictEqual(orphan.mode, undefined);
        assert.strictEqual(orphan.resumable, false);
    });

    it("una guardada huerfana tampoco se ofrece", () => {
        const model = buildPanelModel(
            inventoryState(["branch\treview-saved/rota\t1\t0\t1"]),
            {busy: false}
        );
        assert.strictEqual(model.reviews[0].saved, true);
        assert.strictEqual(model.reviews[0].orphan, true);
        assert.strictEqual(model.reviews[0].resumable, false);
    });

    it("una situacion que no es no-review no lleva inventario", () => {
        const model = buildPanelModel(reviewState(WALK), {busy: false});
        assert.deepStrictEqual(model.reviews, []);
    });
});

describe("resumableSourceAt", () => {
    const branches = parseListPorcelain(INVENTORY.join("\n") + "\n");

    it("devuelve el source sin prefijo de la fila resumible", () => {
        assert.strictEqual(resumableSourceAt(branches, 3), "perf/index");
    });

    it("no resuelve una activa, una huerfana ni una guardada bloqueada", () => {
        assert.strictEqual(resumableSourceAt(branches, 0), undefined, "activa");
        assert.strictEqual(resumableSourceAt(branches, 2), undefined, "huerfana");
        assert.strictEqual(resumableSourceAt(branches, 4), undefined, "con activa gemela");
    });

    it("un indice fuera de rango o que no es entero no resuelve nada", () => {
        for (const index of [-1, 5, 99, 1.5, NaN, "3", "perf/index", null, undefined, {}]) {
            assert.strictEqual(
                resumableSourceAt(branches, index),
                undefined,
                `el indice ${String(index)} no deberia resolver`
            );
        }
    });

    it("sobre un inventario vacio no resuelve nada", () => {
        assert.strictEqual(resumableSourceAt([], 0), undefined);
    });
});
