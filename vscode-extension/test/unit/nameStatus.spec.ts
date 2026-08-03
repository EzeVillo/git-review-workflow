import * as assert from "node:assert";
import {parseNameStatus} from "../../src/cli/nameStatus";

/** Arma la salida de `git diff-tree -z`: campos NUL-separados, con NUL final. */
function z(...fields: string[]): string {
    return fields.map((field) => `${field}\0`).join("");
}

describe("parseNameStatus", () => {
    it("un archivo modificado existe de los dos lados", () => {
        assert.deepStrictEqual(parseNameStatus(z("M", "src/core.ts")), [
            {path: "src/core.ts", before: "src/core.ts", after: "src/core.ts"},
        ]);
    });

    it("un archivo agregado no tiene lado izquierdo", () => {
        assert.deepStrictEqual(parseNameStatus(z("A", "src/nuevo.ts")), [
            {path: "src/nuevo.ts", before: undefined, after: "src/nuevo.ts"},
        ]);
    });

    it("un archivo eliminado no tiene lado derecho", () => {
        assert.deepStrictEqual(parseNameStatus(z("D", "src/viejo.ts")), [
            {path: "src/viejo.ts", before: "src/viejo.ts", after: undefined},
        ]);
    });

    it("un cambio de tipo existe de los dos lados", () => {
        assert.deepStrictEqual(parseNameStatus(z("T", "src/link.ts")), [
            {path: "src/link.ts", before: "src/link.ts", after: "src/link.ts"},
        ]);
    });

    it("un rename toma sus dos paths y no desincroniza los registros siguientes", () => {
        const output = z("R100", "src/viejo.ts", "src/nuevo.ts", "M", "src/otro.ts");
        assert.deepStrictEqual(parseNameStatus(output), [
            {path: "src/nuevo.ts", before: "src/viejo.ts", after: "src/nuevo.ts"},
            {path: "src/otro.ts", before: "src/otro.ts", after: "src/otro.ts"},
        ]);
    });

    it("una copia se muestra contra el archivo del que salio", () => {
        assert.deepStrictEqual(parseNameStatus(z("C75", "src/fuente.ts", "src/copia.ts")), [
            {path: "src/copia.ts", before: "src/fuente.ts", after: "src/copia.ts"},
        ]);
    });

    it("conserva varios registros en el orden en que los da git", () => {
        const output = z("A", "src/add.ts", "D", "src/gone.ts", "M", "src/mod.ts");
        assert.deepStrictEqual(parseNameStatus(output).map((c) => c.path), [
            "src/add.ts",
            "src/gone.ts",
            "src/mod.ts",
        ]);
    });

    it("con -z los paths salen literales: espacios, acentos y comillas incluidos", () => {
        const odd = 'src/raro café "con" espacios.ts';
        assert.deepStrictEqual(parseNameStatus(z("A", odd)), [
            {path: odd, before: undefined, after: odd},
        ]);
    });

    it("un commit sin cambios (merge, o el arbol vacio) no da registros", () => {
        assert.deepStrictEqual(parseNameStatus(""), []);
    });

    it("una salida truncada descarta el registro incompleto, no inventa un path", () => {
        assert.deepStrictEqual(parseNameStatus(z("M", "src/core.ts") + "A\0"), [
            {path: "src/core.ts", before: "src/core.ts", after: "src/core.ts"},
        ]);
    });
});
