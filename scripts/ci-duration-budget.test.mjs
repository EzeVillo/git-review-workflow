import assert from "node:assert/strict";
import {test} from "node:test";
import budget from "./ci-duration-budget.cjs";

const job = (name, minutes, extra = {}) => ({
    id: 1, run_attempt: 1, name, status: "completed", conclusion: "success",
    started_at: "2026-11-06T00:00:00Z", completed_at: new Date(Date.parse("2026-11-06T00:00:00Z") + minutes * 60000).toISOString(), ...extra
});

test("every platform uses the same absolute ten-minute budget", () => {
    const result = budget.compareDurations([job("Linux", 11), job("Mac", 12), job("Windows", 13), job("Landing", 1)]);
    assert.equal(result.passed, false);
    assert.deepEqual(result.exceeded.map(j => j.name), ["Windows", "Mac", "Linux"]);
    assert.match(budget.markdown(result), /Maximum execution time per job: \*\*10.00 min\*\*/);
    assert.equal(budget.compareDurations([job("Linux", 8), job("Mac", 10), job("Windows", 9)]).passed, true);
    assert.equal(budget.compareDurations([job("Linux", 10.001)]).passed, false);
});

test("queue time does not count as execution time", () => {
    const result = budget.compareDurations([job("Windows", 8, {
        created_at: "2026-11-05T23:00:00Z", started_at: "2026-11-06T00:30:00Z", completed_at: "2026-11-06T00:38:00Z"
    })]);
    assert.equal(result.jobs[0].milliseconds, 8 * 60000);
    assert.equal(result.passed, true);
});

test("failed and skipped checks cannot pass by finishing early", () => {
    for (const state of [{conclusion: "failure"}, {conclusion: "skipped"}, {conclusion: "cancelled"}, {status: "in_progress", conclusion: null}]) {
        const result = budget.compareDurations([job("Broken", 2, state), job("Other", 3)]);
        assert.equal(result.passed, false);
        assert.deepEqual(result.incomplete, ["Broken"]);
    }
});

test("partial reruns keep successful jobs and use the latest result by name", () => {
    const jobs = [job("Mac", 9), job("Windows", 12), job("Windows", 8, {id: 2, run_attempt: 2})];
    const result = budget.compareDurations(jobs);
    assert.equal(result.passed, true);
    assert.equal(result.jobs.find(j => j.name === "Windows").run_attempt, 2);
    assert.equal(result.jobs.length, 2);
});

test("the reporting job cannot exceed its own budget or hide missing results", () => {
    const result = budget.compareDurations([job("Mac", 9), job("CI duration budget", 100)]);
    assert.equal(result.passed, true);
    assert.deepEqual(result.jobs.map(j => j.name), ["Mac"]);
    assert.throws(() => budget.compareDurations([job("CI duration budget", 1)]));
    assert.throws(() => budget.compareDurations([job("Mac", 1)], 0));
    assert.throws(() => budget.compareDurations([job("Mac", 1, {completed_at: "invalid"})]));
});
