import * as assert from "node:assert";
import {classifyStartFailure, quoteForTerminal} from "../../src/review/startFailure";

describe("classifyStartFailure", () => {
    it("could not update from (el propio start ante cualquier fallo de fetch) clasifica como network", () => {
        assert.strictEqual(classifyStartFailure("error: could not update from origin\n"), "network");
    });

    it("could not resolve host clasifica como network", () => {
        assert.strictEqual(
            classifyStartFailure("fatal: unable to access 'https://example.com/x': Could not resolve host: example.com\n"),
            "network"
        );
    });

    it("terminal prompts disabled (GIT_TERMINAL_PROMPT=0) clasifica como network", () => {
        assert.strictEqual(
            classifyStartFailure("fatal: could not read Username for 'https://example.com': terminal prompts disabled\n"),
            "network"
        );
    });

    it("authentication failed clasifica como network", () => {
        assert.strictEqual(
            classifyStartFailure("fatal: Authentication failed for 'https://example.com/repo.git/'\n"),
            "network"
        );
    });

    it("permission denied (publickey) clasifica como network", () => {
        assert.strictEqual(
            classifyStartFailure("git@github.com: Permission denied (publickey).\n"),
            "network"
        );
    });

    it("es insensible a mayusculas/minusculas", () => {
        assert.strictEqual(classifyStartFailure("FATAL: COULD NOT RESOLVE HOST\n"), "network");
    });

    it("un working tree sucio clasifica como repository" , () => {
        assert.strictEqual(
            classifyStartFailure("error: you have local changes; commit or stash them first\n"),
            "repository"
        );
    });

    it("una review ya existente clasifica como repository", () => {
        assert.strictEqual(
            classifyStartFailure("error: review/feature/x already exists; run git review clean feature/x first\n"),
            "repository"
        );
    });

    it("una rama inexistente clasifica como repository", () => {
        assert.strictEqual(classifyStartFailure("error: origin/feature/x not found\n"), "repository");
    });

    it("stderr vacio clasifica como repository (nunca ofrece un escape sin motivo)", () => {
        assert.strictEqual(classifyStartFailure(""), "repository");
    });
});

describe("quoteForTerminal", () => {
    it("deja un nombre simple sin comillas", () => {
        assert.strictEqual(quoteForTerminal("feature/checkout"), "feature/checkout");
    });

    it("cita un nombre con espacios", () => {
        assert.strictEqual(quoteForTerminal("feature/with space"), '"feature/with space"');
    });

    it("escapa una comilla doble interna", () => {
        assert.strictEqual(quoteForTerminal('feature/"quoted"'), '"feature/\\"quoted\\""');
    });

    it("cita un nombre que empieza con guion, para que no se lea como flag al pegarlo", () => {
        assert.strictEqual(quoteForTerminal("-foo"), '"-foo"');
    });
});
