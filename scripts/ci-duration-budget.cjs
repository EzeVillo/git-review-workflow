"use strict";

const {appendFileSync} = require("node:fs");
const {execFileSync} = require("node:child_process");
const reportJob = "Windows duration budget";

function latestJobs(jobs) {
    const latest = new Map();
    for (const job of jobs) {
        const old = latest.get(job.name);
        if (!old || (job.run_attempt ?? 0) > (old.run_attempt ?? 0) ||
            ((job.run_attempt ?? 0) === (old.run_attempt ?? 0) && job.id > old.id)) latest.set(job.name, job);
    }
    return [...latest.values()];
}

function compareDurations(jobs) {
    const complete = latestJobs(jobs).filter(job => job.name !== reportJob);
    const incomplete = complete.filter(job => job.status !== "completed" || job.conclusion !== "success").map(job => job.name);
    const timed = complete.filter(job => job.status === "completed" && job.conclusion === "success").map(job => {
        const milliseconds = Date.parse(job.completed_at) - Date.parse(job.started_at);
        if (!Number.isFinite(milliseconds) || milliseconds < 0) throw new Error(`Invalid timestamps for ${job.name}`);
        return {...job, milliseconds};
    });
    const hasLabel = (job, regex) => job.labels?.some(label => regex.test(label));
    const unix = timed.filter(job => hasLabel(job, /^(ubuntu|macos)(-|$)|^linux$/i));
    const windows = timed.filter(job => hasLabel(job, /^windows(-|$)/i)).sort((a, b) => b.milliseconds - a.milliseconds);
    if (!unix.length || !windows.length) throw new Error("Both Windows and Linux/macOS job results are required.");
    const reference = unix.reduce((max, job) => job.milliseconds > max.milliseconds ? job : max);
    const exceeded = windows.filter(job => job.milliseconds > reference.milliseconds);
    return {reference, windows, exceeded, incomplete, passed: !exceeded.length && !incomplete.length};
}

function markdown(result) {
    const name = value => value.replaceAll("|", "\\|").replaceAll("\n", " ");
    return ["## Windows duration budget", "",
        `Reference: **${name(result.reference.name)} — ${(result.reference.milliseconds / 60000).toFixed(2)} min**.`,
        "Execution time excludes time waiting for a runner. All tests finish before this comparison runs.", "",
        "| Windows job | Minutes | Within reference |", "|---|---:|---|",
        ...result.windows.map(job => `| ${name(job.name)} | ${(job.milliseconds / 60000).toFixed(2)} | ${job.milliseconds <= result.reference.milliseconds ? "yes" : "no"} |`),
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
            : `Windows jobs exceeded the Linux/macOS reference: ${result.exceeded.map(job => job.name).join(", ")}`);
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
