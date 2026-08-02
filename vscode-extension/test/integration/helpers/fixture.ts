import * as cp from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

/**
 * Construye repos fixture invocando el `bin/git-review` real del checkout
 * (research.md Decisión 11, "deuda anotada"): un fixture de salida porcelain
 * escrita a mano probaría el parser contra sí mismo.
 */
const REPO_ROOT = path.resolve(__dirname, "../../../..");
export const GIT_REVIEW_DISPATCHER = path.join(REPO_ROOT, "bin", "git-review");
const REPO_BIN_DIR = path.join(REPO_ROOT, "bin");

/**
 * `bin/git-review` es un script `#!/usr/bin/env sh`: en Windows, invocarlo
 * directo con `spawnSync` (sin shell) falla — CreateProcess no entiende
 * shebangs, sólo `git.exe` sabe ejecutarlo vía su propia capa MSYS. Por eso el
 * fixture usa siempre `git review <verbo>` con `bin/` al frente del PATH,
 * igual que `invoke.ts` en producción (research.md Decisión 3): es el mismo
 * mecanismo de descubrimiento, y el único portable en los tres SO.
 */
function envWithBinOnPath(): NodeJS.ProcessEnv {
    const pathKey = Object.keys(process.env).find((k) => k.toUpperCase() === "PATH") ?? "PATH";
    const existing = process.env[pathKey] ?? "";
    return {...process.env, [pathKey]: `${REPO_BIN_DIR}${path.delimiter}${existing}`};
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

/** Crea `branch` desde `main` con `files` committeados encima, y vuelve a `main`. */
export function createBranchWithChanges(repo: FixtureRepo, branch: string, files: Record<string, string>): void {
    git(["checkout", "-b", branch], repo.dir);
    for (const [file, content] of Object.entries(files)) {
        writeFile(repo, file, content);
    }
    git(["add", "."], repo.dir);
    git(["commit", "-m", `changes for ${branch}`], repo.dir);
    git(["checkout", "main"], repo.dir);
}

/** Crea `branch` desde `main` con un commit separado por entrada de `commits`. */
export function createBranchWithCommits(repo: FixtureRepo, branch: string, commits: Array<{
    file: string;
    content: string;
    message: string
}>): void {
    git(["checkout", "-b", branch], repo.dir);
    for (const commit of commits) {
        writeFile(repo, commit.file, commit.content);
        git(["add", "."], repo.dir);
        git(["commit", "-m", commit.message], repo.dir);
    }
    git(["checkout", "main"], repo.dir);
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
}

function escapeRegExp(s: string): string {
    return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function cleanupRepo(repo: FixtureRepo): void {
    fs.rmSync(repo.dir, {recursive: true, force: true});
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
