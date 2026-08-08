import * as cp from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

/**
 * Raíz del checkout: el primer ancestro que contiene `bin/git-review`.
 *
 * Contar `..` no sirve — este archivo corre compilado desde
 * `out/test/integration/helpers/` (`test:integration` es `tsc -p . --outDir
 * out && node ./out/test/integration/runTests.js`), un nivel más profundo que
 * el fuente, así que un conteo fijo se descalibra con el `outDir`. Y falla en
 * silencio: `REPO_BIN_DIR` queda apuntando a un directorio inexistente, el
 * PATH que arma `envWithBinOnPath` no surte efecto y los fixtures resuelven
 * `git review` desde el PATH del sistema — o sea contra la CLI *instalada*,
 * que puede ser otra versión que la del checkout que se está probando. Por eso
 * acá se falla fuerte en vez de degradar a un default.
 */
function findRepoRoot(startDir: string): string {
    let dir = startDir;
    for (; ;) {
        if (fs.existsSync(path.join(dir, "bin", "git-review"))) {
            return dir;
        }
        const parent = path.dirname(dir);
        if (parent === dir) {
            throw new Error(`fixture: no encontré bin/git-review subiendo desde ${startDir}`);
        }
        dir = parent;
    }
}

/**
 * Construye repos fixture invocando el `bin/git-review` real del checkout
 * (research.md Decisión 11, "deuda anotada"): un fixture de salida porcelain
 * escrita a mano probaría el parser contra sí mismo.
 */
const REPO_ROOT = findRepoRoot(__dirname);
export const GIT_REVIEW_DISPATCHER = path.join(REPO_ROOT, "bin", "git-review");
const REPO_BIN_DIR = path.join(REPO_ROOT, "bin");

/** En Windows la variable puede venir como `Path`, no `PATH`. */
function pathKey(): string {
    return Object.keys(process.env).find((k) => k.toUpperCase() === "PATH") ?? "PATH";
}

/** Idempotente: `runTests` ya deja `bin/` al frente del PATH que heredamos. */
function withBinFirst(existing: string): string {
    const prefix = `${REPO_BIN_DIR}${path.delimiter}`;
    return existing.startsWith(prefix) ? existing : `${prefix}${existing}`;
}

/**
 * `bin/git-review` es un script `#!/usr/bin/env sh`: en Windows, invocarlo
 * directo con `spawnSync` (sin shell) falla — CreateProcess no entiende
 * shebangs, sólo `git.exe` sabe ejecutarlo vía su propia capa MSYS. Por eso el
 * fixture usa siempre `git review <verbo>` con `bin/` al frente del PATH,
 * igual que `invoke.ts` en producción (research.md Decisión 3): es el mismo
 * mecanismo de descubrimiento, y el único portable en los tres SO.
 */
function envWithBinOnPath(): NodeJS.ProcessEnv {
    const key = pathKey();
    return {...process.env, [key]: withBinFirst(process.env[key] ?? "")};
}

/**
 * Pone el `bin/` del checkout al frente del PATH **de este proceso**, para que
 * lo herede el host de VS Code y, con él, la extensión: `invokeGitReview`
 * spawnea `git review` con `process.env` (invoke.ts), y `runTests` lanza el
 * host con `Object.assign({}, process.env, testRunnerEnv)`.
 *
 * Sin esto la suite prueba dos CLIs a la vez — el fixture arma el repo con la
 * del checkout y el panel lo lee con la que haya *instalada* en el PATH del
 * sistema, que puede ser otra versión. Es lo que antes obligaba a correr
 * `./install.sh` para que la suite pasara.
 */
export function putBinOnPath(): void {
    const key = pathKey();
    process.env[key] = withBinFirst(process.env[key] ?? "");
}

export interface CommandResult {
    stdout: string;
    stderr: string;
    status: number;
}

function runOrThrow(command: string, args: string[], cwd: string): string {
    const result = cp.spawnSync(command, args, {cwd, encoding: "utf8", env: envWithBinOnPath()});
    if (result.status !== 0) {
        throw new Error(`${command} ${args.join(" ")} (cwd=${cwd}) failed with ${result.status}:\n${result.stderr}`);
    }
    return result.stdout;
}

export function git(args: string[], cwd: string): string {
    return runOrThrow("git", args, cwd);
}

export function gitReview(args: string[], cwd: string): CommandResult {
    const result = cp.spawnSync("git", ["review", ...args], {
        cwd,
        encoding: "utf8",
        env: envWithBinOnPath()
    });
    return {stdout: result.stdout ?? "", stderr: result.stderr ?? "", status: result.status ?? -1};
}

export function gitReviewOrThrow(args: string[], cwd: string): CommandResult {
    const result = gitReview(args, cwd);
    if (result.status !== 0) {
        throw new Error(`git-review ${args.join(" ")} (cwd=${cwd}) failed with ${result.status}:\n${result.stderr}`);
    }
    return result;
}

export interface FixtureRepo {
    dir: string;
    gitReviewPath: string;
}

/** Un repo git limpio, con `main` como rama base y `reviewworkflow.base` fijado. */
export function createTempRepo(): FixtureRepo {
    const dir = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), "grv-fixture-"));
    git(["init", "--initial-branch=main"], dir);
    git(["config", "user.email", "test@example.com"], dir);
    git(["config", "user.name", "Test"], dir);
    // Determinístico entre SO: sin esto, Windows normaliza LF a CRLF al
    // hacer checkout y los tests de contenido de archivo dependerían de la
    // plataforma que corre la suite.
    git(["config", "core.autocrlf", "false"], dir);
    git(["config", "reviewworkflow.base", "main"], dir);
    fs.writeFileSync(path.join(dir, "README.md"), "# fixture\n");
    git(["add", "."], dir);
    git(["commit", "-m", "initial"], dir);
    return {dir, gitReviewPath: GIT_REVIEW_DISPATCHER};
}

export function writeFile(repo: FixtureRepo, relPath: string, content: string): void {
    const filePath = path.join(repo.dir, relPath);
    fs.mkdirSync(path.dirname(filePath), {recursive: true});
    fs.writeFileSync(filePath, content);
}

function hasRemote(repo: FixtureRepo, name = "origin"): boolean {
    const result = cp.spawnSync("git", ["remote"], {
        cwd: repo.dir,
        encoding: "utf8",
        env: envWithBinOnPath(),
    });
    return (result.stdout ?? "")
        .split(/\r?\n/)
        .map((line) => line.trim())
        .includes(name);
}

/**
 * Espeja un tip local en `refs/remotes/origin/<branch>` sin `git push`.
 * El self-origin del fixture es un working tree (no bare): push está denegado
 * por defecto. Los probes de `config --porcelain` (origen Remote) no fetchean y
 * hard-failan si falta el tracking ref — este helper es el puente.
 */
export function mirrorRemoteTracking(repo: FixtureRepo, branch: string, remote = "origin"): void {
    const tip = git(["rev-parse", branch], repo.dir).trim();
    git(["update-ref", `refs/remotes/${remote}/${branch}`, tip], repo.dir);
}

/** Crea `branch` desde `main` con `files` committeados encima, y vuelve a `main`. */
export function createBranchWithChanges(repo: FixtureRepo, branch: string, files: Record<string, string>): void {
    // -B: el fixture es compartido; un escenario previo puede haber dejado la rama.
    git(["checkout", "-B", branch, "main"], repo.dir);
    for (const [file, content] of Object.entries(files)) {
        writeFile(repo, file, content);
    }
    git(["add", "."], repo.dir);
    git(["commit", "-m", `changes for ${branch}`], repo.dir);
    git(["checkout", "main"], repo.dir);
    if (hasRemote(repo)) {
        mirrorRemoteTracking(repo, branch);
    }
}

/** Crea `branch` desde `main` con un commit separado por entrada de `commits`. */
export function createBranchWithCommits(repo: FixtureRepo, branch: string, commits: Array<{
    file: string;
    content: string;
    message: string
}>): void {
    git(["checkout", "-B", branch, "main"], repo.dir);
    for (const commit of commits) {
        writeFile(repo, commit.file, commit.content);
        git(["add", "."], repo.dir);
        git(["commit", "-m", commit.message], repo.dir);
    }
    git(["checkout", "main"], repo.dir);
    if (hasRemote(repo)) {
        mirrorRemoteTracking(repo, branch);
    }
}

/** `git review start <branch> --offline [...extraArgs]` — sin remoto, contra el checkout local. */
export function startReview(repo: FixtureRepo, branch: string, extraArgs: string[] = []): CommandResult {
    return gitReviewOrThrow(["start", branch, "--offline", ...extraArgs], repo.dir);
}

export interface WalkthroughEntry {
    path: string;
    why: string;
    key?: boolean;
}

/**
 * Escribe un walkthrough válido para `branch`: corre `checkout`, edita el
 * skeleton de `walkthrough init` con `entries` (en el orden dado) y el
 * `headsUp` provisto, corre `walkthrough build` para validar/renumerar, y
 * commitea `.review/walkthrough.md`. Deja el repo de vuelta en `main`.
 */
export function addWalkthrough(repo: FixtureRepo, branch: string, entries: WalkthroughEntry[], headsUp = "Nada delicado en este PR de prueba."): void {
    git(["checkout", branch], repo.dir);
    // Defensivo: un review abortado en el repo compartido puede dejar
    // `.review/walkthrough.md` sin trackear en el working tree (git switch
    // --discard-changes des-stagea una adición nueva, pero no la borra) —
    // --force evita que init se niegue a pisarlo.
    gitReviewOrThrow(["walkthrough", "init", "--force"], repo.dir);

    const wtPath = path.join(repo.dir, ".review", "walkthrough.md");
    let content = fs.readFileSync(wtPath, "utf8");

    content = content.replace(
        /<!-- heads-up:[\s\S]*?-->/,
        headsUp
    );

    let order = 1;
    for (const entry of entries) {
        const headingRe = new RegExp(`## \\?\\. ${escapeRegExp(entry.path)}\\n<!-- why: -->`);
        const why = entry.key ? `> key\n${entry.why}` : entry.why;
        const before = content;
        content = content.replace(headingRe, `## ${order}. ${entry.path}\n${why}`);
        if (content === before) {
            throw new Error(`addWalkthrough: no encontré el placeholder de ${entry.path} en el skeleton de ${branch}`);
        }
        order++;
    }

    // Cualquier archivo que el rango real trae y `entries` no cubrió explícitamente
    // (drift entre lo que el caller listó y lo que el diff del branch trae de
    // verdad) recibe un why genérico en vez de dejar el build sin poder validar.
    content = content.replace(/## \?\. (\S.*)\n<!-- why: -->/g, (_match, leftoverPath: string) => `## ${order++}. ${leftoverPath}\nauto-filled why for ${leftoverPath}`);

    fs.writeFileSync(wtPath, content);
    gitReviewOrThrow(["walkthrough", "build"], repo.dir);

    git(["add", ".review/walkthrough.md"], repo.dir);
    git(["commit", "-m", "add walkthrough"], repo.dir);
    git(["checkout", "main"], repo.dir);
    // Tip moved after the walkthrough commit; keep origin tracking in sync for
    // remote probes (config --porcelain / start Remote without a prior fetch).
    if (hasRemote(repo)) {
        mirrorRemoteTracking(repo, branch);
    }
}

function escapeRegExp(s: string): string {
    return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Los dos modos de fixture "sin review" que el asistente de inicio necesita
 * (T029, prerequisito de start-review.spec.ts): `createTempRepo` ya deja
 * `reviewworkflow.base` fijada en `main`, así que "con base" es el estado por
 * default y "sin base" es quitarla — nunca al revés, para que un test que se
 * olvida de restaurarla no deje a los que corren después sin base por
 * accidente (el estado por default sigue siendo el mismo que ya usaban).
 */
export function withoutBaseConfigured(repo: FixtureRepo): void {
    git(["config", "--unset", "reviewworkflow.base"], repo.dir);
}

export function withBaseConfigured(repo: FixtureRepo, branch = "main"): void {
    git(["config", "reviewworkflow.base", branch], repo.dir);
}

/**
 * `git review start` sin `--local`/`--offline` hace un `fetch` real del
 * remoto (contracts/cli-invocation.md § start): el fixture compartido no
 * tiene ninguno, así que el asistente de inicio —que en esta fase no ofrece
 * todavía la UI de origen y siempre revisa `remote`— necesita uno para
 * arrancar. Un remoto que apunta al propio directorio alcanza: git soporta el
 * transporte local, y fetch trae los mismos objetos que ya existen ahí mismo.
 * Deliberadamente NO agregado por default en `createTempRepo` — nada más lo
 * usa hoy, y agregar un remoto real cambia el "no hay origin" que otros
 * fixtures asumen sin decirlo.
 */
export function addSelfOrigin(repo: FixtureRepo): void {
    git(["remote", "add", "origin", repo.dir], repo.dir);
    // Base tracking ref for remote-layout offers (no fetch in config porcelain).
    mirrorRemoteTracking(repo, "main");
}

export function removeOrigin(repo: FixtureRepo): void {
    git(["remote", "remove", "origin"], repo.dir);
}

export function cleanupRepo(repo: FixtureRepo): void {
    // En Windows el borrado tira EPERM si git o el propio host de pruebas
    // todavía tienen un handle abierto sobre el repo temporal; no es un fallo
    // del test. Reintentar + tragar el error residual: un fixture huérfano en
    // %TEMP% no debe pintar de rojo una suite que ya pasó.
    try {
        fs.rmSync(repo.dir, {recursive: true, force: true, maxRetries: 15, retryDelay: 200});
    } catch (err) {
        const code = (err as NodeJS.ErrnoException).code;
        if (code === "EPERM" || code === "EBUSY" || code === "ENOTEMPTY") {
            return;
        }
        throw err;
    }
}

/**
 * El repo fixture único que `runTests.ts` crea y abre como workspace del
 * host de pruebas (`GIT_REVIEW_FIXTURE_DIR`). Las specs lo comparten y
 * mutan su estado con `git`/`git review` entre escenarios, en vez de abrir
 * una ventana de VS Code nueva por cada uno.
 */
export function sharedFixtureRepo(): FixtureRepo {
    const dir = process.env.GIT_REVIEW_FIXTURE_DIR;
    if (!dir) {
        throw new Error("GIT_REVIEW_FIXTURE_DIR is not set; run the integration suite via runTests.ts");
    }
    return {dir, gitReviewPath: GIT_REVIEW_DISPATCHER};
}

/** Vuelve el fixture compartido a un estado sin review, tolerante a que ya no haya una. */
export function abortReview(repo: FixtureRepo): void {
    const cur = cp.spawnSync("git", ["symbolic-ref", "--quiet", "--short", "HEAD"], {
        cwd: repo.dir,
        encoding: "utf8"
    }).stdout.trim();
    if (cur.startsWith("review/")) {
        gitReview(["abort"], repo.dir);
    }
    cp.spawnSync("git", ["checkout", "main"], {cwd: repo.dir, encoding: "utf8"});
}
