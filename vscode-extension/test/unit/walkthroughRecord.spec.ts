import * as assert from "node:assert";
import {parseConfigPorcelain} from "../../src/cli/configPorcelain";
import {isReportedGuide} from "../../src/review/draftWatch";
import {walkthroughAgentPrompt} from "../../src/review/userCopy";
import {buildPanelModel} from "../../src/views/panelModel";

const TAB = "\t";
const row = (...fields: string[]): string => fields.join(TAB);

const WT = "/repo/.review/walkthrough.md";

describe("registro walkthrough de config --porcelain", () => {
    it("parsea estado, ruta y el par de progreso", () => {
        const out = [
            row("config", "remote", "origin"),
            row("walkthrough", "stale", WT, "10", "12"),
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.walkthrough, {
            path: WT,
            state: "stale",
            annotated: 10,
            total: 12,
        });
    });

    it("los cuatro estados se reconocen", () => {
        for (const state of ["in-sync", "stale", "unknown", "absent"] as const) {
            const result = parseConfigPorcelain(row("walkthrough", state, WT, "0", "0") + "\n");
            assert.strictEqual(result.walkthrough?.state, state);
        }
    });

    it("un estado desconocido tira la fila entera", () => {
        // Un badge inventado es peor que no dibujar el bloque.
        const result = parseConfigPorcelain(row("walkthrough", "sideways", WT, "1", "1") + "\n");
        assert.strictEqual(result.walkthrough, undefined);
    });

    it("un contador ilegible cae a 0 sin perder el estado", () => {
        // El estado es lo que decide que ofrece el bloque; perderlo por un
        // contador roto dejaria al autor sin la unica superficie que le dice que
        // su orden de lectura quedo atras.
        const result = parseConfigPorcelain(row("walkthrough", "stale", WT, "x", "-2") + "\n");
        assert.strictEqual(result.walkthrough?.state, "stale");
        assert.strictEqual(result.walkthrough?.annotated, 0);
        assert.strictEqual(result.walkthrough?.total, 0);
    });

    it("sin ruta no hay fila", () => {
        const result = parseConfigPorcelain(row("walkthrough", "stale", "", "1", "1") + "\n");
        assert.strictEqual(result.walkthrough, undefined);
    });

    it("con dos filas gana la primera", () => {
        const out = [
            row("walkthrough", "in-sync", WT, "3", "3"),
            row("walkthrough", "stale", "/otro.md", "1", "2"),
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.strictEqual(result.walkthrough?.path, WT);
        assert.strictEqual(result.walkthrough?.state, "in-sync");
    });

    it("sin registro queda ausente: es la degradacion contra una CLI anterior", () => {
        const result = parseConfigPorcelain(row("config", "remote", "origin") + "\n");
        assert.strictEqual(result.walkthrough, undefined);
    });
});

describe("proyeccion de la fila del walkthrough", () => {
    const model = (state: "in-sync" | "stale" | "unknown" | "absent", ann = 3, tot = 3) =>
        buildPanelModel(
            {
                situation: "no-review",
                branches: [],
                walkthrough: {path: WT, state, annotated: ann, total: tot},
            } as never,
            {busy: false},
        ).walkthrough;

    it("el badge dice cada estado en prosa", () => {
        assert.strictEqual(model("in-sync")?.badge, "up to date");
        assert.strictEqual(model("stale")?.badge, "may be out of date");
        assert.strictEqual(model("unknown")?.badge, "state unknown");
        assert.strictEqual(model("absent")?.badge, "none");
    });

    it("stale no afirma de mas: sugiere mirar, no dictamina", () => {
        // El veredicto es de build. Lo que la CLI compara en cada refresco es
        // barato y aproximado, asi que el badge no puede leerse como una
        // sentencia sobre un archivo que puede estar perfecto.
        assert.strictEqual(model("stale")?.badge, "may be out of date");
        assert.notStrictEqual(model("stale")?.badge, "out of date");
    });

    it("la etiqueta del boton sigue al estado, no a la deriva", () => {
        // El mismo verbo crea y actualiza; con el archivo ahi, "Create" seria una
        // promesa que la CLI no cumple. Y unknown/stale actualizan igual.
        assert.strictEqual(model("absent")?.actionLabel, "Create");
        assert.strictEqual(model("in-sync")?.actionLabel, "Update");
        assert.strictEqual(model("stale")?.actionLabel, "Update");
        assert.strictEqual(model("unknown")?.actionLabel, "Update");
    });

    it("exists apaga los dos controles de la fila", () => {
        assert.strictEqual(model("absent")?.exists, false);
        assert.strictEqual(model("unknown")?.exists, true);
    });

    it("sin registro no hay fila en el modelo", () => {
        const m = buildPanelModel({situation: "no-review", branches: []} as never, {busy: false});
        assert.strictEqual(m.walkthrough, undefined);
    });
});

describe("copy del walkthrough para un agente", () => {
    it("es un puntero al archivo, nunca la consigna", () => {
        const text = walkthroughAgentPrompt(WT);
        assert.ok(text.includes(WT));
        assert.ok(text.includes("The instructions are inside the file"));
    });

    it("dice que no se toquen las entradas ya escritas", () => {
        // Sin esto el agente reescribe de punta a punta, que es exactamente lo
        // que preservar la prosa existe para evitar.
        const text = walkthroughAgentPrompt(WT);
        assert.ok(text.includes("finished: leave them as they are"));
        assert.ok(text.includes('"## ?."'));
    });
});

describe("el guardado del walkthrough refresca", () => {
    it("dispara sobre la ruta que reporto la CLI", () => {
        const state = {walkthrough: {path: WT}};
        assert.strictEqual(isReportedGuide(state, WT, "linux"), true);
        assert.strictEqual(isReportedGuide(state, "/repo/otro.md", "linux"), false);
    });

    it("sin registro no dispara sobre nada", () => {
        assert.strictEqual(isReportedGuide({}, WT, "linux"), false);
    });
});
