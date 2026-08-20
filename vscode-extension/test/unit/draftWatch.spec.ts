import * as assert from "node:assert";
import {draftWatchDirs} from "../../src/review/draftWatch";

describe("draftWatchDirs", () => {
    it("sin borradores no hay nada que vigilar", () => {
        assert.deepStrictEqual(draftWatchDirs({}), []);
        assert.deepStrictEqual(draftWatchDirs({drafts: []}), []);
    });

    it("toma el directorio de cada registro draft de config", () => {
        assert.deepStrictEqual(
            draftWatchDirs({
                drafts: [
                    {path: "/repo/.git/review-walkthrough/feature/checkout.md"},
                    {path: "/repo/.git/review-walkthrough/telemetry.md"},
                ],
            }),
            ["/repo/.git/review-walkthrough", "/repo/.git/review-walkthrough/feature"]
        );
    });

    it("incluye el borrador en vigor de la review activa", () => {
        assert.deepStrictEqual(
            draftWatchDirs({draftPath: "/repo/.git/review-walkthrough/feature/x.md"}),
            ["/repo/.git/review-walkthrough/feature"]
        );
    });

    it("no repite un directorio que aparece por las dos vias", () => {
        assert.deepStrictEqual(
            draftWatchDirs({
                draftPath: "/repo/.git/review-walkthrough/feature/x.md",
                drafts: [
                    {path: "/repo/.git/review-walkthrough/feature/x.md"},
                    {path: "/repo/.git/review-walkthrough/feature/y.md"},
                ],
            }),
            ["/repo/.git/review-walkthrough/feature"]
        );
    });

    it("el orden es estable, no el de aparicion", () => {
        const one = draftWatchDirs({
            drafts: [{path: "/repo/.git/rw/b/x.md"}, {path: "/repo/.git/rw/a/y.md"}],
        });
        const other = draftWatchDirs({
            drafts: [{path: "/repo/.git/rw/a/y.md"}, {path: "/repo/.git/rw/b/x.md"}],
        });
        assert.deepStrictEqual(one, ["/repo/.git/rw/a", "/repo/.git/rw/b"]);
        assert.deepStrictEqual(one, other);
    });

    it("separa igual una ruta de Windows con backslash", () => {
        assert.deepStrictEqual(
            draftWatchDirs({draftPath: "C:\\repo\\.git\\review-walkthrough\\feature\\x.md"}),
            ["C:\\repo\\.git\\review-walkthrough\\feature"]
        );
        assert.deepStrictEqual(
            draftWatchDirs({draftPath: "C:/repo/.git/review-walkthrough/x.md"}),
            ["C:/repo/.git/review-walkthrough"]
        );
    });

    it("descarta lo que no nombra un directorio", () => {
        assert.deepStrictEqual(draftWatchDirs({draftPath: ""}), []);
        assert.deepStrictEqual(draftWatchDirs({draftPath: "   "}), []);
        assert.deepStrictEqual(draftWatchDirs({draftPath: "x.md"}), []);
        assert.deepStrictEqual(draftWatchDirs({draftPath: "/x.md"}), []);
    });
});
