import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

/**
 * Dónde ponemos el `--user-data-dir` del host de pruebas, y por qué no en el
 * default de `@vscode/test-electron`.
 *
 * VS Code nombra el socket IPC de su proceso main
 * `<user-data-dir>/<version>-main.sock`, y en POSIX un path de socket no puede
 * pasar de `sizeof(sockaddr_un.sun_path) - 1`: 103 chars en Darwin/BSD, 107 en
 * Linux. Pasado el límite VS Code avisa por stderr pero intenta el `bind()`
 * igual, el main muere con `EINVAL` y la suite entera cae con un `exit 1` que
 * no menciona ningún test.
 *
 * El default de test-electron es `<extensionRoot>/.vscode-test/user-data`
 * (`getProfileArguments`, out/util.js), y en un runner de GitHub el
 * `extensionRoot` arranca con el nombre del repo duplicado
 * (`/Users/runner/work/git-review-workflow/git-review-workflow/...`): 113
 * chars de socket. Explota sólo en macOS, pero **no por margen** — ese mismo
 * path mide 112 en Linux, también por encima de 107. Ubuntu zafa porque VS
 * Code, en POSIX, prefiere `XDG_RUNTIME_DIR` (definida en los runners) sobre
 * el user-data-dir y sólo cae a éste si no existe; Windows usa named pipes,
 * donde el límite no aplica. O sea: correr la suite en un contenedor Linux sin
 * `XDG_RUNTIME_DIR` y con el checkout en un path largo reproduce el mismo
 * `EINVAL`.
 *
 * La salida es dejar de depender del largo del checkout: un directorio propio
 * bajo el temp del sistema, corto y verificado antes de lanzar nada.
 */

/** `sizeof(sockaddr_un.sun_path) - 1`, por plataforma. */
const SUN_PATH_MAX: Partial<Record<NodeJS.Platform, number>> = {
    darwin: 103,
    linux: 107,
};

/** El más estricto de los conocidos: el default para cualquier POSIX que no listemos. */
const SUN_PATH_MAX_FALLBACK = 103;

/**
 * Lo que VS Code le appendea al user-data-dir para formar el socket.
 * Observado: `1.13-main.sock` (14 chars) con VS Code 1.132. Reservamos 24 para
 * que una versión más larga o un `type` distinto no nos deje otra vez al filo.
 */
export const SOCKET_BASENAME_BUDGET = 24;

const PREFIX = "grv-ud-";
/** `mkdtemp` reemplaza el sufijo por 6 caracteres aleatorios. */
const MKDTEMP_RANDOM_LENGTH = 6;

/** Largo máximo del path del socket. `Infinity` en Windows: son named pipes. */
export function socketPathLimit(platform: NodeJS.Platform): number {
    if (platform === "win32") {
        return Number.POSITIVE_INFINITY;
    }
    return SUN_PATH_MAX[platform] ?? SUN_PATH_MAX_FALLBACK;
}

/** Largo máximo del user-data-dir: el del socket, menos su basename y el separador. */
export function userDataDirLimit(platform: NodeJS.Platform): number {
    const limit = socketPathLimit(platform);
    return limit === Number.POSITIVE_INFINITY ? limit : limit - SOCKET_BASENAME_BUDGET - 1;
}

/** El largo que tendría el directorio creado bajo `tmpRoot`, sin crear nada. */
export function projectedUserDataDirLength(tmpRoot: string): number {
    return tmpRoot.length + 1 + PREFIX.length + MKDTEMP_RANDOM_LENGTH;
}

/**
 * `undefined` si `dir` sirve como user-data-dir en `platform`; si no, el
 * mensaje que explica por qué. Devolver el mensaje en vez de tirar deja que el
 * test lo afirme sin capturar excepciones.
 */
export function checkUserDataDir(dir: string, platform: NodeJS.Platform = process.platform): string | undefined {
    const limit = userDataDirLimit(platform);
    if (dir.length <= limit) {
        return undefined;
    }
    return `user-data-dir demasiado largo para ${platform}: ${dir.length} chars y el máximo es ${limit}, `
        + `porque el socket IPC de VS Code (<user-data-dir>/<version>-main.sock) no puede pasar de `
        + `${socketPathLimit(platform)}. Usá un TMPDIR más corto. Directorio: ${dir}`;
}

/**
 * Crea el user-data-dir del host y verifica que el socket vaya a entrar.
 * Falla acá —con el largo y el límite a la vista— en vez de dejar que el
 * editor muera después con un `EINVAL` que no dice qué path lo causó.
 */
export function createUserDataDir(): string {
    // realpath: VS Code resuelve el directorio antes de componer el socket, así
    // que el largo que importa es el del path resuelto (en macOS `os.tmpdir()`
    // devuelve `/var/folders/...`, ya real; en Windows expande el `~1` del 8.3).
    const root = fs.realpathSync(os.tmpdir());
    const dir = fs.mkdtempSync(path.join(root, PREFIX));
    const problem = checkUserDataDir(dir);
    if (problem) {
        removeUserDataDir(dir);
        throw new Error(problem);
    }
    return dir;
}

/**
 * Los args de lanzamiento del host. El `--user-data-dir=` explícito es lo que
 * hace que `getProfileArguments` de test-electron no agregue el suyo: chequea
 * con `hasArg`, que matchea `--user-data-dir` exacto o con `=` (out/util.js).
 */
export function launchArgsFor(workspaceDir: string, userDataDir: string): string[] {
    return [workspaceDir, `--user-data-dir=${userDataDir}`];
}

export function removeUserDataDir(dir: string): void {
    // Misma tolerancia que `cleanupRepo`: en Windows el borrado puede tirar
    // EPERM si el host todavía no soltó un handle, y un directorio huérfano en
    // %TEMP% no debe pintar de rojo una suite que ya pasó.
    try {
        fs.rmSync(dir, {recursive: true, force: true, maxRetries: 15, retryDelay: 200});
    } catch (err) {
        const code = (err as NodeJS.ErrnoException).code;
        if (code === "EPERM" || code === "EBUSY" || code === "ENOTEMPTY") {
            return;
        }
        throw err;
    }
}
