import * as assert from "node:assert";
import {ReadingOffer} from "../../src/cli/configPorcelain";
import {
    advanceDraftFlow,
    DraftFlowState,
    gitdirFromLink,
    initialDraftFlowState,
    offersIncludeKeys,
} from "../../src/review/draftFlow";

/** Aplica una secuencia de eventos desde un estado inicial. */
function run(start: DraftFlowState, events: Parameters<typeof advanceDraftFlow>[1][]): DraftFlowState {
    return events.reduce(advanceDraftFlow, start);
}

describe("initialDraftFlowState", () => {
    it("create arranca creando el borrador; resume lo abre sin recrearlo", () => {
        assert.deepStrictEqual(initialDraftFlowState("create"), {kind: "create"});
        assert.deepStrictEqual(initialDraftFlowState("resume"), {kind: "open"});
    });
});

describe("advanceDraftFlow", () => {
    it("camino completo sin esenciales: crear, abrir, esperar, validar, walk", () => {
        const end = run(initialDraftFlowState("create"), [
            {kind: "created", ok: true},
            {kind: "opened"},
            {kind: "continue"},
            {kind: "built", ok: true},
            {kind: "offers", offers: [{id: "walk", rank: "recommended"}, {id: "step", rank: "available"}]},
        ]);
        assert.deepStrictEqual(end, {kind: "done", layout: "walk"});
    });

    it("con keys entre las ofertas pregunta antes de decidir el recorrido", () => {
        const offers: ReadingOffer[] = [
            {id: "walk", rank: "recommended"},
            {id: "keys", rank: "available"},
        ];
        const asked = run(initialDraftFlowState("resume"), [
            {kind: "opened"},
            {kind: "continue"},
            {kind: "built", ok: true},
            {kind: "offers", offers},
        ]);
        assert.deepStrictEqual(asked, {kind: "pickKeys"});

        assert.deepStrictEqual(advanceDraftFlow(asked, {kind: "keysPicked", keysOnly: true}), {
            kind: "done",
            layout: "keys",
        });
        assert.deepStrictEqual(advanceDraftFlow(asked, {kind: "keysPicked", keysOnly: false}), {
            kind: "done",
            layout: "walk",
        });
    });

    it("cerrar el selector de esenciales vuelve al paso de forma de lectura, sin error", () => {
        const back = advanceDraftFlow({kind: "pickKeys"}, {kind: "keysPicked", keysOnly: undefined});
        assert.deepStrictEqual(back, {kind: "back"});
    });

    it("un build fallido vuelve al aviso con el motivo, y reintenta sin limite", () => {
        let state = run(initialDraftFlowState("resume"), [
            {kind: "opened"},
            {kind: "continue"},
            {kind: "built", ok: false, error: "entry 3 still has the placeholder why"},
        ]);
        assert.deepStrictEqual(state, {kind: "wait", error: "entry 3 still has the placeholder why"});

        // Segundo intento: el aviso vuelve a llevar a build, y otro fallo
        // vuelve a dejarlo disponible con el error nuevo.
        state = run(state, [{kind: "continue"}, {kind: "built", ok: false, error: "duplicate entry"}]);
        assert.deepStrictEqual(state, {kind: "wait", error: "duplicate entry"});

        // Tercero, en verde: el error no queda pegado.
        state = run(state, [{kind: "continue"}, {kind: "built", ok: true}]);
        assert.deepStrictEqual(state, {kind: "reload"});
    });

    it("Cancel en el aviso vuelve atras sin error (el borrador sobrevive)", () => {
        const state = run(initialDraftFlowState("resume"), [{kind: "opened"}, {kind: "cancel"}]);
        assert.deepStrictEqual(state, {kind: "back"});
        assert.ok(!("error" in state) || state.error === undefined);
    });

    it("descartar el aviso no es Cancel: el bucle se queda esperando", () => {
        // Cerrar la notificacion con la X mientras se edita el borrador — que es
        // lo que el aviso pide hacer — no es una respuesta a la pregunta.
        const waiting = run(initialDraftFlowState("resume"), [{kind: "opened"}]);
        assert.deepStrictEqual(waiting, {kind: "wait"});
        assert.deepStrictEqual(advanceDraftFlow(waiting, {kind: "dismiss"}), {kind: "wait"});

        // Con un rechazo a cuestas, descartar conserva el motivo: el aviso
        // siguiente lo vuelve a mostrar en vez de perderlo.
        const failed: DraftFlowState = {kind: "wait", error: "duplicate entry"};
        assert.deepStrictEqual(advanceDraftFlow(failed, {kind: "dismiss"}), failed);

        // Y desde ahi las dos salidas siguen siendo las de siempre.
        assert.deepStrictEqual(advanceDraftFlow(failed, {kind: "cancel"}), {kind: "back"});
        assert.deepStrictEqual(advanceDraftFlow(failed, {kind: "continue"}), {kind: "build"});
    });

    it("si la creacion falla no se espera nada: vuelve atras con el motivo", () => {
        const state = advanceDraftFlow(
            {kind: "create"},
            {kind: "created", ok: false, error: "a draft already exists; use --force"}
        );
        assert.deepStrictEqual(state, {kind: "back", error: "a draft already exists; use --force"});
    });

    it("un evento que no corresponde al estado lo deja intacto", () => {
        const waiting: DraftFlowState = {kind: "wait"};
        assert.deepStrictEqual(advanceDraftFlow(waiting, {kind: "built", ok: true}), waiting);
        assert.deepStrictEqual(advanceDraftFlow({kind: "create"}, {kind: "continue"}), {kind: "create"});
        assert.deepStrictEqual(advanceDraftFlow({kind: "open"}, {kind: "cancel"}), {kind: "open"});
    });

    it("done y back son terminales", () => {
        const done: DraftFlowState = {kind: "done", layout: "walk"};
        assert.deepStrictEqual(advanceDraftFlow(done, {kind: "cancel"}), done);
        const back: DraftFlowState = {kind: "back", error: "boom"};
        assert.deepStrictEqual(advanceDraftFlow(back, {kind: "continue"}), back);
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

describe("gitdirFromLink", () => {
    it("lee el gitdir de un .git que es archivo (worktree / submodulo)", () => {
        assert.strictEqual(
            gitdirFromLink("gitdir: /repo/.git/worktrees/wt1\n"),
            "/repo/.git/worktrees/wt1"
        );
        assert.strictEqual(gitdirFromLink("gitdir: ../.git/modules/sub"), "../.git/modules/sub");
        // CRLF y espacios de mas no deben quedar pegados al path.
        assert.strictEqual(gitdirFromLink("gitdir:   C:/repo/.git/worktrees/wt1  \r\n"), "C:/repo/.git/worktrees/wt1");
    });

    it("devuelve undefined cuando no hay linea gitdir", () => {
        assert.strictEqual(gitdirFromLink(""), undefined);
        assert.strictEqual(gitdirFromLink("ref: refs/heads/main\n"), undefined);
        assert.strictEqual(gitdirFromLink("gitdir:\n"), undefined);
    });
});
