import * as assert from "node:assert";
import {ReadingOffer} from "../../src/cli/configPorcelain";
import {
    buildLayoutItems,
    effectiveOffers,
    FALLBACK_OFFERS,
    layoutSummary,
    offerConfigFlags,
} from "../../src/review/layoutOffers";

describe("effectiveOffers", () => {
    it("sin offers (CLI vieja) cae a whole+step available", () => {
        assert.deepStrictEqual(effectiveOffers(undefined), [...FALLBACK_OFFERS]);
        assert.deepStrictEqual(effectiveOffers([]), [...FALLBACK_OFFERS]);
        assert.ok(effectiveOffers(undefined).every((o) => o.rank === "available"));
        assert.ok(!effectiveOffers(undefined).some((o) => o.id === "walk" || o.id === "keys"));
    });

    it("con offers de la CLI las usa tal cual", () => {
        const offers: ReadingOffer[] = [
            {id: "walk", rank: "recommended"},
            {id: "step", rank: "available"},
        ];
        assert.deepStrictEqual(effectiveOffers(offers), offers);
    });
});

describe("buildLayoutItems", () => {
    it("solo construye items de los ids reportados", () => {
        const items = buildLayoutItems([
            {id: "walk", rank: "recommended"},
            {id: "keys", rank: "available"},
            {id: "step", rank: "available"},
            {id: "whole", rank: "available"},
        ]);
        assert.deepStrictEqual(
            items.map((i) => i.layout),
            ["walk", "keys", "step", "whole"]
        );
        assert.ok(items[0].label.includes("recommended"));
        assert.ok(items[0].description.includes("recommended"));
        assert.ok(!items[1].label.includes("recommended"), "keys no es recommended");
    });

    it("walk recommended va primero aunque el array CLI venga desordenado", () => {
        const items = buildLayoutItems([
            {id: "whole", rank: "available"},
            {id: "walk", rank: "recommended"},
            {id: "step", rank: "available"},
        ]);
        assert.strictEqual(items[0].layout, "walk");
        assert.strictEqual(items[1].layout, "step");
        assert.strictEqual(items[2].layout, "whole");
    });

    it("draft entra entre keys y step, y marca el desvio por el armado", () => {
        const items = buildLayoutItems([
            {id: "whole", rank: "available"},
            {id: "step", rank: "available"},
            {id: "draft", rank: "available"},
        ]);
        assert.deepStrictEqual(
            items.map((i) => i.layout),
            ["walk", "step", "whole"]
        );
        assert.strictEqual(items[0].draft, "create");
        assert.strictEqual(items[0].label, "Build a reading order first");
        assert.strictEqual(items[0].description, "nobody wrote one for this PR; otherwise you read the whole diff");
        // Los demas no llevan la marca: elegirlos va derecho a start.
        assert.strictEqual(items[1].draft, undefined);
        assert.strictEqual(items[2].draft, undefined);
    });

    it("sobre un borrador gastado la fila dice otra cosa", () => {
        // "pick up the one you left half-written" describe un orden a medio
        // escribir; sobre uno terminado y ya usado es falso, y lo que sigue no es
        // terminarlo sino reconciliarlo o empezar uno nuevo.
        const offers = [{id: "draft-resume", rank: "available"} as const];
        const fresh = buildLayoutItems(offers);
        const spent = buildLayoutItems(offers, true);

        assert.strictEqual(fresh[0].label, "Finish the reading order you started");
        assert.strictEqual(spent[0].label, "Reuse the reading order you wrote");
        assert.notStrictEqual(spent[0].description, fresh[0].description);
        // Lo demas de la fila no cambia: sigue siendo el camino del borrador y
        // sigue llevando al mismo layout.
        assert.strictEqual(spent[0].draft, "resume");
        assert.strictEqual(spent[0].layout, "walk");
    });

    it("el estado del borrador no toca ninguna otra fila", () => {
        const offers = [
            {id: "walk", rank: "recommended"} as const,
            {id: "step", rank: "available"} as const,
            {id: "whole", rank: "available"} as const,
        ];
        assert.deepStrictEqual(
            buildLayoutItems(offers, true).map((i) => i.label),
            buildLayoutItems(offers).map((i) => i.label)
        );
    });

    it("draft-resume convive con walk recommended, que va primero", () => {
        const items = buildLayoutItems([
            {id: "draft-resume", rank: "available"},
            {id: "walk", rank: "recommended"},
            {id: "step", rank: "available"},
        ]);
        assert.deepStrictEqual(
            items.map((i) => i.label),
            ["Walkthrough (recommended)", "Finish the reading order you started", "Commit by commit"]
        );
        assert.strictEqual(items[0].draft, undefined, "walk se lee, no se arma");
        assert.strictEqual(items[1].draft, "resume");
        assert.strictEqual(items[1].layout, "walk");
    });

    it("fallback sin recommended ni Automatic", () => {
        const items = buildLayoutItems(undefined);
        assert.deepStrictEqual(
            items.map((i) => i.layout),
            ["step", "whole"]
        );
        for (const item of items) {
            assert.ok(!item.label.toLowerCase().includes("automatic"));
            assert.ok(!item.description.toLowerCase().includes("automatic"));
            assert.ok(!item.label.includes("recommended"));
        }
    });
});

describe("layoutSummary", () => {
    it("nombra la forma real sin automatic", () => {
        assert.strictEqual(layoutSummary("walk"), "as a walkthrough");
        assert.strictEqual(layoutSummary("keys"), "keys only");
        assert.strictEqual(layoutSummary("step"), "commit by commit");
        assert.strictEqual(layoutSummary("whole"), "as the whole diff");
        for (const layout of ["walk", "keys", "step", "whole"] as const) {
            assert.ok(!layoutSummary(layout).toLowerCase().includes("automatic"));
        }
    });
});

describe("offerConfigFlags", () => {
    it("remote full: sin flags", () => {
        assert.deepStrictEqual(offerConfigFlags("remote", "full"), []);
    });

    it("local delta: --local --delta", () => {
        assert.deepStrictEqual(offerConfigFlags("local", "delta"), ["--local", "--delta"]);
    });

    it("offline full: --offline", () => {
        assert.deepStrictEqual(offerConfigFlags("offline", "full"), ["--offline"]);
    });
});
