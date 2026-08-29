import * as assert from "node:assert";
import {parseConfigPorcelain} from "../../src/cli/configPorcelain";
import {parsePorcelain} from "../../src/cli/porcelain";
import {
    draftArgs,
    draftConfigArgs,
    forgetDraftArgs,
    intentToArgs,
} from "../../src/review/reviewIntent";
import {draftAgentPrompt} from "../../src/review/userCopy";
// `import type`: `review/state.ts` importa `vscode`, que no existe fuera del
// host — el tipo se borra en compilación y el módulo no llega a cargarse.
import type {ReviewState} from "../../src/review/state";
import {buildPanelModel, draftAt} from "../../src/views/panelModel";

const DRAFT_LINE =
    "draft\tfeature/checkout\t/repo/.git/review-walkthrough/feature/checkout.md\t3\t9\tlocal\tdelta\tfresh";

/** El mismo borrador con su review ya cerrada: el octavo campo es lo unico que cambia. */
const SPENT_DRAFT_LINE =
    "draft\tfeature/checkout\t/repo/.git/review-walkthrough/feature/checkout.md\t9\t9\tlocal\tdelta\treviewed";

describe("parseConfigPorcelain — registros draft", () => {
    it("parsea los ocho campos del registro", () => {
        const result = parseConfigPorcelain(["config\tremote\torigin", DRAFT_LINE, ""].join("\n"));
        assert.deepStrictEqual(result.drafts, [
            {
                src: "feature/checkout",
                path: "/repo/.git/review-walkthrough/feature/checkout.md",
                annotated: 3,
                total: 9,
                source: "local",
                range: "delta",
                state: "fresh",
            },
        ]);
    });

    it("lee reviewed del octavo campo", () => {
        const result = parseConfigPorcelain([SPENT_DRAFT_LINE, ""].join("\n"));
        assert.strictEqual(result.drafts[0]?.state, "reviewed");
    });

    it("un registro de siete campos, de una CLI anterior, es fresh", () => {
        // Degrada al comportamiento de antes: la fila sigue arriba con sus
        // cuatro controles. Esconderla por un dato que nadie dio seria peor.
        const old = DRAFT_LINE.slice(0, DRAFT_LINE.lastIndexOf("\t"));
        const result = parseConfigPorcelain([old, ""].join("\n"));
        assert.strictEqual(result.drafts[0]?.state, "fresh");
    });

    it("un octavo campo desconocido tambien es fresh", () => {
        const weird = DRAFT_LINE.slice(0, DRAFT_LINE.lastIndexOf("\t")) + "\tsomething-new";
        const result = parseConfigPorcelain([weird, ""].join("\n"));
        assert.strictEqual(result.drafts[0]?.state, "fresh");
    });

    it("sin registros draft el array esta vacio, nunca ausente", () => {
        const result = parseConfigPorcelain("config\tremote\torigin\n");
        assert.deepStrictEqual(result.drafts, []);
    });

    it("varios registros conservan el orden de la CLI", () => {
        const result = parseConfigPorcelain(
            [
                "draft\tfeature/telemetry\t/repo/.git/review-walkthrough/feature/telemetry.md\t0\t5\tremote\tfull",
                DRAFT_LINE,
                "",
            ].join("\n")
        );
        assert.deepStrictEqual(
            result.drafts.map((d) => d.src),
            ["feature/telemetry", "feature/checkout"]
        );
    });

    it("un source o range que no reconoce se lee como unknown", () => {
        // Es lo que la CLI emite cuando el bloque de instrucciones se borro a
        // mano, y tambien lo unico honesto para un valor que agregue una CLI
        // mas nueva: en los dos casos este cliente no puede replicar los flags.
        const result = parseConfigPorcelain(
            "draft\tfeature/x\t/repo/.git/review-walkthrough/feature/x.md\t0\t2\tunknown\tunknown\n"
        );
        assert.strictEqual(result.drafts[0].source, "unknown");
        assert.strictEqual(result.drafts[0].range, "unknown");
    });

    it("un registro malformado se ignora entero", () => {
        // Media fila de progreso seria peor que ninguna: un total que no es un
        // entero no se puede dibujar como "3/N" sin inventar el N.
        const result = parseConfigPorcelain(
            [
                "draft\tfeature/x\t/repo/.git/review-walkthrough/feature/x.md\tmany\t2\tremote\tfull",
                "draft\t\t/repo/.git/review-walkthrough/feature/y.md\t0\t2\tremote\tfull",
                "draft\tfeature/z",
                DRAFT_LINE,
                "",
            ].join("\n")
        );
        assert.deepStrictEqual(
            result.drafts.map((d) => d.src),
            ["feature/checkout"]
        );
    });

    it("un progreso que no es un entero no negativo invalida el registro", () => {
        // La regla tiene que ser la misma en los tres clientes: la CLI cuenta
        // con awk y emite siempre digitos, asi que un signo o un espacio es un
        // registro que este cliente no entendio. Aceptarlo en uno y no en otro
        // hace que la misma linea dibuje fila en dos paneles y en el tercero no.
        for (const bad of ["-3", "+3", " 3", "3 ", "3.0", "", "0x2"]) {
            const line = `draft\tfeature/x\t/repo/.git/review-walkthrough/feature/x.md\t${bad}\t9\tremote\tfull`;
            assert.deepStrictEqual(
                parseConfigPorcelain(`${line}\n`).drafts,
                [],
                `annotated=${JSON.stringify(bad)}`
            );
            const other = `draft\tfeature/x\t/repo/.git/review-walkthrough/feature/x.md\t0\t${bad}\tremote\tfull`;
            assert.deepStrictEqual(
                parseConfigPorcelain(`${other}\n`).drafts,
                [],
                `total=${JSON.stringify(bad)}`
            );
        }
    });
});

describe("parsePorcelain — el campo de ruta del registro draft", () => {
    const STATE = "state\treview/feature/x\tfeature/x\tabc1234\twalk\tapplied\t1\t2\t2\ta.txt\t0";

    it("la ruta llega aparte, sin tocar el booleano de presencia", () => {
        const parsed = parsePorcelain(
            [STATE, "draft\t/repo/.git/review-walkthrough/feature/x.md", ""].join("\n")
        );
        assert.strictEqual(parsed.draft, true);
        assert.strictEqual(parsed.draftPath, "/repo/.git/review-walkthrough/feature/x.md");
    });

    it("un registro sin campo sigue marcando el borrador", () => {
        // Una CLI anterior a 012 emite el registro pelado, y eso no puede
        // apagar la marca: la presencia es la presencia.
        const parsed = parsePorcelain([STATE, "draft", ""].join("\n"));
        assert.strictEqual(parsed.draft, true);
        assert.strictEqual(parsed.draftPath, undefined);
    });

    it("sin registro draft no hay ni marca ni ruta", () => {
        const parsed = parsePorcelain([STATE, ""].join("\n"));
        assert.strictEqual(parsed.draft, undefined);
        assert.strictEqual(parsed.draftPath, undefined);
    });
});

describe("PanelModel.drafts", () => {
    function stateWith(situation: ReviewState["situation"], stdout: string): ReviewState {
        const parsed = parseConfigPorcelain(stdout);
        return {
            situation,
            entries: [],
            files: [],
            branches: [],
            config: parsed.config,
            drafts: parsed.drafts,
        };
    }

    it("se puebla solo en no-review", () => {
        const stdout = ["config\tremote\torigin", DRAFT_LINE, ""].join("\n");
        const shown = buildPanelModel(stateWith("no-review", stdout), {busy: false});
        assert.strictEqual(shown.drafts.length, 1);
        assert.deepStrictEqual(shown.drafts[0], {
            branch: "feature/checkout",
            path: "/repo/.git/review-walkthrough/feature/checkout.md",
            annotated: 3,
            total: 9,
            startable: true,
            spent: false,
        });

        // Una review en curso es siempre lo mas importante que el panel tiene
        // para decir; el borrador de otra rama no le compite el cuerpo.
        for (const situation of ["finish-pending", "error", "out-of-range"] as const) {
            const other = buildPanelModel(stateWith(situation, stdout), {busy: false});
            assert.deepStrictEqual(other.drafts, [], situation);
        }
    });

    it("spent sigue al estado que reporta la CLI, y no se deriva del progreso", () => {
        // Un borrador completo (9/9) sin review cerrada NO esta gastado, y uno
        // que la CLI marca reviewed lo esta pase lo que pase con el par.
        const filled = DRAFT_LINE.replace("\t3\t9\t", "\t9\t9\t");
        const a = buildPanelModel(stateWith("no-review", filled + "\n"), {busy: false});
        assert.strictEqual(a.drafts[0].spent, false);

        const b = buildPanelModel(stateWith("no-review", SPENT_DRAFT_LINE + "\n"), {busy: false});
        assert.strictEqual(b.drafts[0].spent, true);
    });

    it("una fila con flags desconocidos no es startable", () => {
        const stdout = "draft\tfeature/x\t/repo/.git/review-walkthrough/feature/x.md\t0\t2\tunknown\tunknown\n";
        const model = buildPanelModel(stateWith("no-review", stdout), {busy: false});
        assert.strictEqual(model.drafts[0].startable, false);
    });

    it("el progreso llega contado, nunca derivado", () => {
        const stdout = "draft\tfeature/x\t/repo/.git/review-walkthrough/feature/x.md\t0\t0\tremote\tfull\n";
        const model = buildPanelModel(stateWith("no-review", stdout), {busy: false});
        // Un borrador de cero bytes: la CLI lo reporta igual, porque hay que
        // poder abrirlo y descartarlo.
        assert.strictEqual(model.drafts[0].annotated, 0);
        assert.strictEqual(model.drafts[0].total, 0);
    });

    it("draftAt valida el indice que llega del webview", () => {
        const drafts = parseConfigPorcelain([DRAFT_LINE, ""].join("\n")).drafts;
        assert.strictEqual(draftAt(drafts, 0)?.src, "feature/checkout");
        assert.strictEqual(draftAt(drafts, 1), undefined);
        assert.strictEqual(draftAt(drafts, -1), undefined);
        assert.strictEqual(draftAt(drafts, 0.5), undefined);
        assert.strictEqual(draftAt(drafts, "0"), undefined);
        assert.strictEqual(draftAt(drafts, undefined), undefined);
    });
});

describe("argv de los controles del bloque de borradores", () => {
    it("los tres pasos de Validate and start llevan los MISMOS flags", () => {
        // Salen de los campos source/range del registro, no de los defaults.
        // Con los defaults, un borrador hecho con --delta o --local cubre otro
        // conjunto de paths y --build muere por deriva, siempre.
        assert.deepStrictEqual(
            draftArgs("feature/checkout", "local", "delta", true),
            ["draft", "--build", "--local", "--delta", "--", "feature/checkout"]
        );
        assert.deepStrictEqual(
            draftConfigArgs("feature/checkout", "local", "delta"),
            ["--porcelain", "--local", "--delta", "--", "feature/checkout"]
        );
        assert.deepStrictEqual(
            intentToArgs(
                {branch: "feature/checkout", layout: "walk", range: "delta", source: "local"},
                "feature/checkout"
            ),
            ["--delta", "--local", "--", "feature/checkout"]
        );
    });

    it("offline y full salen igual en los tres", () => {
        assert.deepStrictEqual(
            draftArgs("feature/x", "offline", "full", true),
            ["draft", "--build", "--offline", "--", "feature/x"]
        );
        assert.deepStrictEqual(
            draftConfigArgs("feature/x", "offline", "full"),
            ["--porcelain", "--offline", "--", "feature/x"]
        );
    });

    it("remote y full no agregan ningun flag", () => {
        assert.deepStrictEqual(
            draftArgs("feature/x", "remote", "full", true),
            ["draft", "--build", "--", "feature/x"]
        );
        assert.deepStrictEqual(
            draftConfigArgs("feature/x", "remote", "full"),
            ["--porcelain", "--", "feature/x"]
        );
    });

    it("los controles de la fila nunca llevan --force, --from ni --stdout", () => {
        // Validate and start valida y arranca sobre lo que hay escrito. Tirarlo
        // es otra decision, y se pide en otro lado (el picker del asistente).
        const args = draftArgs("feature/x", "remote", "full", true).join(" ");
        assert.ok(!args.includes("--force"), args);
        assert.ok(!args.includes("--from"), args);
        assert.ok(!args.includes("--stdout"), args);
    });

    it("--force solo cuando el revisor eligio empezar de cero", () => {
        // Update no lleva flag: el verbo reconcilia por defecto desde que dejo
        // de negarse sobre un archivo existente.
        assert.deepStrictEqual(
            draftArgs("feature/x", "remote", "full", false, false),
            ["draft", "--porcelain", "--", "feature/x"]
        );
        assert.deepStrictEqual(
            draftArgs("feature/x", "local", "delta", false, true),
            ["draft", "--porcelain", "--force", "--local", "--delta", "--", "feature/x"]
        );
    });

    // El paso que escribe el esqueleto pide el registro `merged`; el que valida
    // e instala no, porque no lo emite -- su resultado es el badge de la fila.
    it("--porcelain va en el paso que escribe y no en --build", () => {
        assert.ok(draftArgs("feature/x", "remote", "full", false).includes("--porcelain"));
        assert.ok(!draftArgs("feature/x", "remote", "full", true).includes("--porcelain"));
    });

    it("Discard nombra una sola rama y nunca --all ni --saved", () => {
        assert.deepStrictEqual(forgetDraftArgs("feature/checkout"), [
            "--draft",
            "--",
            "feature/checkout",
        ]);
        const args = forgetDraftArgs("feature/x").join(" ");
        assert.ok(!args.includes("--all"), args);
        assert.ok(!args.includes("--saved"), args);
    });

    it("un nombre de rama que empieza con - va detras de --", () => {
        assert.deepStrictEqual(forgetDraftArgs("-weird")[1], "--");
        assert.deepStrictEqual(draftArgs("-weird", "remote", "full", true).slice(-2), [
            "--",
            "-weird",
        ]);
    });
});

describe("draftAgentPrompt", () => {
    it("es el texto canonico, byte por byte, con la ruta de esa fila", () => {
        assert.strictEqual(
            draftAgentPrompt("/repo/.git/review-walkthrough/feature/checkout.md"),
            "Fill in the reading order at /repo/.git/review-walkthrough/feature/checkout.md." +
            " The instructions are inside the file, in the comment at the top." +
            " Do not change the file list or the numbering rules."
        );
    });

    it("no nombra ningun modelo, servicio ni asistente", () => {
        const text = draftAgentPrompt("/x.md").toLowerCase();
        for (const word of ["copilot", "openai", "claude", "chatgpt", "http"]) {
            assert.ok(!text.includes(word), word);
        }
    });
});
