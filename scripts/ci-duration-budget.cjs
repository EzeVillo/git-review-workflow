"use strict";

const {appendFileSync} = require("node:fs");
const {execFileSync} = require("node:child_process");
const {readProfile} = require("./ci-shards.cjs");
const reportJob = "CI duration budget";

function latestJobs(jobs) {
    const latest = new Map();
    for (const job of jobs) {
        const old = latest.get(job.name);
        if (!old || (job.run_attempt ?? 0) > (old.run_attempt ?? 0) ||
            ((job.run_attempt ?? 0) === (old.run_attempt ?? 0) && job.id > old.id)) latest.set(job.name, job);
    }
    return [...latest.values()];
}

function compareDurations(jobs, maximumMilliseconds = readProfile().maximumMilliseconds) {
    if (!Number.isFinite(maximumMilliseconds) || maximumMilliseconds <= 0) throw new Error("Invalid job duration budget.");
    const complete = latestJobs(jobs).filter(job => job.name !== reportJob);
    const incomplete = complete.filter(job => job.status !== "completed" || job.conclusion !== "success").map(job => job.name);
    const timed = complete.filter(job => job.status === "completed" && job.conclusion === "success").map(job => {
        const milliseconds = Date.parse(job.completed_at) - Date.parse(job.started_at);
        if (!Number.isFinite(milliseconds) || milliseconds < 0) throw new Error(`Invalid timestamps for ${job.name}`);
        return {...job, milliseconds};
    });
    if (!complete.length) throw new Error("Completed CI jobs are required.");
    timed.sort((a, b) => b.milliseconds - a.milliseconds);
    const exceeded = timed.filter(job => job.milliseconds > maximumMilliseconds);
    return {maximumMilliseconds, jobs: timed, exceeded, incomplete, passed: !exceeded.length && !incomplete.length};
}

function markdown(result) {
    const name = value => value.replaceAll("|", "\\|").replaceAll("\n", " ");
    return ["## CI duration budget", "",
        `Maximum execution time per job: **${(result.maximumMilliseconds / 60000).toFixed(2)} min**.`,
        "Execution time excludes time waiting for a runner. All tests finish before this comparison runs.", "",
        "| Job | Minutes | Within budget |", "|---|---:|---|",
        ...result.jobs.map(job => `| ${name(job.name)} | ${(job.milliseconds / 60000).toFixed(2)} | ${job.milliseconds <= result.maximumMilliseconds ? "yes" : "no"} |`),
        ...(result.incomplete.length ? ["", `Checks without a successful result: ${result.incomplete.map(name).join(", ")}.`] : [])
    ].join("\n") + "\n";
}

module.exports = {latestJobs, compareDurations, markdown};
if (require.main === module) {
    try {
        const repository = process.env.GITHUB_REPOSITORY;
        const run = process.env.GITHUB_RUN_ID;
        if (!/^[\w.-]+\/[\w.-]+$/.test(repository ?? "") || !/^[0-9]+$/.test(run ?? "")) throw new Error("Repository and workflow run are required.");
        // filter=all also keeps successful jobs from earlier attempts when only
        // failed jobs were re-run. Select the latest attempt of each job name.
        const pages = JSON.parse(execFileSync("gh", ["api", "--paginate", "--slurp",
            `repos/${repository}/actions/runs/${run}/jobs?filter=all&per_page=100`],
        {encoding: "utf8", maxBuffer: 20 * 1024 * 1024, timeout: 120000}));
        const result = compareDurations(pages.flatMap(page => page.jobs));
        const summary = markdown(result);
        console.log(summary);
        if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
        if (!result.passed) throw new Error(result.incomplete.length
            ? "The timing budget requires all checks to pass."
            : `Jobs exceeded the ten-minute budget: ${result.exceeded.map(job => job.name).join(", ")}`);
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
