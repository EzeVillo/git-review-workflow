"""Measure the full guarded Save in disposable repositories, without changing installs."""
import argparse
import collections
import hashlib
import json
import os
import pathlib
import platform
import statistics
import subprocess
import tarfile
import time
import urllib.parse


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("candidate", type=pathlib.Path)
    parser.add_argument("helper", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--rounds", type=int, default=4)
    args = parser.parse_args()
    source, candidate, helper, out = [p.resolve() for p in
                                     (args.source, args.candidate, args.helper, args.output)]
    if args.rounds < 2:
        parser.error("Use at least two rounds per variant")
    if out.exists():
        parser.error("Use a new output directory")
    out.mkdir(parents=True)
    archive = out / "baseline.tar"
    subprocess.run(["git", "archive", "--format=tar", "-o", str(archive), "HEAD", "bin"],
                   cwd=source, check=True)
    baseline = out / "baseline"
    baseline.mkdir()
    with tarfile.open(archive) as tar:
        tar.extractall(baseline, filter="data")
    repo = out / "fixture"
    repo.mkdir()
    variants = {"baseline": baseline / "bin", "native": candidate / "bin"}
    env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(out / "global"),
               GIT_REVIEW_ADVICE="0", GIT_TERMINAL_PROMPT="0", GIT_REVIEW_META_HELPER=str(helper))
    env.pop("GIT_TRACE2_EVENT", None)
    git_tools = ["C:/Program Files/Git/bin", "C:/Program Files/Git/usr/bin"] if os.name == "nt" else []

    def call(arguments, variant="baseline", trace=None):
        extra = dict(env, PATH=os.pathsep.join([str(variants[variant]), *git_tools, os.environ["PATH"]]))
        if trace:
            extra["GIT_TRACE2_EVENT"] = trace.as_posix()
        start = time.perf_counter()
        result = subprocess.run(["git", *arguments], cwd=repo, env=extra,
                                capture_output=True, timeout=120)
        elapsed = time.perf_counter() - start
        if result.returncode:
            raise AssertionError((arguments, result.returncode, result.stderr))
        return result.stdout, elapsed

    def git(*arguments):
        return call(arguments)[0]

    def trace_counts(path):
        commands = [json.loads(line).get("argv", []) for line in path.read_text(encoding="utf-8").splitlines()
                    if json.loads(line).get("event") == "start"]
        return dict(collections.Counter(command[1] if len(command) > 1 else "?" for command in commands))

    git("init", "-q", "-b", "main")
    for key, value in [("user.name", "Benchmark fixture"), ("user.email", "perf@example.invalid"),
                       ("core.autocrlf", "false"), ("commit.gpgsign", "false"),
                       ("reviewworkflow.base", "main")]:
        git("config", key, value)
    (repo / "a.txt").write_bytes(b"Base.\n")
    git("add", "."); git("commit", "-qm", "base"); git("switch", "-qc", "feature/performance")
    (repo / "a.txt").write_bytes(b"Changed.\n")
    (repo / ".review").mkdir()
    (repo / ".review/walkthrough.md").write_bytes(b"# Walkthrough\n\n## 1. a.txt\n\nRead this change.\n")
    git("add", "."); git("commit", "-qm", "change"); git("switch", "-q", "main")
    git("review", "start", "--offline", "feature/performance")
    git("review", "comments", "add", "--document", "local", "--text", "Preserve this private note.")
    git("review", "comments", "add", "--document", "shared", "--text", "Preserve this Shared preparation.")
    session = git("config", "branch.review/feature/performance.reviewcommentssession").decode().strip()
    local = repo / ".git/review-comments/sessions" / session / "local.md"
    prose = {path: path.read_bytes() for path in [local, local.parent / "shared.md"]}
    (repo / "a.txt").write_bytes(b"Changed.\nPrivate code edit.\n")
    diff = git("diff", "--binary", "HEAD")
    rows = []
    # Two warmups, then balanced alternating pairs with their order reversed each round.
    order = ["baseline", "native"] + [v for i in range(args.rounds) for v in
                                      (["baseline", "native"] if i % 2 == 0 else ["native", "baseline"])]
    for index, variant in enumerate(order):
        status = git("review", "status", "--porcelain")
        candidate_status = call(["review", "status", "--porcelain"], "native")[0]
        guard = lambda data: next(line.split(b"\t")[1] for line in data.splitlines() if line.startswith(b"guard\t"))
        token = guard(status).decode()
        assert guard(candidate_status).decode() == token
        query_trace = out / f"{index}-{variant}-paths.jsonl"
        save_trace = out / f"{index}-{variant}-save.jsonl"
        started = time.perf_counter()
        paths_report, query_seconds = call(["review", "comments", "paths", "--porcelain"], variant, query_trace)
        lines = paths_report.decode().splitlines()
        assert lines[0] == f"comments-paths\t1\t{token}\t{session}"
        assert lines[-1] == "comments-paths\tcomplete"
        paths = {urllib.parse.unquote(line.split("\t", 2)[2]) for line in lines if line.startswith("comments-path\t")}
        assert paths == {p.as_posix() for p in prose}
        report, save_seconds = call(["review", "--expect-state", token, "save", "--porcelain"], variant, save_trace)
        total = time.perf_counter() - started
        lines = report.splitlines()
        assert lines[0] == b"save-state\t1" and lines[-1] == b"save-state\tcomplete"
        listed = b"\n".join(line[5:] for line in lines if line.startswith(b"list\t")) + b"\n"
        configured = b"\n".join(line[7:] for line in lines if line.startswith(b"config\t")) + b"\n"
        assert listed == git("review", "list", "--porcelain")
        assert configured == git("review", "config", "--porcelain")
        assert git("branch", "--show-current") == b"main\n" and git("status", "--porcelain") == b""
        assert all(path.read_bytes() == data for path, data in prose.items())
        row = dict(variant=variant, warmup=index < 2, query_seconds=query_seconds,
                   save_seconds=save_seconds, total_seconds=total,
                   query_git_commands=trace_counts(query_trace), save_git_commands=trace_counts(save_trace))
        rows.append(row)
        print(json.dumps(row), flush=True)
        git("review", "continue", "feature/performance")
        assert git("config", "branch.review/feature/performance.reviewcommentssession").decode().strip() == session
        assert all(path.read_bytes() == data for path, data in prose.items())
        assert git("diff", "--binary", "HEAD") == diff
        assert git("config", "branch.review/feature/performance.reviewwalkstep") == b"1\n"
    git("review", "save")
    report = dict(
        method="Native processes; 2 warmups, balanced alternating samples; small walk, Local + Shared and private edit. "
               "Both variants query paths then guarded Save with full porcelain reply. Trace2 enabled in both. "
               "Setup, guards, checks and Continue excluded. No IDE buffers, UI or painting measured.",
        platform=platform.platform(), git_version=git("--version").decode().strip(),
        baseline_head=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source).decode().strip(),
        candidate_lib_sha256=digest(candidate / "bin/git-review-lib.sh"),
        candidate_save_sha256=digest(candidate / "bin/git-review-verbs/save"),
        helper_sha256=digest(helper), samples=rows,
        medians={variant: {metric: statistics.median(row[metric] for row in rows
                                                   if row["variant"] == variant and not row["warmup"])
                           for metric in ["query_seconds", "save_seconds", "total_seconds"]} for variant in variants},
        checks=["cross-compatible opaque guards", "exact owned paths", "full list/config equals baseline",
                "main clean", "Local/Shared byte-identical", "Continue restores code, session and cursor"])
    (out / "summary.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report["medians"]), flush=True)


if __name__ == "__main__":
    main()
