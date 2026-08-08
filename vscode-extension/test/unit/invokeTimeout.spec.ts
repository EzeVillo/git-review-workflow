import * as assert from "node:assert";
import {invokeGitReview} from "../../src/cli/invoke";

/**
 * El techo que promete `timeoutForClass` tiene que cumplirse de verdad. Antes
 * no se cumplía: con la opción `timeout` de `spawn`, Node manda SIGTERM y
 * después espera `close`, que no llega hasta que se cierran los pipes — y los
 * sostienen los nietos, a los que la señal no alcanzó. Medido en Windows, un
 * hijo con timeout de 2000ms resolvía a los 8117ms (o sea, al terminar por su
 * cuenta: el timeout no adelantaba nada), y eso se veía en el log del panel
 * como "← exit null 29656ms" con un READ_TIMEOUT_MS de 15000.
 *
 * El proceso de prueba es el propio Node en vez de un `sh -c sleep`: `sh` puede
 * no estar en el PATH del runner de Windows, y `process.execPath` termina en
 * .exe ahí, así que `resolveCommand` lo invoca directo en las dos plataformas
 * sin pasar por la envoltura de `sh`. El "verbo" es `-e` y el arg el script.
 */
describe("invokeGitReview: timeout", () => {
    /** Un proceso que no termina solo dentro del horizonte del test. */
    const HANGS = "setTimeout(() => {}, 60000)";

    it("corta un proceso colgado y lo reporta como timedOut", async () => {
        const started = Date.now();
        const result = await invokeGitReview("-e", [HANGS], {
            cwd: process.cwd(),
            gitReviewPath: process.execPath,
            timeoutMs: 300,
        });
        const elapsed = Date.now() - started;

        assert.strictEqual(result.timedOut, true, "debe marcarse como timeout");
        assert.strictEqual(result.exitCode, null);
        assert.strictEqual(result.errorCode, undefined, "un timeout no es un fallo de spawn");
        // Holgado contra un runner cargado, pero muy por debajo de los 60s que
        // el proceso habría tardado: sin el fix, esto no resolvía hasta ahí.
        assert.ok(elapsed < 5000, `resolvió en ${elapsed}ms, se esperaba cerca de 300ms`);
    });

    it("un proceso que termina a tiempo no se marca como timedOut", async () => {
        const result = await invokeGitReview("-e", ["process.stdout.write('ok')"], {
            cwd: process.cwd(),
            gitReviewPath: process.execPath,
            timeoutMs: 10000,
        });

        assert.strictEqual(result.exitCode, 0);
        assert.strictEqual(result.stdout, "ok");
        assert.strictEqual(result.timedOut, undefined, "no debe inventar el campo");
    });

    it("un proceso que falla a tiempo conserva su exit code y su stderr", async () => {
        const result = await invokeGitReview(
            "-e",
            ["process.stderr.write('boom'); process.exit(3)"],
            {cwd: process.cwd(), gitReviewPath: process.execPath, timeoutMs: 10000}
        );

        assert.strictEqual(result.exitCode, 3);
        assert.strictEqual(result.stderr, "boom");
        assert.strictEqual(result.timedOut, undefined);
    });
});
