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
