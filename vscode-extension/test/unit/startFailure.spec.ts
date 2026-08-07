import * as assert from "node:assert";
import {classifyStartFailure, quoteForTerminal} from "../../src/review/startFailure";

describe("classifyStartFailure", () => {
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

    it("el die() propio de start ('could not update from') SOLO, sin el stderr de git delante, clasifica como repository", () => {
        // Regresion (revision de la Fase 3): ese texto es la salida del VERBO,
        // no el stderr de git que el contrato autoriza mirar (contracts/
        // cli-invocation.md § "Clasificar no es parsear"). git fetch --quiet
        // sigue escribiendo su propio stderr antes de este die(), asi que en
        // la practica siempre llega acompanado de una de las marcas de arriba
        // — pero la funcion no debe clasificar "network" a partir de esta
        // frase sola.
        assert.strictEqual(classifyStartFailure("error: could not update from origin\n"), "repository");
    });
});

describe("quoteForTerminal (POSIX)", () => {
    it("deja un nombre simple sin comillas", () => {
        assert.strictEqual(quoteForTerminal("feature/checkout", "linux"), "feature/checkout");
    });

    it("cita un nombre con espacios", () => {
        assert.strictEqual(quoteForTerminal("feature/with space", "linux"), '"feature/with space"');
    });

    it("escapa una comilla doble interna", () => {
        assert.strictEqual(quoteForTerminal('feature/"quoted"', "linux"), '"feature/\\"quoted\\""');
    });

    it("cita un nombre que empieza con guion, para que no se lea como flag al pegarlo", () => {
        assert.strictEqual(quoteForTerminal("-foo", "linux"), '"-foo"');
    });
});

describe("quoteForTerminal (PowerShell / win32)", () => {
    it("deja un nombre simple sin comillas", () => {
        assert.strictEqual(quoteForTerminal("feature/checkout", "win32"), "feature/checkout");
    });

    it("cita con comillas simples un nombre con espacios", () => {
        assert.strictEqual(quoteForTerminal("feature/with space", "win32"), "'feature/with space'");
    });

    it("no expande $ ni backticks: comilla simple literal", () => {
        assert.strictEqual(quoteForTerminal("cost_$total", "win32"), "'cost_$total'");
        assert.strictEqual(quoteForTerminal("a`n", "win32"), "'a`n'");
    });

    it("embebe comilla simple duplicandola ('' en PowerShell)", () => {
        assert.strictEqual(quoteForTerminal("it's", "win32"), "'it''s'");
    });

    it("cita un nombre que empieza con guion", () => {
        assert.strictEqual(quoteForTerminal("-foo", "win32"), "'-foo'");
    });
});
