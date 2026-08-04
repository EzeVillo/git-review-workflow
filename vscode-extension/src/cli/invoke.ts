import * as path from "node:path";
import spawn from "cross-spawn";

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
}

const READ_TIMEOUT_MS = 15000;
const LOCAL_MUTATION_TIMEOUT_MS = 120000;
const NETWORK_MUTATION_TIMEOUT_MS = 300000;

// Mutación local: replica ediciones o mueve refs sin tocar la red, pero puede
// recorrer un PR grande commit por commit — un timeout de lectura la mataría
// a mitad (research.md Decisión 6 de `005`).
const LOCAL_MUTATION_VERBS = new Set(["finish", "save", "abort", "continue", "next", "prev"]);
// Sólo `start` hace `fetch`; es la única invocación que puede esperar a un
// remoto lento además de replicar el diff completo del PR.
const NETWORK_MUTATION_VERBS = new Set(["start"]);

/**
 * Timeout según la clase de la invocación (research.md Decisión 6 de `005`).
 * La clasificación depende sólo de `verb`; `args` está por forma — ningún
 * verbo de la tabla tiene una variante de argumentos que cambie de clase. Un
 * verbo desconocido se trata como lectura, el default más conservador: nada
 * hoy amerita un timeout largo sin estar en la tabla.
 */
export function timeoutForClass(verb: string, _args: string[]): number {
    if (NETWORK_MUTATION_VERBS.has(verb)) {
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
 * Invoca `git review <verbo> [...args]` según la forma fijada en
 * contracts/cli-invocation.md: sin shell propio (cross-spawn resuelve
 * `.cmd`/`.bat` de Windows sin reintroducir el problema de citado que
 * `shell: true` traería para los paths que viajan como argv), cwd en la raíz
 * del repo objetivo, cancelable y con timeout.
 */
export function invokeGitReview(
    verb: string,
    args: string[],
    options: InvokeOptions
): Promise<InvokeResult> {
    const {command, args: commandArgs} = resolveCommand(verb, args, options.gitReviewPath);

    return new Promise((resolve) => {
        const child = spawn(command, commandArgs, {
            cwd: options.cwd,
            timeout: options.timeoutMs ?? timeoutForClass(verb, args),
            signal: options.signal,
            ...(options.network ? {env: networkEnv()} : {}),
        });

        let stdout = "";
        let stderr = "";
        child.stdout?.setEncoding("utf8").on("data", (chunk: string) => (stdout += chunk));
        child.stderr?.setEncoding("utf8").on("data", (chunk: string) => (stderr += chunk));

        child.on("error", (error: NodeJS.ErrnoException) => {
            resolve({
                stdout,
                stderr,
                exitCode: null,
                errorCode: error.code,
            });
        });

        child.on("close", (code) => {
            resolve({stdout, stderr, exitCode: code});
        });
    });
}
