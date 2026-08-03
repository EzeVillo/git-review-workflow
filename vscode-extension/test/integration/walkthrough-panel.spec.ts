import * as assert from "node:assert";
import * as fs from "node:fs";
import * as path from "node:path";
import {PathRef} from "../../src/cli/unquote";
import {entryPickLabel} from "../../src/views/panelModel";
import {getTestApi} from "./helpers/extensionApi";
import {
    abortReview,
    addWalkthrough,
    createBranchWithChanges,
    git,
    gitReview,
    sharedFixtureRepo,
    startReview,
    writeFile
} from "./helpers/fixture";

function displayOf(id: string | PathRef): string {
    return typeof id === "string" ? id : id.display;
}

describe("US1: ver donde estoy en el walkthrough", function () {
    this.timeout(60000);
    const repo = sharedFixtureRepo();

    afterEach(() => {
        abortReview(repo);
    });

    it("lista las entradas en el orden del walkthrough, marca la actual y las esenciales, agrupa lo no cubierto (quickstart §1)", async () => {
        const branch = "us1-walk";
        createBranchWithChanges(repo, branch, {
            "src/a.ts": "a\n",
            "src/b.ts": "b\n",
            "src/c.ts": "c\n",
            "src/d.ts": "d\n",
            "src/e.ts": "e\n",
            "src/f.ts": "f\n",
            "src/g.ts": "g\n",
        });
        addWalkthrough(repo, branch, [
            {path: "src/a.ts", why: "explica a"},
            {path: "src/b.ts", why: "explica b"},
            {path: "src/c.ts", why: "explica c", key: true},
            {path: "src/d.ts", why: "explica d"},
            {path: "src/e.ts", why: "explica e"},
            {path: "src/f.ts", why: "explica f"},
            {path: "src/g.ts", why: "explica g"},
        ]);
        // Archivos que llegan DESPUÉS de construir el walkthrough: el PR los trae
        // pero nadie los anotó todavía — es el caso real de "sin cobertura"
        // (walkthrough build exige cobertura completa del diff al momento de
        // construirlo, así que no puede haber un archivo sin entrada ahí).
        git(["checkout", branch], repo.dir);
        writeFile(repo, "src/uncovered1.ts", "u1\n");
        writeFile(repo, "src/uncovered2.ts", "u2\n");
        git(["add", "."], repo.dir);
        git(["commit", "-m", "more changes after the walkthrough"], repo.dir);
        git(["checkout", "main"], repo.dir);

        startReview(repo, branch);
        gitReview(["next"], repo.dir); // cursor: 1 -> 2

        const api = await getTestApi();
        const state = await api.refresh();

        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "walk");
        assert.strictEqual(state.state?.position, 2);
        assert.strictEqual(state.state?.total, 7);
        assert.strictEqual(state.entries.length, 7);
        assert.strictEqual(state.uncovered.length, 2);

        const order = state.entries.map((e) => displayOf(e.id));
        assert.deepStrictEqual(order, ["src/a.ts", "src/b.ts", "src/c.ts", "src/d.ts", "src/e.ts", "src/f.ts", "src/g.ts"]);

        const essentialFlags = state.entries.map((e) => e.essential);
        assert.deepStrictEqual(essentialFlags, [false, false, true, false, false, false, false]);

        // El panel: la entrada actual es el contenido, la secuencia y lo no
        // cubierto son accesos separados con su cuenta (FR-005, FR-005a, FR-008).
        const model = await api.getPanelModel();
        assert.strictEqual(model.situation, "review");
        assert.strictEqual(model.mode, "walk");
        assert.strictEqual(model.position, 2);
        assert.strictEqual(model.total, 7);
        assert.strictEqual(model.baseMoved, false);
        assert.strictEqual(model.degraded, false);
        assert.deepStrictEqual(model.current, {
            position: 2,
            display: "src/b.ts",
            essential: false,
            banked: false,
        });
        assert.strictEqual(model.entryCount, 7);
        assert.strictEqual(model.uncoveredCount, 2);
        assert.deepStrictEqual(model.why, {state: "present", text: "explica b\n"});

        // Lo que alimenta el QuickPick de la secuencia: orden de la CLI, la
        // actual y la esencial marcadas con texto.
        const picks = state.entries.map((entry) => entryPickLabel(entry, state.state?.position));
        assert.deepStrictEqual(picks.map((p) => p.label), [
            "01  src/a.ts",
            "02  src/b.ts",
            "03  src/c.ts",
            "04  src/d.ts",
            "05  src/e.ts",
            "06  src/f.ts",
            "07  src/g.ts",
        ]);
        assert.strictEqual(picks[1].description, "actual");
        assert.strictEqual(picks[2].description, "esencial");

        const uncoveredNames = state.uncovered.map((u) => u.id.display).sort();
        assert.deepStrictEqual(uncoveredNames, ["src/uncovered1.ts", "src/uncovered2.ts"]);
    });

    it("mode = whole sin walkthrough: sin secuencia ni entrada actual, y sin error (US1 escenario 3)", async () => {
        const branch = "us1-whole";
        createBranchWithChanges(repo, branch, {"src/x.ts": "x\n"});
        startReview(repo, branch, ["--no-walk"]);

        const api = await getTestApi();
        const state = await api.refresh();

        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "whole");
        assert.strictEqual(state.state?.walkthrough, "none");
        assert.strictEqual(state.entries.length, 0);

        // Sin walkthrough el panel no ofrece secuencia ni navegación (FR-026),
        // y no es un error.
        const model = await api.getPanelModel();
        assert.strictEqual(model.situation, "review");
        assert.strictEqual(model.mode, "whole");
        assert.strictEqual(model.entryCount, 0);
        assert.strictEqual(model.current, undefined);
        assert.strictEqual(model.why, undefined);
        assert.strictEqual(model.degraded, false);
        assert.strictEqual(model.stderr, undefined);
    });

    it("walkthrough degradado: la review sigue usable y se informa el motivo (US1 escenario 4)", async () => {
        const branch = "us1-degraded";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        addWalkthrough(repo, branch, [{path: "src/a.ts", why: "explica a"}]);

        // Un commit posterior deja a.ts idéntico a la base (desaparece del diff)
        // mientras el walkthrough construido sigue mencionándolo: la secuencia
        // derivada queda vacía y la review degrada a whole.
        git(["checkout", branch], repo.dir);
        fs.rmSync(path.join(repo.dir, "src", "a.ts"));
        writeFile(repo, "src/other.ts", "other\n");
        git(["add", "-A"], repo.dir);
        git(["commit", "-m", "revert a.ts, add other.ts"], repo.dir);
        git(["checkout", "main"], repo.dir);

        startReview(repo, branch);

        const api = await getTestApi();
        const state = await api.refresh();

        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "whole");
        assert.strictEqual(state.state?.walkthrough, "degraded");
        assert.strictEqual(state.entries.length, 0);
        assert.strictEqual(state.uncovered.length, 1);
        assert.strictEqual(state.uncovered[0].id.display, "src/other.ts");

        // Degradado se informa (FR-010) y la review sigue usable: los archivos
        // del rango siguen alcanzables desde el panel.
        const model = await api.getPanelModel();
        assert.strictEqual(model.situation, "review");
        assert.strictEqual(model.degraded, true);
        assert.strictEqual(model.uncoveredCount, 1);
        assert.strictEqual(model.entryCount, 0);
    });
});
