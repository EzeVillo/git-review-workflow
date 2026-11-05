import * as assert from "node:assert";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {runInNewContext} from "node:vm";
import * as ts from "typescript";

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

describe("incremental review refresh", () => {
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
