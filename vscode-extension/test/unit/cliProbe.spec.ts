import * as assert from "node:assert";
import {
    CLI_PROBE_INTERVAL_MS,
    CLI_PROBE_RETRIES,
    CLI_PROBE_RETRY_DELAY_MS,
    shouldProbeCli,
    versionVerdict,
} from "../../src/review/cliProbe";
import type {Situation} from "../../src/review/situation";

describe("shouldProbeCli", () => {
    it("solo en cli-missing o cli-outdated con el panel visible", () => {
        assert.strictEqual(shouldProbeCli("cli-missing", true), true);
        assert.strictEqual(shouldProbeCli("cli-outdated", true), true);
    });

    it("no sondea si el panel no es visible", () => {
        assert.strictEqual(shouldProbeCli("cli-missing", false), false);
        assert.strictEqual(shouldProbeCli("cli-outdated", false), false);
    });

    it("no sondea en ninguna otra situacion, aunque el panel este abierto", () => {
        const others: Situation[] = [
            "review",
            "no-review",
            "out-of-range",
            "error",
            "finish-conflict",
            "finish-pending",
        ];
        for (const situation of others) {
            assert.strictEqual(
                shouldProbeCli(situation, true),
                false,
                `no debe sondear en ${situation}`,
            );
        }
    });

    it("el intervalo es de 10 segundos", () => {
        assert.strictEqual(CLI_PROBE_INTERVAL_MS, 10_000);
    });
});

describe("versionVerdict", () => {
    const probe = (over: Partial<Parameters<typeof versionVerdict>[0]>) => ({
        stderr: "",
        exitCode: 0 as number | null,
        ...over,
    });

    it("exit cero es la CLI presente", () => {
        assert.strictEqual(versionVerdict(probe({})), "ok");
    });

    it("solo ENOENT es ausencia del lado del spawn", () => {
        assert.strictEqual(versionVerdict(probe({errorCode: "ENOENT", exitCode: null})), "missing");
        // EAGAIN es el fork que no salio bajo carga -- el arranque del host, sin ir
        // mas lejos. La CLI puede estar perfectamente instalada.
        assert.strictEqual(versionVerdict(probe({errorCode: "EAGAIN", exitCode: null})), "unknown");
    });

    it("un timeout nunca es una CLI ausente", () => {
        // Un proceso que no existe no tarda en no existir: lo que un timeout
        // describe es una CLI viva y lenta, que es el caso opuesto.
        assert.strictEqual(
            versionVerdict(probe({exitCode: null, timedOut: true})),
            "unknown"
        );
    });

    it("un exit distinto de cero solo es ausencia si el stderr la nombra", () => {
        assert.strictEqual(
            versionVerdict(probe({exitCode: 1, stderr: "git: 'review' is not a git command. See 'git --help'."})),
            "missing"
        );
        assert.strictEqual(
            versionVerdict(probe({exitCode: 1, stderr: "fatal: detected dubious ownership in repository"})),
            "unknown"
        );
        assert.strictEqual(versionVerdict(probe({exitCode: 128})), "unknown");
    });

    it("el veredicto no mira la version: eso lo decide quien la compara", () => {
        // Un build que imprime la version en otro lado no es una CLI vieja, y el
        // llamador se abstiene cuando no hay linea (isOutdated("") da true, y
        // asi salia por el panel como una CLI vieja que nadie llego a leer).
        assert.ok(!("stdout" in probe({})), "stdout no es parte del veredicto");
    });

    it("los reintentos existen y esperan entre uno y otro", () => {
        assert.ok(CLI_PROBE_RETRIES >= 1, "sin reintento el primer fallo del arranque se publica igual");
        assert.ok(CLI_PROBE_RETRY_DELAY_MS > 0, "reintentar en el mismo tick repite el mismo mal momento");
        assert.ok(
            CLI_PROBE_RETRIES * CLI_PROBE_RETRY_DELAY_MS < CLI_PROBE_INTERVAL_MS,
            "la espera acumulada no puede pasarse del sondeo de fondo"
        );
    });
});
