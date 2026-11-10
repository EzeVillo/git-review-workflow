import * as assert from "node:assert";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {runInNewContext} from "node:vm";
import * as ts from "typescript";
import {RefreshGate} from "../../src/review/refreshGate";

// Execute the actual host pipeline with a scripted process boundary and the
// EventEmitter surface it uses. No IDE or process timing is needed to prove
// that the review is published while comments are still unanswered.
function pipeline(invoke: (verb: string) => Promise<object>) {
    const exported: any = {};
    const events: any[] = [];
    const source = readFileSync(resolve("src/review/state.ts"), "utf8");
    runInNewContext(ts.transpileModule(source, {compilerOptions: {module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022}}).outputText, {
        exports: exported, setTimeout,
        require: (name: string) => name === "vscode" ? {EventEmitter: class {
            event = () => undefined;
            fire(state: object) { events.push(state); }
            dispose() {}
        }} : name === "../cli/invoke" ? {invokeGitReview: invoke} : require(resolve("src/review", name)),
    });
    return {manager: new exported.ReviewStateManager(() => ({cwd: "/repo"})), events};
}

describe("Continue primary state", () => {
    const guard = "b".repeat(40);
    const wire = `continue-state\t1\nstate\treview/feature\tfeature\tdeadbeef\twhole\tnone\ncapability\tsave-state\nguard\t${guard}\ncontinue-state\tcomplete\n`;
    it("publishes Continue without another primary query", async () => {
        const calls: string[] = [];
        const {manager} = pipeline(async verb => { calls.push(verb); return {stdout:"",stderr:"",exitCode:0}; });
        await manager.refreshPrimary(wire);
        assert.deepStrictEqual(calls,["comments"]);
        assert.strictEqual(manager.state.guard,guard);
        assert.strictEqual(manager.state.saveState,true);
        assert.strictEqual(manager.state.situation,"review");
    });
    it("keeps the inventory token from a normal or fallback read", async () => {
        const calls: string[] = [];
        const {manager} = pipeline(async verb => {
            calls.push(verb);
            if (verb === "status") return {stdout:"",stderr:"",exitCode:2};
            if (verb === "list") return {stdout:`capability\tcontinue-state\ncontinue-guard\t${guard}\nbranch\treview-saved/feature\t1\t0\t0\twhole\n`,stderr:"",exitCode:0};
            return {stdout:"",stderr:"",exitCode:0};
        });
        await manager.refreshPrimary(wire.replace("continue-state\tcomplete\n",""));
        assert.deepStrictEqual(calls,["--version","status","list","config","comments"]);
        assert.strictEqual(manager.state.continueGuard,guard);
    });
});

describe("incremental review refresh", () => {
    const reply = (guard = "a".repeat(40), position = 1) =>
        `state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t${position}\t2\t2\ta.txt\t0\n` +
        "entry\t1\ta.txt\t0\t1\nentry\t2\tb.txt\t0\t1\ncapability\tnavigation-state\n" +
        `guard\t${guard}\nnavigation\tmoved\n`;

    it("reuses only the complete comments report for the current workspace read", async () => {
        const calls: string[] = [];
        let identity = "fresh";
        let commentsExit = 0;
        const {manager} = pipeline(async verb => {
            calls.push(verb);
            return {exitCode: verb === "comments" ? commentsExit : 0, stderr: "", stdout:
                verb === "--version" ? "999.0.0\n" : verb === "status" ? reply() :
                    `comments-guard\tcomment-guard\ncomments-identity\t${identity}\tContext\ncomments-capability\tadd\tlocal\n`};
        });
        const current = await manager.refresh();
        calls.length = 0;
        assert.strictEqual(manager.commentsForComposer("/repo"), current.comments);
        assert.strictEqual(manager.commentsForComposer("/other"), undefined);
        manager.invalidatePendingReads();
        assert.strictEqual(manager.commentsForComposer("/repo"), undefined);
        assert.deepStrictEqual(calls, []);
        identity = "ambiguous";
        await manager.refresh();
        assert.strictEqual(manager.commentsForComposer("/repo"), undefined);
        identity = "resolved";
        commentsExit = 1;
        await manager.refresh();
        assert.strictEqual(manager.commentsForComposer("/repo"), undefined);
    });

    it("the mutation's actual primary read consumes earlier watcher requests before querying the CLI", async () => {
        const gate = new RefreshGate();
        const calls: string[] = [];
        const {manager} = pipeline(async verb => { calls.push(verb); return {stdout:"",stderr:"",exitCode:0}; });
        manager.onPrimaryReadStarting = () => gate.primaryStarting();
        gate.mutationChanged(true);
        gate.request();
        await manager.refreshPrimary(reply());
        gate.mutationChanged(false);
        assert.strictEqual(gate.tryStart(),false);
        assert.deepStrictEqual(calls,["comments"]);
        assert.strictEqual(manager.state.state.position,1);
    });

    it("uses a navigation reply without a version or status read and releases before comments", async () => {
        let release!: (value: object) => void;
        const deferred = new Promise<object>(resolve => { release = resolve; });
        const calls: string[] = [];
        const {manager, events} = pipeline(async verb => { calls.push(verb); return deferred; });
        try {
            const primary = await manager.refreshPrimary(reply()+"why\tpresent\t1\nwhy-line\t1\tfrom this snapshot\n");
            assert.deepStrictEqual(calls, ["comments"]);
            assert.strictEqual(primary.state.position, 1);
            assert.strictEqual(primary.navigationState, true);
            assert.strictEqual(primary.inlineWhy,"from this snapshot\n");
            assert.strictEqual(primary.comments.loading, true);
            assert.strictEqual(events.length, 1);
        } finally { release({exitCode: 0, stderr: "", stdout: ""}); }
        for (let i = 0; i < 10 && events.length < 2; i++) await Promise.resolve();
        assert.ok(!manager.state.comments.loading);
    });

    it("discards an earlier comments response after a newer navigation", async () => {
        let release!: (value: object) => void;
        const deferred = new Promise<object>(resolve => { release = resolve; });
        const {manager, events} = pipeline(async () => deferred);
        await manager.refreshPrimary(reply());
        const current = await manager.refreshPrimary(reply("b".repeat(40), 2));
        release({exitCode: 0, stderr: "", stdout: ""});
        for (let i = 0; i < 10 && events.length < 3; i++) await Promise.resolve();
        assert.strictEqual(manager.state.state.position, 2);
        assert.strictEqual(manager.state.guard, "b".repeat(40));
        assert.strictEqual(manager.state.readId, current.readId);
        assert.strictEqual(events.length, 3);
    });

    it("falls back to a primary read for malformed or absent navigation replies", async () => {
        const calls: string[] = [];
        const {manager} = pipeline(async verb => {
            calls.push(verb);
            return {exitCode: 0, stderr: "", stdout: verb === "--version" ? "999.0.0\n" : verb === "status" ? reply() : ""};
        });
        const state = await manager.refreshPrimary(reply().replace("navigation\tmoved", "navigation\tunknown"));
        assert.deepStrictEqual(calls, ["--version", "status", "comments"]);
        assert.strictEqual(state.state.position, 1);
    });

    it("an old version failure cannot overwrite an accepted navigation reply", async () => {
        let release!: (value: object) => void;
        const version = new Promise<object>(resolve => { release = resolve; });
        const {manager} = pipeline(async verb => verb === "--version" ? version : {exitCode: 0, stderr: "", stdout: ""});
        const older = manager.refresh();
        await manager.refreshPrimary(reply("b".repeat(40), 2));
        release({exitCode: 1, errorCode: "ENOENT", stderr: "git-review: command not found", stdout: ""});
        await older;
        assert.strictEqual(manager.state.situation, "review");
        assert.strictEqual(manager.state.guard, "b".repeat(40));
        assert.strictEqual(manager.state.state.position, 2);
    });

    it("a watcher waits for the mutation's primary publication before starting another read", async () => {
        let release!: (value: object) => void;
        let started!: () => void;
        const status = new Promise<object>(resolve => { release = resolve; });
        const entered = new Promise<void>(resolve => { started = resolve; });
        let statusCalls = 0;
        const {manager, events} = pipeline(async verb => {
            if (verb === "status" && ++statusCalls === 1) { started(); return status; }
            return {exitCode: 0, stderr: "", stdout: verb === "--version" ? "999.0.0\n" : verb === "status" ? reply("b".repeat(40), 2) : ""};
        });
        await manager.refreshPrimary(reply());
        const mutation = manager.refreshPrimary();
        await entered;
        const watcher = manager.refresh();
        try {
            for (let i = 0; i < 20; i++) await Promise.resolve();
            assert.strictEqual(statusCalls, 1, "the watcher must not supersede an unpublished mutation result");
        } finally { release({exitCode: 0, stderr: "", stdout: reply("b".repeat(40), 2)}); }
        const published = await mutation;
        assert.strictEqual(published.state.position, 2);
        assert.strictEqual(manager.state.state.position, 2);
        assert.ok(events.some(state => state.state?.position === 2));
        await watcher;
        assert.strictEqual(statusCalls, 2);
    });

    it("a queued watcher rerun cannot supersede an unpublished mutation", async () => {
        let releaseOld!: (value: object) => void, releasePrimary!: (value: object) => void;
        const older = new Promise<object>(resolve => { releaseOld = resolve; });
        const primary = new Promise<object>(resolve => { releasePrimary = resolve; });
        let statusCalls = 0;
        const {manager} = pipeline(async verb => {
            if (verb === "status") {
                statusCalls++;
                if (statusCalls === 2) return older;
                if (statusCalls === 3) return primary;
            }
            return {exitCode: 0, stderr: "", stdout: verb === "--version" ? "999.0.0\n" : verb === "status" ? reply("b".repeat(40), 2) : ""};
        });
        await manager.refresh();
        const watcher = manager.refresh();
        for (let i = 0; i < 20 && statusCalls < 2; i++) await Promise.resolve();
        assert.strictEqual(statusCalls, 2);
        const mutation = manager.refreshPrimary();
        for (let i = 0; i < 20 && statusCalls < 3; i++) await Promise.resolve();
        assert.strictEqual(statusCalls, 3);
        const queued = manager.refresh();
        releaseOld({exitCode: 0, stderr: "", stdout: reply()});
        try {
            for (let i = 0; i < 30; i++) await Promise.resolve();
            assert.strictEqual(statusCalls, 3, "an older dirty read must wait for the mutation too");
        } finally { releasePrimary({exitCode: 0, stderr: "", stdout: reply("c".repeat(40), 2)}); }
        assert.strictEqual((await mutation).guard, "c".repeat(40));
        await Promise.all([watcher, queued]);
        assert.strictEqual(statusCalls, 4);
    });

    it("publishes the review with pending comments before waiting for their response", async () => {
        let release!: (value: object) => void;
        const comments = new Promise<object>(resolve => { release = resolve; });
        const calls: string[] = [];
        const {manager, events} = pipeline(async verb => {
            calls.push(verb);
            if (verb === "comments") return comments;
            return {exitCode: 0, stderr: "", stdout: verb === "--version" ? "999.0.0\n" : "state\treview/feature\tfeature\tdeadbeef\twhole\tnone\nentry\t1\tsample.txt"};
        });
        const refreshing = manager.refresh();
        // Flush promises rather than sleeping or making an elapsed-time assertion.
        for (let i = 0; i < 20 && !calls.includes("comments"); i++) await Promise.resolve();
        assert.ok(calls.includes("comments"));
        assert.strictEqual(events.length, 1);
        assert.strictEqual(manager.state.situation, "review");
        assert.strictEqual(manager.state.entries.length, 1);
        assert.strictEqual(manager.state.comments.loading, true);
        assert.deepStrictEqual(Array.from(manager.state.comments.documents), []);
        release({exitCode: 0, stderr: "", stdout: "comments-identity\tfresh\tNo comments context yet."});
        const complete = await refreshing;
        assert.strictEqual(events.length, 2);
        assert.ok(!complete.comments.loading);
        assert.strictEqual(manager.state, complete);
        assert.strictEqual(events[0].readId, events[1].readId);
    });
});

describe("optional Save state", () => {
    const wire = "save-state\t1\nstatus\t2\nlist\tbranch\treview-saved/feature\t1\t0\t0\twalk\t2\t3\nconfig\tconfig\tbase\tmain\nconfig\tconfig\tremote\torigin\nsave-state\tcomplete\n";
    it("publishes the final inventory and config without another primary query", async () => {
        const calls: string[] = [];
        const {manager} = pipeline(async verb => { calls.push(verb); return {stdout:"",stderr:"",exitCode:0}; });
        const state = await manager.refreshPrimary(wire);
        assert.deepStrictEqual(calls,["comments"]);
        assert.strictEqual(state.situation,"no-review");
        assert.strictEqual(state.branches[0].saved,true);
        assert.strictEqual(state.branches[0].position,2);
        assert.strictEqual(state.config.base,"main");
    });
    it("falls back without repeating a successful Save", async () => {
        const {parseSaveReply} = require("../../src/review/saveReply");
        for (const bad of ["",wire.replace("save-state\tcomplete\n",""),wire+"save-state\tcomplete\n",
            wire.replace("status\t2","status\t0"),wire.replace("list\tbranch","unknown\tbranch"),
            wire.replace("config\tconfig\tremote\torigin\n","")]) {
            assert.strictEqual(parseSaveReply(bad),undefined);
            const calls: string[] = [];
            const {manager} = pipeline(async verb => { calls.push(verb); return {stdout:"",stderr:"",exitCode:verb === "status" ? 2 : 0}; });
            await manager.refreshPrimary(bad);
            assert.deepStrictEqual(calls,["--version","status","list","config","comments"]);
        }
        assert.ok(parseSaveReply(wire.replace(/\n/g,"\r\n")));
    });
});
