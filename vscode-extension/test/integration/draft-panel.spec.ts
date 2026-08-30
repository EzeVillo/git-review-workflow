import * as assert from "node:assert";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import {sameDraftFile} from "../../src/review/draftFlow";
import {getTestApi} from "./helpers/extensionApi";
import {
    abortReview,
    addSelfOrigin,
    createBranchWithChanges,
    createBranchWithCommits,
    git,
    gitReviewOrThrow,
    mirrorRemoteTracking,
    removeOrigin,
    sharedFixtureRepo,
    withBaseConfigured,
} from "./helpers/fixture";

/**
 * El bloque de borradores del estado vacío: un orden a medio escribir tiene
 * que verse en el primer vistazo al panel, sin abrir ningún asistente y tras
 * cerrar y reabrir el editor. Se afirma el `PanelModel` (el webview corre en
 * su propio contexto) y el efecto real de cada control sobre disco y git.
 */
function draftPath(repoDir: string, branch: string): string {
    return path.join(repoDir, ".git", "review-walkthrough", `${branch}.md`);
}

/**
 * Vacía el namespace de borradores borrando ARCHIVOS, no directorios: un
 * `rmSync(ns, {recursive: true})` falla en Windows con EPERM mientras la
 * extensión tiene el directorio abierto por su watcher. Es un problema del
 * test, no del producto (`git review forget --draft` sólo hace `rm -f` sobre
 * el archivo); un namespace de directorios vacíos no reporta ningún borrador,
 * porque la CLI lista `*.md`. Sin esto el EPERM deja el archivo en disco y el
 * test siguiente muere en `makeDraft` con "already exists".
 */
function clearDrafts(repoDir: string): void {
    const walk = (dir: string): void => {
        for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) {
                walk(full);
            } else {
                // maxRetries por lo mismo que en fixture.ts al borrar el repo:
                // en Windows un archivo recien tocado puede seguir con un handle
                // encima un instante mas, y ahi rmSync tira EPERM/EBUSY.
                fs.rmSync(full, {force: true, maxRetries: 10, retryDelay: 50});
            }
        }
    };
    const ns = path.join(repoDir, ".git", "review-walkthrough");
    if (fs.existsSync(ns)) {
        walk(ns);
    }
}

/**
 * Espera a que el estado converja: los controles refrescan en background y no
 * hay otra señal cuando lo que se afirma es que NO pasa nada.
 *
 * `until` corta apenas se cumple; sin esa condición son las cuarenta pasadas
 * fijas, que en Windows (cada refresh es un `status --porcelain` real, nueve
 * procesos git a ~50 ms cada uno contra ~1 ms en Linux) se comen el timeout de
 * dos minutos de la suite — así se caían los dos tests de `startFromDraft` ahí,
 * verdes en Linux.
 */
async function settle(
    api: Awaited<ReturnType<typeof getTestApi>>,
    until?: (state: Awaited<ReturnType<typeof api.refresh>>) => boolean
): Promise<void> {
    for (let i = 0; i < 40; i++) {
        await new Promise((resolve) => setTimeout(resolve, 50));
        const state = await api.refresh();
        if (until?.(state)) {
            return;
        }
    }
}

type TestApi = Awaited<ReturnType<typeof getTestApi>>;
type RefreshedState = Awaited<ReturnType<TestApi["refresh"]>>;

function draftReviewStarted(branch: string): (state: RefreshedState) => boolean {
    return (state) =>
        state.situation === "review" &&
        state.state?.branch === `review/${branch}` &&
        state.state.mode === "walk" &&
        state.draft === true;
}

describe("US3: el bloque de borradores del panel", function () {
    this.timeout(120000);
    const repo = sharedFixtureRepo();

    before(() => addSelfOrigin(repo));
    after(() => removeOrigin(repo));

    afterEach(async () => {
        abortReview(repo);
        withBaseConfigured(repo, "main");
        clearDrafts(repo.dir);
        await vscode.commands.executeCommand("workbench.action.closeAllEditors");
    });

    /**
     * Llena un esqueleto conservando todo lo anterior a `## Heads-up`, donde
     * vive el bloque de instrucciones: sobrescribir el archivo entero se
     * llevaría los flags de origen y rango que la CLI devuelve por el registro
     * `draft`, y el borrador dejaría de ser startable.
     */
    function fillDraft(file: string, body: string): void {
        const text = fs.readFileSync(file, "utf8");
        // Con salto de línea al principio: el andamiaje también nombra
        // "## Heads-up" en su propio comentario, y cortar ahí lo partiría.
        const cut = text.indexOf("\n## Heads-up") + 1;
        assert.ok(cut > 0, "el esqueleto trae su seccion Heads-up");
        fs.writeFileSync(file, text.slice(0, cut) + body, "utf8");
    }

    /** Genera el esqueleto de <branch> con la CLI, como haría el asistente. */
    function makeDraft(branch: string, ...flags: string[]): string {
        git(["checkout", "main"], repo.dir);
        gitReviewOrThrow(["walkthrough", "draft", ...flags, "--", branch], repo.dir);
        return draftPath(repo.dir, branch);
    }

    it("dos borradores se dibujan como dos filas, y el cuerpo de siempre sigue debajo", async () => {
        const one = "us3-panel-one";
        const two = "us3-panel-two";
        createBranchWithChanges(repo, one, {"src/a.ts": "a\n", "src/b.ts": "b\n"});
        createBranchWithChanges(repo, two, {"src/c.ts": "c\n"});
        makeDraft(one);
        makeDraft(two);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");
        const model = await api.getPanelModel();

        assert.deepStrictEqual(
            model.drafts.map((d) => d.branch).sort(),
            [one, two].sort()
        );
        // El progreso llega contado por la CLI: un esqueleto recién generado es
        // 0 de N, con N los archivos del rango.
        const first = model.drafts.find((d) => d.branch === one);
        assert.strictEqual(first?.annotated, 0);
        // El total es lo que el ARCHIVO declara, contado por la CLI. Se compara
        // contra las entradas del esqueleto y no contra un numero fijo: el
        // fixture es compartido y otra spec puede haber movido main, con lo que
        // el rango de esta rama cambia sin que este test tenga nada que ver.
        // El +1 es el heads-up: el esqueleto lo deja con su placeholder y build
        // lo rechaza igual que a un why sin llenar, asi que es una unidad mas
        // del par y no una regla aparte.
        const skeleton = fs.readFileSync(first.path, "utf8");
        const declared = skeleton.split("\n").filter((line) => line.startsWith("## ?. ")).length;
        assert.ok(declared > 0, skeleton);
        assert.ok(/^## Heads-up\s*$/m.test(skeleton), "el esqueleto trae su seccion Heads-up");
        assert.strictEqual(first.total, declared + 1);
        assert.ok(fs.existsSync(first?.path ?? ""), `la ruta reportada existe: ${first?.path}`);
        assert.ok(path.isAbsolute(first?.path ?? ""), "la ruta es absoluta");

        // El bloque NO reemplaza el cuerpo: la situación sigue siendo no-review
        // con su Start a review y su configuración.
        assert.strictEqual(model.situation, "no-review");
        assert.strictEqual(model.noBaseConfigured, false);
        assert.strictEqual(model.configuredBase, "main");
    });

    it("un borrador cuya review termino llega al modelo como gastado", async () => {
        const branch = "us3-panel-spent";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        // Escrito entero, y no un esqueleto: un orden con entradas sin llenar
        // nunca se reporta como terminado, diga lo que diga el marcador.
        // fillDraft conserva todo lo anterior al Heads-up, o sea el bloque de
        // instrucciones, que es de donde sale el tip que se compara.
        fillDraft(makeDraft(branch), "## 1. src/a.ts\nmine\n");

        const api = await getTestApi();
        await api.refresh();
        const before = (await api.getPanelModel()).drafts.find((d) => d.branch === branch);
        assert.strictEqual(before?.spent, false, "recien escrito, con su review por delante");

        // Lo que deja una review completa de esa rama: el marcador con el tip
        // que cubrio. El borrador se genero contra ese mismo tip, asi que la
        // CLI lo reporta gastado. Se planta la clave en vez de correr un
        // start/finish/clean entero porque el fixture es compartido y esta
        // spec afirma el cable (campo 8 -> model.spent), no la semantica del
        // marcador -- eso lo cubre tests/forget-draft-reviewed.bats.
        const tip = git(["rev-parse", `origin/${branch}`], repo.dir).trim();
        git(["config", `reviewworkflow.${branch}.reviewed`, tip], repo.dir);

        await api.refresh();
        const after = (await api.getPanelModel()).drafts.find((d) => d.branch === branch);
        assert.strictEqual(after?.spent, true);
        // Y sigue estando: nada se borro por reportarlo gastado.
        assert.ok(fs.existsSync(after?.path ?? ""), "el archivo sigue en disco");

        git(["config", "--unset", `reviewworkflow.${branch}.reviewed`], repo.dir);
    });

    it("con una review activa el bloque no aparece", async () => {
        const branch = "us3-panel-hidden";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        fillDraft(makeDraft(branch), "## 1. src/a.ts\nmine\n");
        gitReviewOrThrow(["walkthrough", "draft", "--build", "--", branch], repo.dir);
        gitReviewOrThrow(["start", branch], repo.dir);

        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        const model = await api.getPanelModel();
        // Una review en curso es siempre lo más importante que el panel tiene
        // para decir; el borrador de otra rama no le compite el cuerpo.
        assert.deepStrictEqual(model.drafts, []);
        assert.strictEqual(model.draft, true, "esta review sí lee un borrador");
    });

    it("Open abre el archivo en la ruta que reportó la CLI", async () => {
        const branch = "us3-panel-open";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        makeDraft(branch);

        const api = await getTestApi();
        await api.refresh();
        // La ruta que se afirma es la QUE REPORTO LA CLI, no una rearmada acá:
        // es la regla del feature, y también la única que resiste el runner de
        // Windows. Ahí `%TEMP%` viene en forma 8.3 (`C:\Users\RUNNER~1\...`),
        // que es lo que el fixture usa para armar rutas, mientras que la CLI
        // resuelve con `git rev-parse --absolute-git-dir` y contesta el nombre
        // largo con barras normales (`C:/Users/runneradmin/...`). Son el mismo
        // archivo y ninguna comparación de texto los iguala.
        const reported = (await api.getPanelModel()).drafts.find(
            (d) => d.branch === branch
        )?.path;
        assert.ok(reported, "la CLI reportó una fila para esta rama");
        api.sendPanelMessage("openDraft", 0);

        // sameDraftFile y no `===`: es la misma comparación que hace el producto
        // para encontrar el documento abierto, separadores y mayúsculas
        // incluidos.
        const opened = (): boolean =>
            vscode.window.visibleTextEditors.some((editor) =>
                sameDraftFile(editor.document.uri.fsPath, reported)
            );
        for (let i = 0; i < 60 && !opened(); i++) {
            await new Promise((resolve) => setTimeout(resolve, 50));
        }
        assert.ok(
            opened(),
            `no se abrió ${reported}: ${vscode.window.visibleTextEditors
                .map((e) => e.document.uri.fsPath)
                .join(", ")}`
        );
    });

    it("Copy for agent deja el texto canonico con la ruta de esa fila", async () => {
        const branch = "us3-panel-copy";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        makeDraft(branch);

        const api = await getTestApi();
        await api.refresh();
        // La ruta sale del reporte de la CLI y no se rearma acá: es lo que el
        // texto copiado tiene que llevar verbatim, y en el runner de Windows una
        // rearmada trae la forma 8.3 de %TEMP% (`RUNNER~1`) contra el nombre
        // largo que resuelve git. La oración sí se afirma literal.
        const file = (await api.getPanelModel()).drafts.find((d) => d.branch === branch)?.path;
        assert.ok(file, "la CLI reportó una fila para esta rama");
        await vscode.env.clipboard.writeText("");
        api.sendPanelMessage("copyDraftPrompt", 0);

        let clip = "";
        for (let i = 0; i < 60; i++) {
            clip = await vscode.env.clipboard.readText();
            if (clip.length > 0) {
                break;
            }
            await new Promise((resolve) => setTimeout(resolve, 50));
        }
        assert.strictEqual(
            clip,
            `Fill in the reading order at ${file}. The instructions are inside the file,` +
            " in the comment at the top. Do not change the file list or the numbering rules."
        );
    });

    it("Validate and start sobre un borrador incompleto muestra el motivo y no cambia nada", async () => {
        const branch = "us3-panel-invalid";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n", "src/b.ts": "b\n"});
        const file = makeDraft(branch);
        const before = fs.readFileSync(file, "utf8");

        const api = await getTestApi();
        await api.refresh();

        const errors: string[] = [];
        const originalError = vscode.window.showErrorMessage;
        (vscode.window as unknown as { showErrorMessage: unknown }).showErrorMessage = async (
            message: string
        ) => {
            errors.push(message);
            return undefined;
        };
        try {
            api.sendPanelMessage("startFromDraft", 0);
            for (let i = 0; i < 100 && errors.length === 0; i++) {
                await new Promise((resolve) => setTimeout(resolve, 50));
            }
        } finally {
            (vscode.window as unknown as {
                showErrorMessage: unknown
            }).showErrorMessage = originalError;
        }

        // El motivo lo escribió la CLI: no hay un segundo vocabulario de validación.
        assert.strictEqual(errors.length, 1, errors.join(" | "));
        assert.ok(errors[0].includes("unfilled"), errors[0]);
        // El borrador quedó byte por byte como estaba, y no hay review.
        assert.strictEqual(fs.readFileSync(file, "utf8"), before);
        assert.strictEqual((await api.refresh()).situation, "no-review");
    });

    it("Validate and start pregunta el recorrido solo cuando el borrador marca key", async () => {
        // La mitad no trivial de FR-029: dos borradores validos, uno CON
        // entradas key y otro sin ellas. El primero pregunta recorrido completo
        // vs esenciales; el segundo arranca directo.
        const withKeys = "us3-keys-yes";
        const noKeys = "us3-keys-no";
        createBranchWithChanges(repo, withKeys, {"src/a.ts": "a\n", "src/b.ts": "b\n"});
        createBranchWithChanges(repo, noKeys, {"src/c.ts": "c\n", "src/d.ts": "d\n"});
        fillDraft(
            makeDraft(withKeys),
            "## 1. src/a.ts\n> key\nstart here\n\n## 2. src/b.ts\nthen b\n"
        );
        fillDraft(makeDraft(noKeys), "## 1. src/c.ts\nfirst\n\n## 2. src/d.ts\nthen d\n");

        const api = await getTestApi();

        async function run(branch: string): Promise<number> {
            await api.refresh();
            const index = (await api.getPanelModel()).drafts.findIndex(
                (d) => d.branch === branch
            );
            assert.ok(index >= 0, `no hay fila para ${branch}`);

            let asked = 0;
            let started = false;
            const originalQuickPick = vscode.window.showQuickPick;
            const originalWarning = vscode.window.showWarningMessage;
            (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick = async (
                items: readonly { keysOnly?: boolean }[]
            ) => {
                if (items[0]?.keysOnly !== undefined) {
                    asked++;
                    return items.find((item) => item.keysOnly === false);
                }
                return undefined;
            };
            (vscode.window as unknown as {
                showWarningMessage: unknown
            }).showWarningMessage = async () => {
                started = true;
                return "Start the review";
            };
            try {
                api.sendPanelMessage("startFromDraft", index);
                for (let i = 0; i < 200 && !started; i++) {
                    await new Promise((resolve) => setTimeout(resolve, 50));
                }
                await settle(api, draftReviewStarted(branch));
            } finally {
                (vscode.window as unknown as {
                    showQuickPick: unknown
                }).showQuickPick = originalQuickPick;
                (vscode.window as unknown as {
                    showWarningMessage: unknown
                }).showWarningMessage = originalWarning;
            }
            assert.strictEqual((await api.refresh()).situation, "review");
            abortReview(repo);
            await api.refresh();
            return asked;
        }

        assert.strictEqual(await run(withKeys), 1, "con entradas key se pregunta");
        assert.strictEqual(await run(noKeys), 0, "sin entradas key no hay nada que elegir");
    });

    it("un borrador hecho con --delta se valida y arranca en verde desde el panel", async () => {
        // FR-029a: con los flags por defecto este camino fallaría SIEMPRE por
        // deriva, sobre un borrador perfectamente válido.
        const branch = "us3-delta-start";
        createBranchWithCommits(repo, branch, [
            {file: "src/a.ts", content: "a\n", message: "first"},
            {file: "src/later.ts", content: "later\n", message: "later"},
        ]);
        mirrorRemoteTracking(repo, branch);
        // El marcador que habria dejado una review anterior: el rango
        // incremental cubre solo lo que vino despues.
        const prev = git(["rev-parse", `${branch}~1`], repo.dir).trim();
        git(["config", `reviewworkflow.${branch}.reviewed`, prev], repo.dir);

        // El rango incremental cubre un solo archivo.
        fillDraft(makeDraft(branch, "--delta"), "## 1. src/later.ts\nthe new bit\n");

        const api = await getTestApi();
        await api.refresh();
        const model = await api.getPanelModel();
        const index = model.drafts.findIndex((d) => d.branch === branch);
        assert.ok(index >= 0);
        assert.strictEqual(model.drafts[index].startable, true);

        let started = false;
        const errors: string[] = [];
        const originalWarning = vscode.window.showWarningMessage;
        const originalError = vscode.window.showErrorMessage;
        (vscode.window as unknown as { showWarningMessage: unknown }).showWarningMessage =
            async () => {
                started = true;
                return "Start the review";
            };
        (vscode.window as unknown as { showErrorMessage: unknown }).showErrorMessage = async (
            message: string
        ) => {
            errors.push(message);
            return undefined;
        };
        try {
            api.sendPanelMessage("startFromDraft", index);
            for (let i = 0; i < 200 && !started && errors.length === 0; i++) {
                await new Promise((resolve) => setTimeout(resolve, 50));
            }
            await settle(api, draftReviewStarted(branch));
        } finally {
            (vscode.window as unknown as {
                showWarningMessage: unknown
            }).showWarningMessage = originalWarning;
            (vscode.window as unknown as {
                showErrorMessage: unknown
            }).showErrorMessage = originalError;
        }

        assert.deepStrictEqual(errors, [], "no puede fallar por deriva");
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "walk");
        assert.strictEqual(state.draft, true);
    });

    it("una fila sin flags conocidos no es startable, y el host no la dispara", async () => {
        // SC-017: borrar el bloque de instrucciones a mano es legal, y entonces
        // los flags no se pueden replicar. El control se sigue dibujando pero
        // apagado (eso lo afirma panelHtml.spec.ts, sobre el HTML); lo que se
        // afirma acá es el otro lado: que `startable` viene en false y que el
        // host tampoco invoca la CLI si le llega el mensaje igual.
        const branch = "us3-unknown-flags";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        const file = makeDraft(branch);
        const stripped = fs
            .readFileSync(file, "utf8")
            .split("\n")
            .reduce<{ out: string[]; skip: boolean }>(
                (acc, line) => {
                    if (line.startsWith("<!-- git-review-range:")) {
                        acc.skip = true;
                        return acc;
                    }
                    if (acc.skip) {
                        if (line.includes("-->")) {
                            acc.skip = false;
                        }
                        return acc;
                    }
                    acc.out.push(line);
                    return acc;
                },
                {out: [], skip: false}
            ).out.join("\n");
        fs.writeFileSync(file, stripped, "utf8");
        assert.ok(!fs.readFileSync(file, "utf8").includes("git-review-range"));

        const api = await getTestApi();
        await api.refresh();
        const model = await api.getPanelModel();
        const row = model.drafts.find((d) => d.branch === branch);
        assert.ok(row, "la fila sigue estando");
        assert.strictEqual(row.startable, false);

        // Y el host tampoco lo dispara si le llega el mensaje igual.
        const before = fs.readFileSync(file, "utf8");
        const errors: string[] = [];
        const originalError = vscode.window.showErrorMessage;
        (vscode.window as unknown as { showErrorMessage: unknown }).showErrorMessage = async (
            message: string
        ) => {
            errors.push(message);
            return undefined;
        };
        try {
            api.sendPanelMessage("startFromDraft", model.drafts.indexOf(row));
            // `settle` y no un sleep suelto: lo que se afirma es que NO pasa
            // nada, y eso no tiene señal que esperar, así que el único margen es
            // el tiempo. El de settle es cuatro veces el que había.
            await settle(api);
        } finally {
            (vscode.window as unknown as {
                showErrorMessage: unknown
            }).showErrorMessage = originalError;
        }
        assert.deepStrictEqual(errors, []);
        assert.strictEqual((await api.refresh()).situation, "no-review");
        // El otro rastro que dejaría un --build disparado con los flags por
        // defecto: sale verde o rojo, pero si sale verde reescribe el borrador
        // canónicamente y le REGENERA el bloque de instrucciones. El archivo
        // intacto es lo que dice que la CLI no llegó a correr sobre él.
        assert.strictEqual(fs.readFileSync(file, "utf8"), before);
        assert.ok(!before.includes("git-review-range"));
    });

    it("Discard pide confirmacion y borra solo esa fila", async () => {
        const one = "us3-discard-one";
        const two = "us3-discard-two";
        createBranchWithChanges(repo, one, {"src/a.ts": "a\n"});
        createBranchWithChanges(repo, two, {"src/b.ts": "b\n"});
        const fileOne = makeDraft(one);
        const fileTwo = makeDraft(two);

        const api = await getTestApi();
        await api.refresh();
        let model = await api.getPanelModel();
        const index = model.drafts.findIndex((d) => d.branch === one);
        assert.ok(index >= 0);

        // Sin confirmar no se borra nada.
        let asked = 0;
        const originalWarning = vscode.window.showWarningMessage;
        (vscode.window as unknown as { showWarningMessage: unknown }).showWarningMessage =
            async (message: string) => {
                asked++;
                assert.ok(message.includes(one), message);
                return undefined;
            };
        try {
            api.sendPanelMessage("discardDraft", index);
            for (let i = 0; i < 60 && asked === 0; i++) {
                await new Promise((resolve) => setTimeout(resolve, 50));
            }
            await new Promise((resolve) => setTimeout(resolve, 300));
        } finally {
            (vscode.window as unknown as {
                showWarningMessage: unknown
            }).showWarningMessage = originalWarning;
        }
        assert.strictEqual(asked, 1, "se pide confirmacion");
        assert.ok(fs.existsSync(fileOne), "sin confirmar no se borra");

        // Confirmando, se borra sólo la fila elegida.
        let confirmed = 0;
        (vscode.window as unknown as { showWarningMessage: unknown }).showWarningMessage =
            async (message: string) => {
                confirmed++;
                // El diálogo nombra el verbo real que se va a correr.
                assert.ok(message.length > 0);
                return "Discard";
            };
        try {
            api.sendPanelMessage("discardDraft", index);
            for (let i = 0; i < 100 && fs.existsSync(fileOne); i++) {
                await new Promise((resolve) => setTimeout(resolve, 50));
            }
            await settle(api);
        } finally {
            (vscode.window as unknown as {
                showWarningMessage: unknown
            }).showWarningMessage = originalWarning;
        }
        assert.strictEqual(confirmed, 1);
        assert.strictEqual(fs.existsSync(fileOne), false, "el borrador elegido se borro");
        assert.strictEqual(fs.existsSync(fileTwo), true, "el de la otra fila sigue");

        model = await api.getPanelModel();
        assert.deepStrictEqual(
            model.drafts.map((d) => d.branch),
            [two]
        );
    });
    /**
     * El circuito con el agente: el panel queda a la vista mientras algo que no
     * es la extension llena el archivo. Escribir en el gitdir no mueve HEAD, no
     * toca el indice y no escribe config, asi que ninguna de las dos senales de
     * refresco de siempre lo ve -- si el progreso se mueve solo, es el watcher
     * de borradores. Ningun `api.refresh()` en el medio, a proposito.
     */
    async function waitForModel(
        api: Awaited<ReturnType<typeof getTestApi>>,
        done: (model: Awaited<ReturnType<typeof api.getPanelModel>>) => boolean,
        label: string
    ): Promise<Awaited<ReturnType<typeof api.getPanelModel>>> {
        let model = await api.getPanelModel();
        for (let i = 0; i < 200 && !done(model); i++) {
            await new Promise((resolve) => setTimeout(resolve, 50));
            model = await api.getPanelModel();
        }
        assert.ok(done(model), label + ": " + JSON.stringify(model.drafts));
        return model;
    }

    it("el progreso se mueve solo cuando el borrador se llena desde afuera", async () => {
        const branch = "us3-watch-fill";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n", "src/b.ts": "b\n"});
        const file = makeDraft(branch);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");
        const before = await api.getPanelModel();
        assert.strictEqual(
            before.drafts.find((d) => d.branch === branch)?.annotated,
            0,
            "el esqueleto arranca sin anotar"
        );

        // Lo que hace el agente: escribe el archivo, y nada mas.
        fillDraft(file, "## 1. src/a.ts\nel why de a\n\n## 2. src/b.ts\n");

        const model = await waitForModel(
            api,
            (m) => m.drafts.find((d) => d.branch === branch)?.annotated === 1,
            "el panel no volvio a contar el borrador sin que nadie refrescara"
        );
        // Recontado de verdad sobre el archivo nuevo: una anotada de dos.
        const row = model.drafts.find((d) => d.branch === branch);
        assert.strictEqual(row?.annotated, 1);
        assert.strictEqual(row?.total, 2);
    });
});
