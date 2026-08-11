import * as assert from "node:assert";
import {ReadingOffer} from "../../src/cli/configPorcelain";
import {
    advanceDraftFlow,
    DraftFlowState,
    draftWaitMessage,
    gitdirFromLink,
    initialDraftFlowState,
    offersIncludeKeys,
    sameDraftFile,
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
            {
                kind: "offers",
                offers: [{id: "walk", rank: "recommended"}, {id: "step", rank: "available"}]
            },
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
        const back = advanceDraftFlow({kind: "pickKeys"}, {
            kind: "keysPicked",
            keysOnly: undefined
        });
        assert.deepStrictEqual(back, {kind: "back"});
    });

    it("un build fallido vuelve al aviso con el motivo, y reintenta sin limite", () => {
        let state = run(initialDraftFlowState("resume"), [
            {kind: "opened"},
            {kind: "continue"},
            {kind: "built", ok: false, error: "entry 3 still has the placeholder why"},
        ]);
        assert.deepStrictEqual(state, {
            kind: "wait",
            error: "entry 3 still has the placeholder why"
        });

        // Segundo intento: el aviso vuelve a llevar a build, y otro fallo
        // vuelve a dejarlo disponible con el error nuevo.
        state = run(state, [{kind: "continue"}, {
            kind: "built",
            ok: false,
            error: "duplicate entry"
        }]);
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

describe("draftWaitMessage", () => {
    it("pide llenar el borrador cuando quedo a la vista", () => {
        assert.strictEqual(
            draftWaitMessage("feature/x", undefined, undefined),
            "Fill in the reading order for feature/x, then continue."
        );
        assert.strictEqual(
            draftWaitMessage("feature/x", "no entries found", undefined),
            "The draft is not valid yet: no entries found"
        );
    });

    it("dice donde quedo el archivo cuando el editor no pudo abrirlo", () => {
        // El caso real: el workspace es una subcarpeta de un monorepo, <cwd>/.git
        // no existe, el borrador se escribio igual y la ruta solo va por el stdout
        // de la CLI, que ningun cliente muestra.
        assert.strictEqual(
            draftWaitMessage("feature/x", undefined, {file: "/repo/.git/review-walkthrough/feature/x.md"}),
            "Fill in the reading order for feature/x, then continue. It could not be opened here" +
            " — the draft is at /repo/.git/review-walkthrough/feature/x.md."
        );
        // Y sigue diciendolo cuando el aviso vuelve con el motivo de un rechazo.
        assert.strictEqual(
            draftWaitMessage("feature/x", "no entries found", {file: "/repo/.git/review-walkthrough/feature/x.md"}),
            "The draft is not valid yet: no entries found It could not be opened here" +
            " — the draft is at /repo/.git/review-walkthrough/feature/x.md."
        );
    });

    it("nombra el archivo relativo cuando ni la ruta se pudo armar", () => {
        assert.strictEqual(
            draftWaitMessage("feature/x", undefined, {file: undefined}),
            "Fill in the reading order for feature/x, then continue. It could not be opened here" +
            " — look for review-walkthrough/feature/x.md inside this repository's git directory."
        );
    });
});

describe("sameDraftFile", () => {
    it("empareja la ruta armada con la que devuelve el editor", () => {
        assert.strictEqual(
            sameDraftFile("/repo/.git/review-walkthrough/feature/x.md", "/repo/.git/review-walkthrough/feature/x.md", "linux"),
            true
        );
        assert.strictEqual(
            sameDraftFile("/repo/.git/review-walkthrough/feature/x.md", "/repo/.git/review-walkthrough/feature/y.md", "linux"),
            false
        );
    });

    it("en Windows ignora la caja y el separador; en Linux no", () => {
        // Es el caso que decide si el borrador se guarda: path.join deja
        // "C:\repo\..." y Uri.file devuelve "c:\repo\...", asi que un ===
        // no encuentra el documento abierto y --build lee el archivo sin
        // guardar. En Linux la caja distingue archivos de verdad.
        const built = "C:\\repo\\.git\\review-walkthrough\\feature\\x.md";
        const fromEditor = "c:/repo/.git/review-walkthrough/feature/x.md";
        assert.strictEqual(sameDraftFile(built, fromEditor, "win32"), true);
        assert.strictEqual(sameDraftFile("/repo/A.md", "/repo/a.md", "linux"), false);
    });
});
