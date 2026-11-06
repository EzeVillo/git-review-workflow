import assert from "node:assert/strict";
import {test} from "node:test";
import budget from "./ci-duration-budget.cjs";

const job = (name, os, minutes, extra = {}) => ({
    id: 1, run_attempt: 1, name, labels: [os], status: "completed", conclusion: "success",
    started_at: "2026-11-05T00:00:00Z", completed_at: new Date(Date.parse("2026-11-05T00:00:00Z") + minutes * 60000).toISOString(), ...extra
});

test("every Windows job is compared against the slowest Linux or macOS job", () => {
    const jobs = [job("Linux", "ubuntu-latest", 18), job("Mac", "macos-latest", 42), job("Windows CLI", "windows-latest", 32), job("Windows IDE", "windows-latest", 24)];
    const result = budget.compareDurations(jobs);
    assert.equal(result.reference.name, "Mac");
    assert.equal(result.passed, true);
    assert.equal(result.windows.length, 2);
    assert.match(budget.markdown(result), /Windows IDE/);
    assert.equal(budget.compareDurations([...jobs, job("Windows new job", "windows-latest", 43)]).passed, false);
});

test("queue time does not count as execution time", () => {
    const result = budget.compareDurations([job("Mac", "macos-latest", 42), job("Windows", "windows-latest", 30, {
        created_at: "2026-11-04T23:00:00Z", started_at: "2026-11-05T00:30:00Z", completed_at: "2026-11-05T01:00:00Z"
    })]);
    assert.equal(result.windows[0].milliseconds, 30 * 60000);
    assert.equal(result.passed, true);
});

test("failed and skipped checks cannot pass by finishing early", () => {
    for (const state of [{conclusion: "failure"}, {conclusion: "skipped"}, {conclusion: "cancelled"}, {status: "in_progress", conclusion: null}]) {
        const jobs = [job("Linux", "ubuntu-latest", 18), job("Windows", "windows-latest", 2, state), job("Windows other", "windows-latest", 3)];
        const result = budget.compareDurations(jobs);
        assert.equal(result.passed, false);
        assert.deepEqual(result.incomplete, ["Windows"]);
    }
});

test("a partial rerun uses the latest result without losing previously successful jobs", () => {
    const jobs = [job("Mac", "macos-latest", 42), job("Windows", "windows-latest", 60), job("Windows", "windows-latest", 30, {id: 2, run_attempt: 2})];
    const result = budget.compareDurations(jobs);
    assert.equal(result.passed, true);
    assert.equal(result.windows[0].run_attempt, 2);
    assert.equal(result.reference.name, "Mac");
});

test("the report never becomes its own timing reference", () => {
    const result = budget.compareDurations([job("Mac", "macos-latest", 42), job("Windows", "windows-latest", 43), job("Windows duration budget", "ubuntu-latest", 100)]);
    assert.equal(result.passed, false);
    assert.equal(result.reference.name, "Mac");
    assert.throws(() => budget.compareDurations([job("Windows", "windows-latest", 1)]));
});
