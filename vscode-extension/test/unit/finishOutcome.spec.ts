import * as assert from "node:assert";
import {parseListPorcelain} from "../../src/cli/porcelain";
import {finishOutcome} from "../../src/review/finishOutcome";
// `import type`: `review/state.ts` importa `vscode`, que no existe fuera del
// host — el tipo se borra en compilación y el módulo no llega a cargarse.
import type {ReviewState} from "../../src/review/state";

/**
 * T050a (005 US3): la regla que decide el mensaje de `finishReview.ts` tras un
 * `finish` con exit 0 — "sin ediciones" cuando el refresco posterior no trae
 * un cierre `pending` para esa review, "cierre pendiente" cuando sí. Pura y
 * sin `stdout`/`stderr` de ningún verbo (contracts/cli-invocation.md § "no
 * parsear la salida humana"): lo único que puede mover la aguja es el
 * `ReviewState` ya refrescado.
 */
describe("finishOutcome", () => {
    it("sin registro finish pending para la rama, el resultado es sin ediciones", () => {
        const state: ReviewState = {
            situation: "no-review",
            entries: [],
            branches: parseListPorcelain("branch\treview/feature/checkout\t0\t0\t0\twhole\n"),
        };
        assert.strictEqual(finishOutcome(state, "review/feature/checkout"), "no-edits");
    });

    it("con un registro finish pending para la rama, el resultado es cierre pendiente", () => {
        const state: ReviewState = {
            situation: "finish-pending",
            entries: [],
            branches: parseListPorcelain(
                ["branch\treview/feature/checkout\t0\t0\t0\twhole", "finish\treview/feature/checkout\tpending\t0", ""].join(
                    "\n"
                )
            ),
        };
        assert.strictEqual(finishOutcome(state, "review/feature/checkout"), "pending");
    });

    it("un finish pending de OTRA review no cuenta: se busca por nombre exacto", () => {
        const state: ReviewState = {
            situation: "finish-pending",
            entries: [],
            branches: parseListPorcelain(
                ["branch\treview/other\t0\t0\t0\twhole", "finish\treview/other\tpending\t0", ""].join("\n")
            ),
        };
        assert.strictEqual(finishOutcome(state, "review/feature/checkout"), "no-edits");
    });

    it("un finish conflict (no pending) para la misma rama tampoco cuenta como cierre pendiente", () => {
        // No debería darse en la práctica (un finish exitoso nunca deja
        // conflict), pero la regla es "pending", no "cualquier finish".
        const state: ReviewState = {
            situation: "no-review",
            entries: [],
            branches: parseListPorcelain(
                ["branch\treview/feature/checkout\t0\t0\t0\twhole", "finish\treview/feature/checkout\tconflict\t0", ""].join(
                    "\n"
                )
            ),
        };
        assert.strictEqual(finishOutcome(state, "review/feature/checkout"), "no-edits");
    });

    it("no recibe stdout ni stderr: la firma sólo toma el ReviewState refrescado y el nombre de la rama", () => {
        assert.strictEqual(finishOutcome.length, 2);
    });
});
