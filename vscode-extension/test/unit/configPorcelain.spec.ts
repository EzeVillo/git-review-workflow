import * as assert from "node:assert";
import {parseConfigPorcelain} from "../../src/cli/configPorcelain";

describe("parseConfigPorcelain", () => {
    it("config remote sin base configurada", () => {
        const out = "config\tremote\torigin\n";
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.config, {remote: "origin"});
        assert.deepStrictEqual(result.candidates, []);
        assert.strictEqual(result.delta, undefined);
    });

    it("config base y remote, los dos presentes", () => {
        const out = ["config\tbase\tmain", "config\tremote\torigin", ""].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.config, {base: "main", remote: "origin"});
    });

    it("parsea candidate a CandidateBranch[]", () => {
        const out = [
            "config\tremote\torigin",
            "candidate\tfeature/checkout\tremote\t0",
            "candidate\tfeature/checkout\tlocal\t1",
            "candidate\tmain\tremote\t0",
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.candidates, [
            {name: "feature/checkout", origin: "remote", current: false},
            {name: "feature/checkout", origin: "local", current: true},
            {name: "main", origin: "remote", current: false},
        ]);
    });

    it("un candidate duplicado (misma rama, dos origenes) produce dos entradas, no una fusionada", () => {
        const out = [
            "config\tremote\torigin",
            "candidate\tfeature/x\tremote\t0",
            "candidate\tfeature/x\tlocal\t0",
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.strictEqual(result.candidates.length, 2);
        assert.notStrictEqual(result.candidates[0], result.candidates[1]);
        assert.strictEqual(result.candidates[0].name, "feature/x");
        assert.strictEqual(result.candidates[1].name, "feature/x");
        assert.notStrictEqual(result.candidates[0].origin, result.candidates[1].origin);
    });

    it("parsea delta sólo cuando el registro llega", () => {
        const out = [
            "config\tremote\torigin",
            "delta\tfeature/checkout\tabc123def456",
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.delta, {name: "feature/checkout", tip: "abc123def456"});
    });

    it("sin registro delta el campo queda ausente, no undefined a medias", () => {
        const out = "config\tremote\torigin\n";
        const result = parseConfigPorcelain(out);
        assert.strictEqual("delta" in result, false);
    });

    it("ignora etiquetas desconocidas", () => {
        const out = [
            "config\tremote\torigin",
            "future-tag\tsome\tfields",
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.config, {remote: "origin"});
        assert.deepStrictEqual(result.candidates, []);
    });

    it("ignora campos extra al final de un registro conocido", () => {
        const out = [
            "config\tremote\torigin\textra1\textra2",
            "candidate\tfeature/x\tlocal\t1\textra",
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.config, {remote: "origin"});
        assert.deepStrictEqual(result.candidates, [{name: "feature/x", origin: "local", current: true}]);
    });

    it("una entrada de salida vacia no produce config ni candidatos", () => {
        const result = parseConfigPorcelain("");
        assert.deepStrictEqual(result.config, {remote: "origin"});
        assert.deepStrictEqual(result.candidates, []);
    });

    it("un candidate con origin desconocido se descarta entero", () => {
        const out = [
            "config\tremote\torigin",
            "candidate\tfeature/x\tupstream\t0",
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.candidates, []);
    });
});
