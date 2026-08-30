import type {Situation} from "./situation";

/**
 * Mientras el panel está abierto y la CLI falta o es vieja, re-sondear
 * `--version` en este intervalo: no es polling general de estado, sólo cubre
 * el hueco en el que instalar o actualizar la CLI fuera de VS Code no emite
 * ningún evento al host.
 */
export const CLI_PROBE_INTERVAL_MS = 10_000;

/** `true` cuando conviene reintentar el sondeo de la CLI en background. */
export function shouldProbeCli(situation: Situation, panelVisible: boolean): boolean {
    return panelVisible && (situation === "cli-missing" || situation === "cli-outdated");
}

/**
 * Veredicto de una corrida de `git review --version`, que son TRES cosas y no
 * dos: entre "está y responde" y "no está" existe "no se pudo saber". El
 * arranque es justo donde aparece la tercera —el host recién levanta, el disco
 * está saturado, el proceso tarda o muere sin decir por qué—, y tratarla como
 * ausencia es lo que ponía el cartel de instalar la CLI arriba de una CLI que
 * estaba instalada.
 */
export type CliVerdict = "ok" | "missing" | "unknown";

/**
 * Lo que dice un `git`/shell cuando el ejecutable de verdad no está. Se busca
 * en minúsculas y como substring: el objetivo es la evidencia, no el formato
 * exacto de cada host.
 */
const ABSENCE_MARKERS = [
    "is not a git command",
    "not found",
    "no such file",
    "cannot find",
    "enoent",
    // CreateProcess error=2 — como llega la ausencia del ejecutable por la JVM
    // en Windows, y por lo tanto la que ve el plugin de JetBrains.
    "error=2",
];

/**
 * `true` si el fallo NOMBRA la ausencia del ejecutable. El código de error del
 * spawn y el stderr son el mismo dato leído por dos hosts distintos (Node dice
 * ENOENT donde la JVM dice "CreateProcess error=2"), así que se miran los dos.
 * Vale para cualquier invocación, no sólo para `--version`: un spawn que falló
 * por otra cosa no es una CLI que no está.
 */
export function cliLooksMissing(errorCode: string | undefined, stderr: string): boolean {
    const lower = `${errorCode ?? ""} ${stderr}`.toLowerCase();
    return ABSENCE_MARKERS.some((marker) => lower.includes(marker));
}

/**
 * Lo que el veredicto mira de una corrida, que no incluye `stdout`: la versión
 * la lee el llamador, y sólo después de que esto haya dicho que hubo respuesta.
 */
export interface VersionProbe {
    stderr: string;
    exitCode: number | null;
    errorCode?: string;
    timedOut?: true;
}

/**
 * Clasifica esa corrida (contracts/cli-invocation.md § "git review --version").
 * La única evidencia de ausencia es un fallo que la NOMBRA; un timeout es lo
 * contrario de una CLI ausente (un proceso que no existe no tarda en no
 * existir), y un exit code cualquiera sin ese texto no dice nada por sí solo.
 * `ok` es que la CLI contestó, no que dijo su versión: un build que la imprime
 * en otro lado sigue de largo al `status`, en vez de salir por el panel como una
 * CLI vieja que nadie llegó a leer (`isOutdated("")` es `true`).
 */
export function versionVerdict(probe: VersionProbe): CliVerdict {
    if (probe.timedOut) {
        return "unknown";
    }
    if (probe.errorCode !== undefined || probe.exitCode !== 0) {
        return cliLooksMissing(probe.errorCode, probe.stderr) ? "missing" : "unknown";
    }
    return "ok";
}

/**
 * Reintentos del sondeo ante un veredicto `unknown`, antes de publicar nada.
 * El panel se queda mientras tanto en su superficie de espera: la demora de un
 * arranque cuesta menos que un cartel que hay que desmentir diez segundos
 * después. Acotado a propósito — una respuesta que no llega nunca también
 * tiene que terminar en algo.
 */
export const CLI_PROBE_RETRIES = 2;
export const CLI_PROBE_RETRY_DELAY_MS = 400;
