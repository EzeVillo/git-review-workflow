import * as assert from "node:assert";
import {parseListPorcelain, parsePorcelain, sourceOf} from "../../src/cli/porcelain";
import {PathRef} from "../../src/cli/unquote";

describe("parsePorcelain", () => {
    it("parsea state en modo whole (6 campos)", () => {
        const out = "state\treview/feat-x\torigin/feat-x\tabc123\twhole\tnone\n";
        const result = parsePorcelain(out);
        assert.strictEqual(result.state.mode, "whole");
        assert.strictEqual(result.state.walkthrough, "none");
        assert.strictEqual(result.state.position, undefined);
        assert.strictEqual(result.state.essential, undefined);
        assert.deepStrictEqual(result.entries, []);
    });

    it("parsea state en modo step (10 campos), current como string", () => {
        const out = "state\treview/feat-x\torigin/feat-x\tabc123\tstep\tnone\t2\t9\t9\t9fe1c0d\n";
        const result = parsePorcelain(out);
        assert.strictEqual(result.state.mode, "step");
        assert.strictEqual(result.state.position, 2);
        assert.strictEqual(result.state.total, 9);
        assert.strictEqual(result.state.recorded, 9);
        assert.strictEqual(result.state.current, "9fe1c0d");
        assert.strictEqual(result.state.essential, undefined);
    });

    it("parsea state en modo walk (11 campos), current como PathRef", () => {
        const out = "state\treview/feat-x\torigin/feat-x\tabc123\twalk\tapplied\t3\t7\t7\tsrc/core.ts\t1\n";
        const result = parsePorcelain(out);
        assert.strictEqual(result.state.mode, "walk");
        assert.strictEqual(result.state.essential, true);
        const current = result.state.current as PathRef;
        assert.strictEqual(current.raw, "src/core.ts");
        assert.strictEqual(current.display, "src/core.ts");
    });

    it("entry en modo walk trae essential y annotated, no banked", () => {
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\twalk\tapplied\t1\t3\t3\tsrc/a.ts\t0",
            "entry\t1\tsrc/a.ts\t0\t1",
            "entry\t2\tsrc/b.ts\t1\t1",
            "entry\t3\tsrc/c.ts\t0\t0",
        ].join("\n");
        const result = parsePorcelain(out);
        assert.strictEqual(result.entries.length, 3);
        assert.strictEqual(result.entries[0].essential, false);
        assert.strictEqual(result.entries[0].annotated, true);
        assert.strictEqual(result.entries[0].banked, undefined);
        assert.strictEqual(result.entries[1].essential, true);
        assert.strictEqual(result.entries[1].annotated, true);
        // Un archivo que la review cubre pero el walkthrough no anota: al final
        // del orden de lectura, con annotated en false.
        assert.strictEqual(result.entries[2].essential, false);
        assert.strictEqual(result.entries[2].annotated, false);
    });

    it("entry en modo step trae banked, no essential", () => {
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\tstep\tnone\t1\t2\t2\t1111111",
            "entry\t1\t1111111\t1",
            "entry\t2\t2222222\t0",
        ].join("\n");
        const result = parsePorcelain(out);
        assert.strictEqual(result.entries[0].banked, true);
        assert.strictEqual(result.entries[0].essential, undefined);
        assert.strictEqual(result.entries[1].banked, false);
    });

    it("entry en modo whole trae sólo posición y path, id como PathRef", () => {
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\twhole\tnone",
            "entry\t1\ta.txt",
            "entry\t2\tsrc/b.txt",
        ].join("\n");
        const result = parsePorcelain(out);
        assert.strictEqual(result.entries.length, 2);
        assert.strictEqual(result.entries[0].position, 1);
        // El id de whole es un path, igual que en walk: mismo tratamiento que
        // permite abrirlo (research.md Decisión 4), no un string suelto como en
        // step.
        const id0 = result.entries[0].id as PathRef;
        assert.strictEqual(id0.display, "a.txt");
        assert.strictEqual(id0.raw, "a.txt");
        assert.strictEqual(result.entries[0].essential, undefined);
        assert.strictEqual(result.entries[0].annotated, undefined);
        assert.strictEqual(result.entries[0].banked, undefined);
        const id1 = result.entries[1].id as PathRef;
        assert.strictEqual(id1.display, "src/b.txt");
    });

    it("ignora etiquetas desconocidas", () => {
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\twhole\tnone",
            "future-tag\tsome\tfields",
        ].join("\n");
        const result = parsePorcelain(out);
        assert.strictEqual(result.state.mode, "whole");
        assert.deepStrictEqual(result.entries, []);
    });

    it("ignora campos extra al final de un registro conocido", () => {
        const out = "state\treview/feat-x\torigin/feat-x\tabc123\twhole\tnone\textra1\textra2\n";
        const result = parsePorcelain(out);
        assert.strictEqual(result.state.branch, "review/feat-x");
        assert.strictEqual(result.state.mode, "whole");
    });

    it("un registro uncovered sobrante se ignora como etiqueta desconocida", () => {
        // El tipo de registro ya no existe en el contrato (los archivos sin
        // anotar son entradas, con annotated=0), pero una salida vieja o de un
        // fork que todavía lo emita no debe romper el parseo del resto.
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\twalk\tapplied\t1\t1\t1\tsrc/a.ts\t0",
            "entry\t1\tsrc/a.ts\t0\t1",
            'uncovered\t"caf\\303\\251.ts"',
        ].join("\n");
        const result = parsePorcelain(out);
        assert.strictEqual(result.entries.length, 1);
        assert.strictEqual((result as unknown as {uncovered?: unknown}).uncovered, undefined);
    });

    it("lanza si no hay registro state", () => {
        assert.throws(() => parsePorcelain(""));
    });

    it("subject y author se pueblan por position en modo step", () => {
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\tstep\tnone\t1\t2\t2\t1111111",
            "entry\t1\t1111111\t0",
            "entry\t2\t2222222\t0",
            "subject\t1\tfeat: exponer el asunto",
            "subject\t2\ttest: cubrir los bytes hostiles",
            "author\t1\tEze Villo <eze@example.com>",
            "author\t2\tAna <ana@example.com>",
            "",
        ].join("\n");
        const result = parsePorcelain(out);
        assert.strictEqual(result.subjects?.get(1), "feat: exponer el asunto");
        assert.strictEqual(result.subjects?.get(2), "test: cubrir los bytes hostiles");
        assert.strictEqual(result.authors?.get(1), "Eze Villo <eze@example.com>");
        assert.strictEqual(result.authors?.get(2), "Ana <ana@example.com>");
        // Los registros nuevos no tocan la forma de entry, que otros tests afirman.
        assert.strictEqual(result.entries.length, 2);
        assert.strictEqual(result.entries[0].banked, false);
    });

    it("sin lineas subject/author los mapas quedan ausentes, no vacios (CLI vieja)", () => {
        // La distincion de FR-004: un mapa vacio diria "esta review no tiene
        // asuntos"; la ausencia dice "esta CLI no los reporta", que es lo que
        // hace que el panel degrade al de siempre en vez de mostrar huecos.
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\tstep\tnone\t1\t1\t1\t1111111",
            "entry\t1\t1111111\t0",
            "",
        ].join("\n");
        const result = parsePorcelain(out);
        assert.strictEqual(result.subjects, undefined);
        assert.strictEqual(result.authors, undefined);
    });

    it("un asunto vacio es cadena vacia, no ausencia", () => {
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\tstep\tnone\t1\t1\t1\t1111111",
            "entry\t1\t1111111\t0",
            "subject\t1\t",
            "",
        ].join("\n");
        const result = parsePorcelain(out);
        assert.strictEqual(result.subjects?.has(1), true);
        assert.strictEqual(result.subjects?.get(1), "");
    });

    it("un tab dentro del asunto no lo corta ni desplaza el registro siguiente", () => {
        // El modo de falla que `restAfterTab` existe para evitar: con split("\t")
        // el asunto seria "con" y el resto se perderia, en silencio.
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\tstep\tnone\t1\t2\t2\t1111111",
            "subject\t1\tcon\ttab\ty otro\ttab",
            "subject\t2\tel siguiente sigue entero",
            "author\t1\tno\tmbre <t@example.com>",
            "",
        ].join("\n");
        const result = parsePorcelain(out);
        assert.strictEqual(result.subjects?.get(1), "con\ttab\ty otro\ttab");
        assert.strictEqual(result.subjects?.get(2), "el siguiente sigue entero");
        assert.strictEqual(result.authors?.get(1), "no\tmbre <t@example.com>");
    });

    it("base se puebla en modo whole", () => {
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\twhole\tnone",
            "base\tmain",
            "",
        ].join("\n");
        assert.strictEqual(parsePorcelain(out).base, "main");
    });

    it("sin linea base el campo queda ausente", () => {
        // Los dos motivos posibles —CLI vieja, o review sin base registrada— son
        // indistinguibles acá, y esta bien: el contrato nunca emite `base` vacio,
        // asi que "ausente" siempre significa "no hay nada que mostrar".
        const out = "state\treview/feat-x\torigin/feat-x\tabc123\twhole\tnone\n";
        assert.strictEqual(parsePorcelain(out).base, undefined);
    });

    it("una base con un tab adentro se lee entera", () => {
        // El nombre de una rama no puede llevar un tab, pero el registro se lee
        // con la misma regla que los otros dos textos libres, y eso se prueba.
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\twhole\tnone",
            "base\tcon\ttab",
            "",
        ].join("\n");
        assert.strictEqual(parsePorcelain(out).base, "con\ttab");
    });

    it("un registro subject sin position ni texto se descarta entero", () => {
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\tstep\tnone\t1\t1\t1\t1111111",
            "subject",
            "subject\t1",
            "",
        ].join("\n");
        const result = parsePorcelain(out);
        // Ninguno de los dos llega a tener los dos tabs que el registro exige:
        // no se les inventa posicion ni texto, y el mapa ni siquiera se crea.
        assert.strictEqual(result.subjects, undefined);
    });
});

describe("parseListPorcelain", () => {
    it("parsea una activa en walk con posicion y total", () => {
        const out = "branch\treview/feat-x\t0\t1\t0\twalk\t3\t9\n";
        const branches = parseListPorcelain(out);
        assert.strictEqual(branches.length, 1);
        assert.deepStrictEqual(branches[0], {
            name: "review/feat-x",
            saved: false,
            current: true,
            orphan: false,
            mode: "walk",
            position: 3,
            total: 9,
        });
    });

    it("una guardada en step lleva saved y su posicion registrada", () => {
        const out = "branch\treview-saved/fix/quoting\t1\t0\t0\tstep\t2\t4\n";
        const branches = parseListPorcelain(out);
        assert.strictEqual(branches[0].saved, true);
        assert.strictEqual(branches[0].current, false);
        assert.strictEqual(branches[0].mode, "step");
        assert.strictEqual(branches[0].position, 2);
        assert.strictEqual(branches[0].total, 4);
    });

    it("whole no trae cursor: position y total quedan ausentes", () => {
        const out = "branch\treview/feat-x\t0\t0\t0\twhole\n";
        const branches = parseListPorcelain(out);
        assert.strictEqual(branches[0].mode, "whole");
        assert.strictEqual(branches[0].position, undefined);
        assert.strictEqual(branches[0].total, undefined);
    });

    it("una huerfana no trae mode ni cursor", () => {
        const out = "branch\treview/orphan\t0\t0\t1\n";
        const branches = parseListPorcelain(out);
        assert.strictEqual(branches[0].orphan, true);
        assert.strictEqual(branches[0].mode, undefined);
        assert.strictEqual(branches[0].position, undefined);
        assert.strictEqual(branches[0].total, undefined);
    });

    it("con un solo campo del par, ninguno de los dos se inventa", () => {
        // El contrato los emite de a pares; media salida es salida que no
        // entendemos, y un 0 seria un cursor inventado.
        const out = "branch\treview/feat-x\t0\t0\t0\tstep\t2\n";
        const branches = parseListPorcelain(out);
        assert.strictEqual(branches[0].mode, "step");
        assert.strictEqual(branches[0].position, undefined);
        assert.strictEqual(branches[0].total, undefined);
    });

    it("conserva el orden de la CLI: activas primero, guardadas despues", () => {
        const out = [
            "branch\treview/a\t0\t0\t0\twhole",
            "branch\treview/b\t0\t0\t0\twhole",
            "branch\treview-saved/c\t1\t0\t0\twhole",
            "",
        ].join("\n");
        assert.deepStrictEqual(
            parseListPorcelain(out).map((b) => b.name),
            ["review/a", "review/b", "review-saved/c"]
        );
    });

    it("un inventario vacio es una lista vacia, no un error", () => {
        assert.deepStrictEqual(parseListPorcelain(""), []);
        assert.deepStrictEqual(parseListPorcelain("\n"), []);
    });

    it("ignora etiquetas desconocidas y campos extra al final", () => {
        const out = [
            "future\tlo que sea\t1\t2",
            "branch\treview/feat-x\t0\t0\t0\twalk\t1\t2\textra",
            "",
        ].join("\n");
        const branches = parseListPorcelain(out);
        assert.strictEqual(branches.length, 1);
        assert.strictEqual(branches[0].name, "review/feat-x");
        assert.strictEqual(branches[0].total, 2);
    });
});

describe("sourceOf", () => {
    it("saca el prefijo review/", () => {
        assert.strictEqual(
            sourceOf({name: "review/feature/checkout", saved: false, current: false, orphan: false}),
            "feature/checkout"
        );
    });

    it("saca el prefijo review-saved/ y no confunde el review/ que contiene", () => {
        assert.strictEqual(
            sourceOf({name: "review-saved/feature/checkout", saved: true, current: false, orphan: false}),
            "feature/checkout"
        );
    });

    it("un nombre sin prefijo conocido vuelve tal cual", () => {
        assert.strictEqual(
            sourceOf({name: "main", saved: false, current: false, orphan: false}),
            "main"
        );
    });
});
