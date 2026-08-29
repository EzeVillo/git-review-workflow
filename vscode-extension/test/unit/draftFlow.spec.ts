import * as assert from "node:assert";
import {
    advanceDraftFlow,
    DraftFlowState,
    DraftStep,
    initialDraftFlowState,
    offersIncludeKeys,
    parseMergedRecord,
    sameDraftFile,
} from "../../src/review/draftFlow";
import {draftUpdated} from "../../src/review/userCopy";

describe("initialDraftFlowState", () => {
    it("create arranca creando el borrador; resume ya termino", () => {
        assert.deepStrictEqual(initialDraftFlowState("create"), {kind: "create", force: false, update: false});
        // draft-resume no invoca nada: el archivo se usa tal cual esta.
        assert.deepStrictEqual(initialDraftFlowState("resume"), {kind: "done"});
    });

    it("update es el mismo comando que create, y solo cambia el acuse", () => {
        // El verbo actualiza en vez de negarse, asi que reconciliar no necesita
        // ningun flag: conserva cada entrada cuyo archivo sigue en rango y suma
        // las que entraron. `update` no toca el argv -- decide QUE SE DICE
        // despues: un update contesta "N kept, M added, K dropped", que es lo
        // unico que el panel no puede mostrar, y un create no agrega nada a la
        // fila que el refresco acaba de dibujar.
        assert.deepStrictEqual(initialDraftFlowState("update"), {kind: "create", force: false, update: true});
        assert.deepStrictEqual(initialDraftFlowState("create"), {kind: "create", force: false, update: false});
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
        kinds.add(advanceDraftFlow({kind: "create", force: false, update: false}, {kind: "created", ok: true}).kind);
        kinds.add(advanceDraftFlow({kind: "create", force: false, update: false}, {kind: "created", ok: false}).kind);
        assert.deepStrictEqual([...kinds].sort(), ["back", "create", "done"]);
    });

    it("un fallo de creacion vuelve atras con el motivo de la CLI", () => {
        const state = advanceDraftFlow(
            {kind: "create", force: false, update: false},
            {kind: "created", ok: false, error: "a draft already exists; use --force"}
        );
        assert.deepStrictEqual(state, {kind: "back", error: "a draft already exists; use --force"});
    });

    it("un fallo sin stderr vuelve atras igual, sin inventar un motivo", () => {
        assert.deepStrictEqual(
            advanceDraftFlow({kind: "create", force: false, update: false}, {kind: "created", ok: false}),
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

describe("parseMergedRecord", () => {
    // El caso que motivo el registro: apretar la oferta y no ver nada. El
    // resultado del verbo viaja por stdout, pero leer su FRASE seria parsear
    // salida humana; los tres numeros llegan en campos.
    it("lee los tres numeros del registro", () => {
        assert.deepStrictEqual(parseMergedRecord("merged\t1\t2\t3\n"), {
            kept: 1,
            added: 2,
            dropped: 3,
        });
    });

    it("encuentra el registro entre otras lineas", () => {
        assert.deepStrictEqual(parseMergedRecord("otra\tcosa\nmerged\t0\t1\t0\n"), {
            kept: 0,
            added: 1,
            dropped: 0,
        });
    });

    // Sin registro el llamador se calla: una CLI vieja imprime la frase humana
    // y ninguna otra, y ahi la respuesta correcta es no acusar nada.
    it("sin registro devuelve undefined en vez de inventar", () => {
        assert.strictEqual(parseMergedRecord(""), undefined);
        assert.strictEqual(
            parseMergedRecord("updated /tmp/x.md: 1 kept, 2 added, 3 dropped\n"),
            undefined
        );
        // El nombre solo no alcanza: sin los tres campos no hay respuesta.
        assert.strictEqual(parseMergedRecord("merged\t1\t2\n"), undefined);
        // Ni un campo que no es un numero.
        assert.strictEqual(parseMergedRecord("merged\t1\tdos\t3\n"), undefined);
    });
});

describe("draftUpdated", () => {
    it("nombra las tres cosas cuando las tres pasaron", () => {
        assert.strictEqual(
            draftUpdated(3, 1, 2),
            "Reading order updated: 3 kept, 1 added, 2 no longer in the PR."
        );
    });

    // Los ceros no se dicen: hacer leer "0 added" para descubrir que no se
    // agrego nada es el ruido que esta frase existe para no tener.
    it("omite el cero en vez de enumerarlo", () => {
        assert.strictEqual(draftUpdated(3, 1, 0), "Reading order updated: 3 kept, 1 added.");
        assert.strictEqual(
            draftUpdated(3, 0, 2),
            "Reading order updated: 3 kept, 2 no longer in the PR."
        );
    });

    // Un update que no mueve nada es un resultado real, no un no-op: el rango
    // se corrio sin cambiar que archivos toca. Sin frase no hay ninguna senal.
    it("un update que no movio nada igual dice que paso", () => {
        assert.strictEqual(draftUpdated(4, 0, 0), "Reading order updated: nothing moved, 4 kept.");
    });

    // Ninguna de las tres frases nombra un comando ni una ruta: eso era el
    // stdout que este acuse reemplaza.
    it("no nombra comandos ni rutas", () => {
        for (const text of [draftUpdated(3, 1, 2), draftUpdated(3, 1, 0), draftUpdated(4, 0, 0)]) {
            assert.ok(!text.includes("git review"), text);
            assert.ok(!text.includes("/"), text);
        }
    });
});
