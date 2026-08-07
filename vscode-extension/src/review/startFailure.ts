/**
 * Clasificación del fallo de `git review start` (contracts/cli-invocation.md §
 * "Clasificar no es parsear"). Módulo sin dependencia de `vscode` a propósito
 * — igual que `staleGuard.ts`/`situation.ts` —, para que la lógica se pruebe
 * sin host y `startReview.ts` sólo se encargue de la UI (mostrar el error,
 * ofrecer el botón).
 */
export type StartFailureCategory = "network" | "repository";

/**
 * Los fragmentos de **stderr de git** que delatan que `start` falló tratando
 * de tocar la red: un fetch sin credenciales válidas, un remoto que no
 * responde, o el entorno no interactivo (research.md Decisión 5) rechazando
 * un pedido de contraseña. Deliberadamente NO incluye "could not update
 * from" — esa frase es el `die()` del propio verbo
 * (`bin/git-review-verbs/start`: `git fetch --quiet "$remote" || die "could
 * not update from $remote"`), no stderr de git, y el contrato ("Clasificar no
 * es parsear") sólo autoriza mirar el de git. Es además redundante: `git
 * fetch` sigue escribiendo su propio stderr antes de que el `die` lo haga, así
 * que las marcas de abajo ya cubren el mismo fallo sin cruzar esa frontera.
 */
const NETWORK_MARKERS = [
    "could not resolve host",
    "could not read from remote repository",
    "connection timed out",
    "connection refused",
    "unable to access",
    "could not read username",
    "could not read password",
    "authentication failed",
    "permission denied (publickey)",
    "terminal prompts disabled",
];

/**
 * Clasifica el fallo de `start` para decidir si ofrecer *Run in Terminal*: mira
 * el stderr de git que el verbo propaga, nunca la salida de un verbo de git
 * review para derivar el estado de la review — ese sigue viniendo siempre de
 * `status --porcelain`, después del refresh que sigue a la invocación.
 *
 * Credenciales y red se colapsan deliberadamente en una sola categoría
 * ("network"): separar con precisión "pide credenciales" de "el remoto no
 * responde" depende de mensajes que varían entre versiones y transportes de
 * git — el riesgo que research.md ya deja registrado, con la salida que el
 * brief de esta fase autoriza explícitamente. Equivocarse hacia el lado
 * ruidoso (ofrecer el escape de más) es inocuo; equivocarse hacia el
 * silencioso deja a alguien mirando un timeout sin salida (SC-007). Todo lo
 * que no matchea ninguna marca es "repository": working tree sucio, rama
 * inexistente, review ya existente — el diagnóstico de la CLI y nada más.
 */
export function classifyStartFailure(stderr: string): StartFailureCategory {
    const text = stderr.toLowerCase();
    return NETWORK_MARKERS.some((marker) => text.includes(marker)) ? "network" : "repository";
}

/**
 * Cita un argumento para reproducirlo en una terminal integrada (`Run in
 * Terminal`). El host de VS Code en Windows suele abrir PowerShell; en
 * Linux/macOS, un shell POSIX. `$` y backticks en comillas dobles de
 * PowerShell se expanden — por eso en win32 se usa comilla simple (literal,
 * con `''` para embeber `'`). En POSIX se mantienen comillas dobles con
 * escape de `"`.
 *
 * Es texto para que una persona lo vea y la terminal lo ejecute al pegarlo,
 * no un argv de spawn.
 *
 * @param platform inyectable en tests; por defecto `process.platform`.
 */
export function quoteForTerminal(
    value: string,
    platform: NodeJS.Platform = process.platform
): string {
    if (platform === "win32") {
        // Token simple sin metacaracteres de PowerShell ni espacio: literal.
        // Guion inicial se cita para que no se lea como flag al copiar suelto.
        if (/^[\w./\\-]+$/.test(value) && !value.startsWith("-")) {
            return value;
        }
        // Single-quoted PS string: todo literal salvo '' → '
        return `'${value.replace(/'/g, "''")}'`;
    }
    // POSIX: sin guion inicial a propósito (mismo criterio que antes).
    return /^[\w./][\w./-]*$/.test(value) ? value : `"${value.replace(/"/g, '\\"')}"`;
}
