import * as assert from "node:assert";
import {deltaForSource, parseConfigPorcelain} from "../../src/cli/configPorcelain";

describe("parseConfigPorcelain", () => {
    it("config remote sin base configurada", () => {
        const out = "config\tremote\torigin\n";
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.config, {remote: "origin"});
        assert.deepStrictEqual(result.candidates, []);
        assert.deepStrictEqual(result.remotes, []);
        assert.strictEqual(result.deltas, undefined);
    });

    it("config base y remote, los dos presentes", () => {
        const out = ["config\tbase\tmain", "config\tremote\torigin", ""].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.config, {base: "main", remote: "origin"});
    });

    it("parsea remote-candidate a CandidateRemote[]", () => {
        const out = [
            "config\tremote\torigin",
            "remote-candidate\torigin\t1",
            "remote-candidate\tupstream\t0",
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.remotes, [
            {name: "origin", current: true},
            {name: "upstream", current: false},
        ]);
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

    it("parsea delta con origin y admite hasta dos filas", () => {
        const out = [
            "config\tremote\torigin",
            "delta\tfeature/checkout\tabc123def456\tremote",
            "delta\tfeature/checkout\tfedcba654321\tlocal",
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.deltas, [
            {name: "feature/checkout", tip: "abc123def456", origin: "remote"},
            {name: "feature/checkout", tip: "fedcba654321", origin: "local"},
        ]);
    });

    it("sin registro delta el campo queda ausente, no undefined a medias", () => {
        const out = "config\tremote\torigin\n";
        const result = parseConfigPorcelain(out);
        assert.strictEqual("deltas" in result, false);
    });

    it("descarta un delta sin origin o con origin desconocido", () => {
        const out = [
            "config\tremote\torigin",
            "delta\tfeature/checkout\tabc123def456",
            "delta\tfeature/checkout\tabc123def456\tupstream",
            "delta\tfeature/checkout\tabc123def456\tremote",
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.deltas, [
            {name: "feature/checkout", tip: "abc123def456", origin: "remote"},
        ]);
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
            "delta\tfeature/x\tabc\tremote\textra",
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.config, {remote: "origin"});
        assert.deepStrictEqual(result.candidates, [{
            name: "feature/x",
            origin: "local",
            current: true
        }]);
        assert.deepStrictEqual(result.deltas, [{name: "feature/x", tip: "abc", origin: "remote"}]);
    });

    it("una entrada de salida vacia no produce config ni candidatos", () => {
        const result = parseConfigPorcelain("");
        assert.deepStrictEqual(result.config, {remote: "origin"});
        assert.deepStrictEqual(result.candidates, []);
        assert.deepStrictEqual(result.remotes, []);
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

    // ── offer (008 reading layouts) ──────────────────────────────────────────

    it("parsea offer walk recommended y keys available", () => {
        const out = [
            "config\tremote\torigin",
            "offer\twalk\trecommended",
            "offer\tkeys\tavailable",
            "offer\tstep\tavailable",
            "offer\twhole\tavailable",
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.offers, [
            {id: "walk", rank: "recommended"},
            {id: "keys", rank: "available"},
            {id: "step", rank: "available"},
            {id: "whole", rank: "available"},
        ]);
    });

    it("sin registro offer el campo queda ausente", () => {
        const result = parseConfigPorcelain("config\tremote\torigin\n");
        assert.strictEqual("offers" in result, false);
    });

    it("descarta offer con id o rank desconocido", () => {
        const out = [
            "config\tremote\torigin",
            "offer\tauto\tavailable",
            "offer\twalk\tbest",
            "offer\tstep\tavailable",
            "",
        ].join("\n");
        const result = parseConfigPorcelain(out);
        assert.deepStrictEqual(result.offers, [{id: "step", rank: "available"}]);
    });
});

describe("deltaForSource", () => {
    const deltas = [
        {name: "feature/x", tip: "aaa", origin: "remote" as const},
        {name: "feature/x", tip: "bbb", origin: "local" as const},
    ];

    it("remote source picks the remote row", () => {
        assert.deepStrictEqual(deltaForSource(deltas, "remote"), deltas[0]);
    });

    it("local and offline both pick the local row", () => {
        assert.deepStrictEqual(deltaForSource(deltas, "local"), deltas[1]);
        assert.deepStrictEqual(deltaForSource(deltas, "offline"), deltas[1]);
    });

    it("absent when that origin has no marker", () => {
        assert.strictEqual(deltaForSource([deltas[0]], "local"), undefined);
        assert.strictEqual(deltaForSource([deltas[1]], "remote"), undefined);
        assert.strictEqual(deltaForSource(undefined, "remote"), undefined);
        assert.strictEqual(deltaForSource([], "offline"), undefined);
    });
});
