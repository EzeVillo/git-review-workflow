import * as assert from "node:assert";
import {
    advanceDraftFlow,
    draftOutcomeMessage,
    DraftFlowState,
    DraftStep,
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

    it("update es el mismo comando que create, sin ningun flag", () => {
        // El verbo actualiza en vez de negarse, asi que reconciliar no necesita
        // ningun flag: conserva cada entrada cuyo archivo sigue en rango y suma
        // las que entraron.
        assert.deepStrictEqual(initialDraftFlowState("update"), {kind: "create", force: false});
    });

    it("ningun paso del asistente llega a --force", () => {
        // start-over se retiro: era la otra mitad de un modal que preguntaba, en
        // cada borrador ya usado, si reconciliar o empezar de cero -- una duda
        // que ahora contesta la CLI eligiendo que oferta emitir. Empezar de cero
        // es lo unico que destruye prosa escrita a mano, y del lado del revisor
        // el archivo no esta en git, asi que no vuelve a un paso por el que se
        // pasa de largo: vive en Discard, que confirma.
        const steps: DraftStep[] = ["create", "resume", "update"];
        for (const step of steps) {
            const state = initialDraftFlowState(step);
            if (state.kind === "create") {
                assert.strictEqual(state.force, false, `${step} no debe forzar`);
            }
        }
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

describe("draftOutcomeMessage", () => {
    // El caso que motivo la funcion: apretar la oferta y no ver nada. El
    // resultado del verbo viaja por stdout y este camino leia solo stderr.
    it("el resultado del verbo no puede perderse: viene por stdout", () => {
        const out = "updated $GIT_DIR/review-walkthrough/feature/x.md: 1 kept, 1 added, 0 dropped\n";
        assert.strictEqual(
            draftOutcomeMessage(out, ""),
            "updated $GIT_DIR/review-walkthrough/feature/x.md: 1 kept, 1 added, 0 dropped"
        );
    });

    it("con nota, el resultado va primero y la nota despues", () => {
        const msg = draftOutcomeMessage(
            "updated the file: 2 kept, 0 added, 0 dropped\n",
            "note: no authoring guide. Create one with:\n        git review walkthrough guide\n"
        );
        assert.strictEqual(
            msg,
            "updated the file: 2 kept, 0 added, 0 dropped — " +
            "note: no authoring guide. Create one with: git review walkthrough guide"
        );
        // El separador va ENTRE los dos tramos, nunca adentro de uno: cada uno
        // se aplana por su cuenta antes de unirlos.
        assert.strictEqual(msg.split(" — ").length, 2);
    });

    it("un stream vacio no deja separador colgando", () => {
        assert.strictEqual(draftOutcomeMessage("", "note: solo la nota"), "note: solo la nota");
        assert.strictEqual(draftOutcomeMessage("", ""), "");
        assert.strictEqual(draftOutcomeMessage("  \n \n", "\n"), "");
    });
});
