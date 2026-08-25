import * as assert from "node:assert";
import {
    advanceDraftFlow,
    DraftFlowState,
    initialDraftFlowState,
    offersIncludeKeys,
    sameDraftFile,
} from "../../src/review/draftFlow";

describe("initialDraftFlowState", () => {
    it("create arranca creando el borrador; resume ya termino", () => {
        assert.deepStrictEqual(initialDraftFlowState("create"), {kind: "create", force: false});
        // draft-resume no invoca nada: el archivo se usa tal cual esta.
        assert.deepStrictEqual(initialDraftFlowState("resume"), {kind: "done"});
    });

    it("update es el mismo comando que create; start-over es el que lleva --force", () => {
        // El verbo actualiza en vez de negarse, asi que reconciliar no necesita
        // ningun flag: lo unico que distingue a las dos ramas del picker es que
        // una tira lo escrito y la otra no.
        assert.deepStrictEqual(initialDraftFlowState("update"), {kind: "create", force: false});
        assert.deepStrictEqual(initialDraftFlowState("start-over"), {kind: "create", force: true});
    });
});

describe("advanceDraftFlow", () => {
    it("crear en verde termina el asistente, sin abrir ni esperar nada", () => {
        const end = advanceDraftFlow(initialDraftFlowState("create"), {kind: "created", ok: true});
        assert.deepStrictEqual(end, {kind: "done"});
    });

    it("la maquina tiene tres estados y ninguno espera", () => {
        // El bucle de 011 (open / wait / build / reload / pickKeys) se retiro
        // entero: lo que hacia vive en el panel, sobre un estado que sobrevive a
        // cerrar el editor. Si alguno volviera, este test lo dice.
        const kinds = new Set<string>();
        kinds.add(initialDraftFlowState("create").kind);
        kinds.add(initialDraftFlowState("resume").kind);
        kinds.add(advanceDraftFlow({kind: "create", force: false}, {kind: "created", ok: true}).kind);
        kinds.add(advanceDraftFlow({kind: "create", force: false}, {kind: "created", ok: false}).kind);
        assert.deepStrictEqual([...kinds].sort(), ["back", "create", "done"]);
    });

    it("un fallo de creacion vuelve atras con el motivo de la CLI", () => {
        const state = advanceDraftFlow(
            {kind: "create", force: false},
            {kind: "created", ok: false, error: "a draft already exists; use --force"}
        );
        assert.deepStrictEqual(state, {kind: "back", error: "a draft already exists; use --force"});
    });

    it("un fallo sin stderr vuelve atras igual, sin inventar un motivo", () => {
        assert.deepStrictEqual(
            advanceDraftFlow({kind: "create", force: false}, {kind: "created", ok: false}),
            {kind: "back"}
        );
    });

    it("done y back son terminales", () => {
        const done: DraftFlowState = {kind: "done"};
        assert.deepStrictEqual(advanceDraftFlow(done, {kind: "created", ok: true}), done);
        const back: DraftFlowState = {kind: "back", error: "boom"};
        assert.deepStrictEqual(advanceDraftFlow(back, {kind: "created", ok: true}), back);
    });
});

describe("offersIncludeKeys", () => {
    it("solo cuando la CLI reporta keys", () => {
        assert.strictEqual(offersIncludeKeys(undefined), false);
        assert.strictEqual(offersIncludeKeys([]), false);
        assert.strictEqual(offersIncludeKeys([{id: "walk", rank: "recommended"}]), false);
        assert.strictEqual(
            offersIncludeKeys([{id: "walk", rank: "recommended"}, {id: "keys", rank: "available"}]),
            true
        );
    });
});

describe("sameDraftFile", () => {
    it("en Windows compara sin distinguir separador ni caja", () => {
        assert.strictEqual(
            sameDraftFile(
                "C:\\repo\\.git\\review-walkthrough\\feature\\x.md",
                "c:/repo/.git/review-walkthrough/feature/x.md",
                "win32"
            ),
            true
        );
    });

    it("en POSIX la caja importa", () => {
        assert.strictEqual(
            sameDraftFile("/repo/.git/review-walkthrough/x.md", "/repo/.git/review-walkthrough/X.md", "linux"),
            false
        );
        assert.strictEqual(
            sameDraftFile("/repo/.git/review-walkthrough/x.md", "/repo/.git/review-walkthrough/x.md", "linux"),
            true
        );
    });
});
