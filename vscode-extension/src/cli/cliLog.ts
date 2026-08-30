/**
 * Log de invocaciones a la CLI de git-review (sólo lo que pasa por
 * `invokeGitReview`). No se auto-abre: el canal queda en Output sin empujar
 * la vista; el comando de paleta `gitReview.showCliLog` lo muestra a pedido.
 *
 * No registra git puro ni la API de `vscode.git` — ésos no pasan por acá.
 *
 * `vscode` se carga con `require` sólo en `initCliLog`: este módulo se importa
 * desde `invoke.ts`, y los unit tests de mocha no tienen el módulo `vscode`
 * (mismo motivo que `import type` en otros specs de review/).
 */

const STDERR_MAX = 2000;

interface LogChannel {
    info(message: string): void;
    warn(message: string): void;
    error(message: string): void;
    show(preserveFocus?: boolean): void;
    dispose(): void;
}

let channel: LogChannel | undefined;

/** Crea el canal una vez al activar. Idempotente. */
export function initCliLog(disposables: {push(d: {dispose(): void}): void}): void {
    if (channel) {
        return;
    }
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const vscode = require("vscode") as typeof import("vscode");
    channel = vscode.window.createOutputChannel("Git Review CLI", {log: true});
    disposables.push(channel);
}

/** Abre el canal sin robar el foco del editor. */
export function showCliLog(): void {
    channel?.show(/* preserveFocus */ true);
}

/** Cita un argv para legibilidad en el log (no se re-parsea como shell). */
export function shellQuoteArg(arg: string): string {
    if (arg.length === 0) {
        return '""';
    }
    if (/[\s"\\]/.test(arg)) {
        return `"${arg.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
    }
    return arg;
}

export function formatCommandLine(command: string, args: string[]): string {
    return [command, ...args.map(shellQuoteArg)].join(" ");
}

export function logCliStart(command: string, args: string[], cwd: string): void {
    if (!channel) {
        return;
    }
    channel.info(`→ ${formatCommandLine(command, args)}  (cwd=${cwd})`);
}

export interface CliLogEnd {
    exitCode: number | null;
    errorCode?: string;
    durationMs: number;
    stderr: string;
    /** La invocación se cortó por timeout; ver `invoke.ts`. */
    timedOut?: boolean;
}

/**
 * Cierra la línea de la invocación. Sólo stderr (truncado) en fallos: el
 * stdout de `--porcelain` no se vuelca — el log es de comandos, no de payload.
 */
export function logCliEnd(result: CliLogEnd): void {
    if (!channel) {
        return;
    }
    const ms = `${result.durationMs}ms`;
    // Antes que el resto: un timeout da exitCode null sin errorCode, indistinguible
    // en el log de un proceso muerto por su cuenta ("← exit null 29656ms" con
    // timeout=15000 se leía como misterio, no como timeout).
    if (result.timedOut) {
        channel.warn(`← timed out after ${ms} (killed)`);
        return;
    }
    if (result.errorCode) {
        channel.error(`← spawn failed ${result.errorCode}  ${ms}`);
        return;
    }
    const line = `← exit ${result.exitCode ?? "null"}  ${ms}`;
    if (result.exitCode === 0) {
        channel.info(line);
        return;
    }
    channel.warn(line);
    const err = result.stderr.trimEnd();
    if (err.length === 0) {
        return;
    }
    const body =
        err.length > STDERR_MAX ? `${err.slice(0, STDERR_MAX)}\n… (truncated)` : err;
    for (const part of body.split(/\r?\n/)) {
        channel.warn(`  ${part}`);
    }
}
