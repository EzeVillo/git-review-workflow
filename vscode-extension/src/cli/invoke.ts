import type {ChildProcess} from "node:child_process";
import * as path from "node:path";
import spawn from "cross-spawn";
import {logCliEnd, logCliStart} from "./cliLog";

export interface InvokeOptions {
    cwd: string;
    /** Valor crudo del ajuste `gitReview.path`; vacío = invocar `git review`. */
    gitReviewPath?: string;
    timeoutMs?: number;
    signal?: AbortSignal;
    /**
     * `true` sólo para la invocación que toca la red (`start`): agrega al
     * entorno del proceso hijo `GIT_TERMINAL_PROMPT=0` y apunta
     * `GIT_ASKPASS`/`SSH_ASKPASS` al no-op de `scripts/askpass-noop.js`, para
     * que un `fetch` que necesita credenciales falle rápido con el
     * diagnóstico de git en vez de colgarse esperando un TTY que no existe
     * (research.md Decisión 5 de `005`).
     */
    network?: boolean;
}

export interface InvokeResult {
    stdout: string;
    stderr: string;
    /** null cuando el proceso nunca llegó a correr (p. ej. ENOENT). */
    exitCode: number | null;
    /** Código de error de Node cuando el spawn falló (p. ej. "ENOENT"). */
    errorCode?: string;
    /**
     * La invocación se cortó al vencer su timeout. Llega con `exitCode: null` y
     * sin `errorCode`, así que sin este campo un consumidor no puede
     * distinguirla de un proceso que murió por su cuenta — y el diagnóstico que
     * corresponde es el opuesto (la CLI está viva pero lenta, no rota).
     */
    timedOut?: true;
}

const READ_TIMEOUT_MS = 15000;
const LOCAL_MUTATION_TIMEOUT_MS = 120000;
const NETWORK_MUTATION_TIMEOUT_MS = 300000;

// Mutación local: replica ediciones o mueve refs sin tocar la red, pero puede
// recorrer un PR grande commit por commit — un timeout de lectura la mataría
// a mitad (research.md Decisión 6 de `005`).
const LOCAL_MUTATION_VERBS = new Set([
    "finish",
    "save",
    "abort",
    "continue",
    "next",
    "prev",
    "clean",
    "forget",
    "compare",
    "walkthrough",
    // preview walks the full edit set (step replay can be large); same budget as finish.
    "preview",
]);
// `start` hace fetch del tip; `forget --delta --stale` hace fetch --prune.
// El resto de forget es local — ver timeoutForClass + args.
const NETWORK_MUTATION_VERBS = new Set(["start"]);

/**
 * Timeout según la clase de la invocación (research.md Decisión 6 de `005`,
 * enmienda `006` para clean/forget/compare/walkthrough y forget --stale).
 * Un verbo desconocido se trata como lectura, el default más conservador.
 */
export function timeoutForClass(verb: string, args: string[]): number {
    if (NETWORK_MUTATION_VERBS.has(verb)) {
        return NETWORK_MUTATION_TIMEOUT_MS;
    }
    // forget --delta --stale: fetch; el único caso donde args cambian la clase.
    if (verb === "forget" && args.includes("--stale")) {
        return NETWORK_MUTATION_TIMEOUT_MS;
    }
    if (LOCAL_MUTATION_VERBS.has(verb)) {
        return LOCAL_MUTATION_TIMEOUT_MS;
    }
    return READ_TIMEOUT_MS;
}

/**
 * Comando que git/ssh invocan como `GIT_ASKPASS`/`SSH_ASKPASS`. Nunca el
 * script solo: Windows no sabe ejecutar un `.js`, y git invoca askpass a
 * través de una shell (`use_shell`), así que la cadena con espacio se parte
 * ahí, no acá — mismo motivo por el que el nombre de rama de `resolveCommand`
 * no puede llevar este atajo. `__dirname` resuelve a `dist/` una vez
 * empaquetado (esbuild bundlea todo a un único archivo ahí; T008 copia el
 * script al lado).
 */
function askpassCommand(): string {
    const scriptPath = path.join(__dirname, "askpass-noop.js");
    return `"${process.execPath}" "${scriptPath}"`;
}

/**
 * Entorno para la invocación con `options.network`: parte de `process.env`
 * (perder el resto — `PATH` incluido — rompería la resolución del propio
 * `git`) y sólo agrega las tres variables de la Decisión 5.
 */
function networkEnv(): NodeJS.ProcessEnv {
    const askpass = askpassCommand();
    return {
        ...process.env,
        GIT_TERMINAL_PROMPT: "0",
        GIT_ASKPASS: askpass,
        SSH_ASKPASS: askpass,
    };
}

/**
 * Extensiones que Windows sabe ejecutar como proceso nativo, incluidos los
 * shims `.cmd`/`.bat` de una instalación por npm — cross-spawn ya resuelve
 * esos de forma segura (delega en cmd.exe con el escaping correcto, el mismo
 * problema detrás de CVE-2024-27980). Lo que cross-spawn NO resuelve es un
 * script POSIX sin extensión (`#!/usr/bin/env sh`): ahí sólo `git.exe` sabe
 * correrlo, vía su propia capa MSYS (research.md Decisión 3).
 */
const WINDOWS_NATIVE_EXECUTABLE = /\.(exe|cmd|bat)$/i;

export interface ResolvedCommand {
    command: string;
    args: string[];
}

/**
 * Resuelve el ejecutable y los args de la invocación (contracts/cli-invocation.md
 * § "Forma de toda invocación"). Con `git` de por medio, el subcomando
 * "review" lo consume git y el dispatcher recibe [<verbo>, ...args] igual —
 * pero invocar el dispatcher directamente (gitReview.path) salta ese paso de
 * git, así que el verbo va primero: bin/git-review espera $1=<verbo>, nunca
 * "review" (bin/git-review:67).
 *
 * Exportada (no sólo de uso interno) para que un consumidor que necesite
 * mostrar o reproducir la invocación exacta —el escape *Run in Terminal* de
 * `startReview.ts`, research.md Decisión 5— resuelva el mismo comando que de
 * verdad correría `invokeGitReview`, en vez de hardcodear `git review <verbo>`
 * e ignorar `gitReview.path`.
 */
export function resolveCommand(verb: string, args: string[], gitReviewPath: string | undefined): ResolvedCommand {
    if (gitReviewPath === undefined || gitReviewPath.trim() === "") {
        return {command: "git", args: ["review", verb, ...args]};
    }
    if (process.platform === "win32" && !WINDOWS_NATIVE_EXECUTABLE.test(gitReviewPath)) {
        return {command: "sh", args: [gitReviewPath, verb, ...args]};
    }
    return {command: gitReviewPath, args: [verb, ...args]};
}

/**
 * Mata lo que se pueda del árbol de procesos de una invocación vencida.
 *
 * Es best-effort **por diseño**, y conviene saber exactamente cuánto alcanza:
 * en Windows `taskkill /T` sólo llega a los procesos cuya paternidad Windows
 * registra, y la capa MSYS por la que corren los verbos POSIX no la registra —
 * medido: matar el `sh` con `/T /F` deja vivo un nieto `sleep` 3s después. En
 * POSIX sí alcanza al árbol entero, porque el hijo se spawnea como líder de su
 * propio grupo (`detached`) y la señal va al grupo (`-pid`).
 *
 * Por eso quien llama no espera a que esto surta efecto: desconecta los pipes y
 * resuelve igual. Un nieto que sobreviva termina solo — los verbos son finitos
 * — y mientras tanto ya no bloquea a nadie.
 */
function killTree(child: ChildProcess): void {
    const pid = child.pid;
    if (pid === undefined) {
        return;
    }
    if (process.platform === "win32") {
        try {
            spawn("taskkill", ["/pid", String(pid), "/T", "/F"], {
                stdio: "ignore",
                windowsHide: true,
            });
        } catch {
            // taskkill ausente o el proceso ya murió: nada que hacer.
        }
        return;
    }
    try {
        // Negativo = el grupo entero, que es lo que `detached` nos dio.
        process.kill(-pid, "SIGKILL");
    } catch {
        try {
            child.kill("SIGKILL");
        } catch {
            // Ya terminó.
        }
    }
}

/**
 * Invoca `git review <verbo> [...args]` según la forma fijada en
 * contracts/cli-invocation.md: sin shell propio (cross-spawn resuelve
 * `.cmd`/`.bat` de Windows sin reintroducir el problema de citado que
 * `shell: true` traería para los paths que viajan como argv), cwd en la raíz
 * del repo objetivo, cancelable y con timeout.
 *
 * El timeout es **propio**, no la opción `timeout` de `spawn`: ésa no corta
 * nada acá. Node le manda SIGTERM al hijo y después espera el evento `close`,
 * que no llega hasta que se cierran los pipes — y los sostienen los nietos, que
 * la señal no alcanzó. Medido en Windows: un hijo con timeout de 2000ms
 * resolvía a los 8117ms, o sea al terminar solo; el timeout no adelantaba nada.
 * Ése es el "← exit null 29656ms" con `READ_TIMEOUT_MS = 15000` que se veía en
 * el log. Acá el temporizador mata lo que puede y resuelve en el acto, así que
 * el techo que promete `timeoutForClass` se cumple de verdad.
 */
export function invokeGitReview(
    verb: string,
    args: string[],
    options: InvokeOptions
): Promise<InvokeResult> {
    const {command, args: commandArgs} = resolveCommand(verb, args, options.gitReviewPath);
    const timeoutMs = options.timeoutMs ?? timeoutForClass(verb, args);
    const started = Date.now();
    logCliStart(command, commandArgs, options.cwd);

    return new Promise((resolve) => {
        const child = spawn(command, commandArgs, {
            cwd: options.cwd,
            signal: options.signal,
            // Sólo POSIX: en Windows `detached` abriría una consola nueva, y no
            // compra nada (no hay grupos de procesos a los que señalizar).
            ...(process.platform === "win32" ? {} : {detached: true}),
            ...(options.network ? {env: networkEnv()} : {}),
        });

        let stdout = "";
        let stderr = "";
        let settled = false;
        child.stdout?.setEncoding("utf8").on("data", (chunk: string) => (stdout += chunk));
        child.stderr?.setEncoding("utf8").on("data", (chunk: string) => (stderr += chunk));

        // Declarado antes de `settle` y asignado después: `settle` lo lee, y si
        // un `error` llegara antes de que el temporizador exista, un `const`
        // todavía en su zona muerta temporal tiraría ReferenceError en lugar de
        // rechazar limpio. `clearTimeout(undefined)` es un no-op.
        let timer: ReturnType<typeof setTimeout> | undefined;

        // Un único punto de salida: `close` puede llegar después de que el
        // temporizador ya resolvió (y al revés), y resolver dos veces dejaría
        // el timer vivo o pisaría el resultado ya entregado.
        const settle = (result: InvokeResult): void => {
            if (settled) {
                return;
            }
            settled = true;
            clearTimeout(timer);
            logCliEnd({
                exitCode: result.exitCode,
                errorCode: result.errorCode,
                durationMs: Date.now() - started,
                stderr: result.stderr,
                timedOut: result.timedOut,
            });
            resolve(result);
        };

        timer = setTimeout(() => {
            killTree(child);
            // Soltar los pipes: son ellos los que mantenían viva la espera.
            child.stdout?.destroy();
            child.stderr?.destroy();
            settle({stdout, stderr, exitCode: null, timedOut: true});
        }, timeoutMs);

        child.on("error", (error: NodeJS.ErrnoException) => {
            // Windows + gitReview.path POSIX (sin .cmd/.exe): se spawnea `sh`.
            // ENOENT suele ser "sh no está en PATH", no "falta el dispatcher".
            let errorStderr = stderr;
            if (
                error.code === "ENOENT" &&
                command === "sh" &&
                options.gitReviewPath &&
                options.gitReviewPath.trim() !== ""
            ) {
                const hint =
                    "Could not run git-review via sh (ENOENT). On Windows, put Git Bash sh on PATH, or set gitReview.path to a .cmd/.bat/.exe shim (or leave it empty and use `git review`).";
                errorStderr = errorStderr.length > 0 ? `${errorStderr}\n${hint}` : hint;
            }
            settle({
                stdout,
                stderr: errorStderr,
                exitCode: null,
                errorCode: error.code,
            });
        });

        child.on("close", (code) => {
            settle({stdout, stderr, exitCode: code});
        });
    });
}
