/**
 * Clasificación del fallo de `git review start` (contracts/cli-invocation.md §
 * "Clasificar no es parsear"). Módulo sin dependencia de `vscode` a propósito
 * — igual que `staleGuard.ts`/`situation.ts` —, para que la lógica se pruebe
 * sin host y `startReview.ts` sólo se encargue de la UI (mostrar el error,
 * ofrecer el botón).
 */
export type StartFailureCategory = "network" | "repository";

/**
 * Los fragmentos de **stderr de git** (no del verbo) que delatan que `start`
 * falló tratando de tocar la red: un fetch sin credenciales válidas, un
 * remoto que no responde, o el entorno no interactivo (research.md Decisión
 * 5) rechazando un pedido de contraseña. "could not update from" es la frase
 * fija que el propio `start` antepone a CUALQUIER fallo de fetch
 * (`git fetch --quiet "$remote" || die "could not update from $remote"`,
 * bin/git-review-verbs/start), así que por sí sola ya cubre variantes de
 * git/ssh/http que cambian de una versión o un transporte a otro, sin tener
 * que enumerarlas todas.
 */
const NETWORK_MARKERS = [
    "could not update from",
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
 * Cita un argumento para reproducirlo en una terminal (`Run in Terminal`):
 * literal cuando es "seguro" en cualquier shell común, entre comillas dobles
 * si no. No es un citado universal —no cubre `$`/backticks bajo PowerShell,
 * por ejemplo— porque lo que produce es texto para que una persona lo lea y
 * confirme antes de que corra, no un argv que otro proceso vaya a parsear.
 */
export function quoteForTerminal(value: string): string {
    // Sin guion inicial a propósito, aunque el `--` que siempre lo precede ya
    // lo vuelve inofensivo ahí: quoted, un nombre que empieza como una opción
    // se lee sin ambigüedad si alguien copia sólo ese token suelto.
    return /^[\w./][\w./-]*$/.test(value) ? value : `"${value.replace(/"/g, '\\"')}"`;
}
