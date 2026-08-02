import spawn from "cross-spawn";

export interface InvokeOptions {
    cwd: string;
    /** Valor crudo del ajuste `gitReview.path`; vacío = invocar `git review`. */
    gitReviewPath?: string;
    timeoutMs?: number;
    signal?: AbortSignal;
}

export interface InvokeResult {
    stdout: string;
    stderr: string;
    /** null cuando el proceso nunca llegó a correr (p. ej. ENOENT). */
    exitCode: number | null;
    /** Código de error de Node cuando el spawn falló (p. ej. "ENOENT"). */
    errorCode?: string;
}

const DEFAULT_TIMEOUT_MS = 15000;
// Extensiones que Windows sabe ejecutar como proceso nativo, incluidos los
// shims `.cmd`/`.bat` de una instalación por npm — cross-spawn ya resuelve
// esos de forma segura (delega en cmd.exe con el escaping correcto, el mismo
// problema detrás de CVE-2024-27980). Lo que cross-spawn NO resuelve es un
// script POSIX sin extensión (`#!/usr/bin/env sh`): ahí sólo `git.exe` sabe
// correrlo, vía su propia capa MSYS (research.md Decisión 3).
const WINDOWS_NATIVE_EXECUTABLE = /\.(exe|cmd|bat)$/i;

interface ResolvedCommand {
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
 */
function resolveCommand(verb: string, args: string[], gitReviewPath: string | undefined): ResolvedCommand {
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
            timeout: options.timeoutMs ?? DEFAULT_TIMEOUT_MS,
            signal: options.signal,
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
