import * as assert from "node:assert";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {getProfileArguments} from "@vscode/test-electron/out/util";
import {
    checkUserDataDir,
    createUserDataDir,
    launchArgsFor,
    projectedUserDataDirLength,
    removeUserDataDir,
    socketPathLimit,
    userDataDirLimit,
} from "../integration/helpers/userDataDir";

/**
 * El helper vive en `test/integration/`, pero se prueba acá a propósito: es
 * lo que decide si el host de VS Code puede *arrancar*, así que un spec de
 * integración que dependiera de que arrancó no podría fallar cuando se rompe.
 * Además el bug original sólo se manifestaba en el runner de macOS; estos
 * casos lo evalúan contra `darwin` explícito, así que la regresión cae en
 * cualquier SO, en milisegundos.
 */

/**
 * El user-data-dir exacto que el runner `macos-latest` usaba por default, y el
 * socket que VS Code 1.132 compuso encima: 113 chars contra un `sun_path` de
 * 103. Es el fallo que motivó el helper, anclado al log de CI.
 */
const CI_MACOS_USER_DATA =
    "/Users/runner/work/git-review-workflow/git-review-workflow/vscode-extension/.vscode-test/user-data";
const CI_MACOS_SOCKET = `${CI_MACOS_USER_DATA}/1.13-main.sock`;

describe("socketPathLimit", () => {
    it("aplica el sun_path de cada plataforma", () => {
        assert.strictEqual(socketPathLimit("darwin"), 103);
        assert.strictEqual(socketPathLimit("linux"), 107);
    });

    it("no limita en Windows, que usa named pipes", () => {
        assert.strictEqual(socketPathLimit("win32"), Number.POSITIVE_INFINITY);
    });

    it("cae al más estricto en un POSIX desconocido", () => {
        assert.strictEqual(socketPathLimit("freebsd"), 103);
    });
});

describe("userDataDirLimit", () => {
    it("descuenta el basename del socket y el separador", () => {
        assert.strictEqual(userDataDirLimit("darwin"), 78);
        assert.strictEqual(userDataDirLimit("linux"), 82);
    });

    it("es infinito en Windows", () => {
        assert.strictEqual(userDataDirLimit("win32"), Number.POSITIVE_INFINITY);
    });
});

describe("checkUserDataDir", () => {
    it("el path del socket que reventó el CI de macOS medía 113", () => {
        assert.strictEqual(CI_MACOS_SOCKET.length, 113);
        assert.ok(CI_MACOS_SOCKET.length > socketPathLimit("darwin"));
    });

    it("rechaza el user-data-dir por default del runner de macOS", () => {
        const problem = checkUserDataDir(CI_MACOS_USER_DATA, "darwin");
        assert.ok(problem, "debería rechazarlo");
        assert.ok(problem.includes(CI_MACOS_USER_DATA), `el mensaje no nombra el directorio: ${problem}`);
        assert.ok(problem.includes("98"), `el mensaje no dice el largo real: ${problem}`);
        assert.ok(problem.includes("78"), `el mensaje no dice el máximo: ${problem}`);
    });

    it("también lo rechaza en Linux: ubuntu zafa por XDG_RUNTIME_DIR, no por margen", () => {
        // El mismo layout en /home/runner mide 112, sobre el sun_path de 107.
        // Si Linux dependiera del user-data-dir (contenedor sin XDG_RUNTIME_DIR)
        // fallaría igual que macOS.
        const onLinux = CI_MACOS_USER_DATA.replace("/Users/", "/home/");
        assert.strictEqual(`${onLinux}/1.13-main.sock`.length, 112);
        assert.ok(checkUserDataDir(onLinux, "linux"), "debería rechazarlo también en Linux");
    });

    it("acepta cualquier largo en Windows", () => {
        assert.strictEqual(checkUserDataDir(CI_MACOS_USER_DATA, "win32"), undefined);
    });

    it("acepta el largo exacto del límite y rechaza uno más", () => {
        const atLimit = `/${"a".repeat(userDataDirLimit("darwin") - 1)}`;
        assert.strictEqual(atLimit.length, 78);
        assert.strictEqual(checkUserDataDir(atLimit, "darwin"), undefined);
        assert.ok(checkUserDataDir(`${atLimit}a`, "darwin"), "79 chars ya no debería entrar");
    });
});

describe("projectedUserDataDirLength", () => {
    it("entra en el límite de macOS desde el TMPDIR por default del sistema", () => {
        // Formato real de macOS: /var/folders/<2>/<30>/T
        const macTmp = "/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T";
        assert.strictEqual(macTmp.length, 48);
        assert.strictEqual(projectedUserDataDirLength(macTmp), 62);
        assert.ok(projectedUserDataDirLength(macTmp) <= userDataDirLimit("darwin"));
    });

    it("entra en el límite de macOS desde el temp del runner de GitHub", () => {
        const runnerTmp = "/Users/runner/work/_temp";
        assert.ok(projectedUserDataDirLength(runnerTmp) <= userDataDirLimit("darwin"));
    });
});

describe("createUserDataDir", () => {
    const created: string[] = [];

    afterEach(() => {
        while (created.length > 0) {
            removeUserDataDir(created.pop() as string);
        }
    });

    it("crea un directorio bajo el temp del sistema que pasa el chequeo", () => {
        const dir = createUserDataDir();
        created.push(dir);
        assert.ok(fs.statSync(dir).isDirectory(), "no creó el directorio");
        assert.strictEqual(path.dirname(dir), fs.realpathSync(os.tmpdir()));
        assert.strictEqual(checkUserDataDir(dir), undefined);
    });

    it("da un directorio distinto por llamada, para que dos corridas no compartan socket", () => {
        const first = createUserDataDir();
        created.push(first);
        const second = createUserDataDir();
        created.push(second);
        assert.notStrictEqual(first, second);
    });

    it("removeUserDataDir lo borra", () => {
        const dir = createUserDataDir();
        fs.writeFileSync(path.join(dir, "residuo.txt"), "x");
        removeUserDataDir(dir);
        assert.strictEqual(fs.existsSync(dir), false);
    });
});

describe("launchArgsFor", () => {
    it("abre el workspace y fija el user-data-dir", () => {
        assert.deepStrictEqual(launchArgsFor("/tmp/repo", "/tmp/ud"), [
            "/tmp/repo",
            "--user-data-dir=/tmp/ud",
        ]);
    });

    // Los dos siguientes prueban el contrato con test-electron contra el
    // paquete instalado, no contra una copia de su regla: `getProfileArguments`
    // es la función que en runTest.js decide si agregar el default largo.
    it("desactiva el --user-data-dir por default de test-electron", () => {
        const added = getProfileArguments(launchArgsFor("/tmp/repo", "/tmp/ud"));
        assert.deepStrictEqual(
            added.filter((arg) => arg.startsWith("--user-data-dir")),
            [],
            `test-electron agregó su propio user-data-dir: ${added.join(" ")}`,
        );
    });

    it("sin el flag, test-electron sí agrega el default atado al checkout", () => {
        // Control positivo: sin esto, el test de arriba también pasaría si
        // `getProfileArguments` dejara de agregar nada.
        const added = getProfileArguments(["/tmp/repo"]);
        const dataDir = added.find((arg) => arg.startsWith("--user-data-dir="));
        assert.ok(dataDir, `esperaba un user-data-dir por default: ${added.join(" ")}`);
        assert.ok(
            dataDir.includes(`.vscode-test${path.sep}user-data`),
            `el default dejó de colgar de .vscode-test/: ${dataDir}`,
        );
    });
});
