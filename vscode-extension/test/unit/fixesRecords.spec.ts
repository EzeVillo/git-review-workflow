import * as assert from "node:assert";
import {parseListFixes} from "../../src/cli/porcelain";
import {argsForHousekeeping, confirmCopyFor} from "../../src/review/housekeeping";
import {buildPanelModel} from "../../src/views/panelModel";
import type {ReviewState} from "../../src/review/state";

const TAB = "\t";
const row = (...fields: string[]): string => fields.join(TAB);

const INPUTS = {busy: false, cliMissing: false} as never;

describe("registro fixes de list --porcelain", () => {
    it("parsea una fila por rama, en el orden de la CLI", () => {
        const out = [
            row("branch", "review/feature/x", "0", "1", "0", "whole"),
            row("fixes", "review-fixes/feature/x", "0", "1", "empty"),
            row("fixes", "review-fixes/feature/y", "1", "0", "unmerged"),
            "",
        ].join("\n");
        assert.deepStrictEqual(parseListFixes(out), [
            {name: "review-fixes/feature/x", current: false, session: true, state: "empty"},
            {name: "review-fixes/feature/y", current: true, session: false, state: "unmerged"},
        ]);
    });

    it("un estado que no entendemos se lee como unknown, nunca como uno de los tres", () => {
        // El badge de esta fila es lo unico que separa tirar una rama vacia de
        // tirar trabajo sin pushear: ante la duda, la respuesta es "no se sabe".
        const out = row("fixes", "review-fixes/feature/x", "0", "0", "brand-new-state") + "\n";
        assert.deepStrictEqual(parseListFixes(out), [
            {name: "review-fixes/feature/x", current: false, session: false, state: "unknown"},
        ]);
    });

    it("ignora las lineas que no son suyas y las filas sin nombre", () => {
        const out = [
            row("branch", "review/feature/x", "0", "0", "0", "walk", "2", "5"),
            row("branch-draft", "review/feature/x"),
            row("finish", "review/feature/x", "pending", "0"),
            row("fixes", "", "0", "0", "empty"),
            "",
        ].join("\n");
        assert.deepStrictEqual(parseListFixes(out), []);
    });
});

describe("la seccion Edits you extracted en el modelo", () => {
    const stateWith = (fixes: ReturnType<typeof parseListFixes>): ReviewState => ({
        situation: "no-review",
        entries: [],
        branches: [],
        fixes,
    });

    it("proyecta las filas tal como llegaron, sin filtrar la current", () => {
        const fixes = parseListFixes([
            row("fixes", "review-fixes/feature/x", "1", "1", "empty"),
            row("fixes", "review-fixes/feature/y", "0", "0", "merged"),
            "",
        ].join("\n"));
        const model = buildPanelModel(stateWith(fixes), INPUTS);
        // La current no se puede borrar, pero esconderla dejaria una rama que
        // existe sin ninguna superficie que la nombre.
        assert.deepStrictEqual(model.fixes, [
            {name: "review-fixes/feature/x", current: true, session: true, state: "empty"},
            {name: "review-fixes/feature/y", current: false, session: false, state: "merged"},
        ]);
    });

    it("dentro de una review no hay seccion, aunque el estado traiga filas", () => {
        const fixes = parseListFixes(row("fixes", "review-fixes/feature/x", "0", "0", "empty") + "\n");
        const model = buildPanelModel({...stateWith(fixes), situation: "review"}, INPUTS);
        assert.deepStrictEqual(model.fixes, []);
    });
});

describe("clean --fixes-only", () => {
    it("lleva el flag delante del nombre, como --keep-fixes", () => {
        assert.deepStrictEqual(
            argsForHousekeeping({kind: "clean-fixes-only", source: "feature/x"}),
            ["--fixes-only", "feature/x"]
        );
    });

    it("sin source no arma argv: un clean sin rama se lleva todo el repositorio", () => {
        assert.throws(() => argsForHousekeeping({kind: "clean-fixes-only"}));
    });

    it("la confirmacion dice cuanto cuesta, con el estado que reporto la CLI", () => {
        const unmerged = confirmCopyFor({
            kind: "clean-fixes-only",
            source: "feature/x",
            fixesState: "unmerged",
            session: false,
        });
        assert.ok(unmerged.detail.includes("git review clean --fixes-only feature/x"));
        assert.ok(unmerged.detail.includes("the base branch does not have"));
        assert.ok(!unmerged.detail.includes("left standing"));

        const empty = confirmCopyFor({
            kind: "clean-fixes-only",
            source: "feature/x",
            fixesState: "empty",
            session: true,
        });
        assert.ok(empty.detail.includes("no work of yours is lost"));
        // La sesion se nombra solo cuando existe.
        assert.ok(empty.detail.includes("review/feature/x is left standing"));
    });

    it("sin estado reportado no afirma nada sobre la base", () => {
        const copy = confirmCopyFor({kind: "clean-fixes-only", source: "feature/x"});
        assert.ok(copy.detail.includes("cannot tell"));
        assert.strictEqual(copy.button, "Discard");
    });
});
