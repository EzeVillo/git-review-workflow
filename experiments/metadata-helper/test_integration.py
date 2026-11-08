"""Black-box CLI checks for the isolated overlay, including safe fallback."""
import os
import pathlib
import json
import subprocess
import tempfile
import unittest
import urllib.parse

OVERLAY = pathlib.Path(os.environ["META_OVERLAY_BIN"]).resolve()
BASELINE = pathlib.Path(os.environ["META_BASELINE_BIN"]).resolve()
HELPER = pathlib.Path(os.environ["META_TEST_HELPER"]).resolve()


class IntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gr-meta-integration-")
        self.root = pathlib.Path(self.temp.name)
        self.env = dict(os.environ, PATH=str(OVERLAY) + os.pathsep + os.environ["PATH"],
                        GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(self.root / "global"),
                        GIT_REVIEW_ADVICE="0", GIT_REVIEW_META_HELPER=str(HELPER))

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args, status=0, baseline=False):
        env = self.env.copy()
        if baseline:
            env["PATH"] = str(BASELINE) + os.pathsep + env["PATH"]
        result = subprocess.run(["git", *args], cwd=self.repo, env=env,
                                capture_output=True, timeout=120)
        self.assertEqual(result.returncode, status, result.stderr)
        return result.stdout

    def start(self, mode="walk"):
        self.repo = self.root / mode
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main")
        for key, value in [("user.name", "Metadata experiment"),
                           ("user.email", "meta@example.invalid"),
                           ("core.autocrlf", "false"), ("commit.gpgsign", "false"),
                           ("reviewworkflow.base", "main")]:
            self.git("config", key, value)
        (self.repo / "a.txt").write_bytes(b"Base.\n")
        self.git("add", "."); self.git("commit", "-qm", "base")
        self.git("switch", "-qc", "feature/example")
        (self.repo / "a.txt").write_bytes(b"Changed.\n")
        if mode == "walk":
            (self.repo / ".review").mkdir()
            (self.repo / ".review/walkthrough.md").write_bytes(b"# Walkthrough\n\n## 1. a.txt\n\nRead this file.\n")
        self.git("add", "."); self.git("commit", "-qm", "change")
        self.git("switch", "-q", "main")
        if mode == "compare":
            self.git("review", "compare", "main", "feature/example")
        else:
            flags = ["--step"] if mode == "step" else ["--no-walk"] if mode == "whole" else []
            self.git("review", "start", "--offline", *flags, "feature/example")
        self.cur = self.git("branch", "--show-current").decode().strip()
        self.src = self.git("config", f"branch.{self.cur}.reviewsource").decode().strip()
        self.tip = self.git("config", f"branch.{self.cur}.reviewtip").decode().strip()
        self.git("review", "comments", "add", "--document", "local", "--text", "Keep the private note.")
        if mode != "compare":
            self.git("review", "comments", "add", "--document", "shared", "--text", "Keep the shared preparation.")
        rows = self.git("review", "comments", "paths", "--porcelain").decode().splitlines()
        paths = [pathlib.Path(urllib.parse.unquote(row.split("\t", 2)[2]))
                 for row in rows if row.startswith("comments-path\t")]
        self.prose = {path: path.read_bytes() if path.exists() else None for path in paths}
        self.session = self.git("config", f"branch.{self.cur}.reviewcommentssession")
        (self.repo / "a.txt").write_bytes(b"Changed.\nPrivate edit.\n")
        self.diff = self.git("diff", "--binary", "HEAD")
        self.private_diff = self.git("diff", "--binary", self.tip)

    def guard(self):
        old = self.git("review", "status", "--porcelain", baseline=True)
        new = self.git("review", "status", "--porcelain")
        get = lambda data: next(line.split(b"\t")[1] for line in data.splitlines() if line.startswith(b"guard\t"))
        self.assertEqual(get(old), get(new))
        return get(old).decode()

    def assert_prose(self):
        for path, expected in self.prose.items():
            self.assertEqual(path.read_bytes() if path.exists() else None, expected)

    def save_and_resume(self):
        result = self.git("review", "--expect-state", self.guard(), "save", "--porcelain")
        lines = result.splitlines()
        self.assertEqual(lines[0], b"save-state\t1")
        self.assertEqual(lines[-1], b"save-state\tcomplete")
        for prefix, verb in [(b"list\t", "list"), (b"config\t", "config")]:
            reported = b"\n".join(line[len(prefix):] for line in lines if line.startswith(prefix)) + b"\n"
            self.assertEqual(reported, self.git("review", verb, "--porcelain", baseline=True))
        self.assertEqual(self.git("branch", "--show-current"), b"main\n")
        self.assertEqual(self.git("status", "--porcelain"), b"")
        self.assert_prose()
        self.git("review", "continue", self.src)
        self.assertEqual(self.git("diff", "--binary", "HEAD"), self.diff)
        self.assertEqual(self.git("config", f"branch.{self.cur}.reviewcommentssession"), self.session)
        self.assert_prose()

    def test_save_in_all_four_modes(self):
        for mode in ["whole", "step", "walk", "compare"]:
            with self.subTest(mode=mode):
                self.start(mode)
                self.save_and_resume()

    def test_included_destination_metadata_uses_git_fallback(self):
        self.start()
        included = self.repo / ".git/included-meta"
        self.git("config", "--file", str(included), f"branch.review-saved/{self.src}.reviewmode", "whole")
        self.git("config", "include.path", included.as_posix())
        original = included.read_bytes()
        self.save_and_resume()
        self.assertEqual(included.read_bytes(), original)

    def test_special_scalar_uses_git_fallback(self):
        self.start()
        self.git("config", f"branch.{self.cur}.reviewdraft", "literal\tname")
        self.save_and_resume()
        self.assertEqual(self.git("config", f"branch.{self.cur}.reviewdraft"), b"literal\tname\n")

    def test_post_commit_error_is_not_retried_as_git_writes(self):
        self.start()
        wrapper = self.root / "helper-wrapper"
        count = self.root / "helper-calls"
        wrapper.write_text("""#!/bin/sh
set -eu
if [ "$1" = apply ]; then
    printf 'apply\\n' >>"$META_CALLS"
    if "$META_REAL_HELPER" "$@"; then
        printf 'error: injected failure after metadata commit\\n' >&2
        exit 42
    else exit "$?"
    fi
fi
exec "$META_REAL_HELPER" "$@"
""", encoding="utf-8", newline="\n")
        wrapper.chmod(0o755)
        log = self.root / "git-trace.jsonl"
        self.env.update(META_REAL_HELPER=str(HELPER), META_CALLS=str(count))
        token = self.guard()
        self.env["GIT_REVIEW_META_HELPER"] = str(wrapper)
        self.env["GIT_TRACE2_EVENT"] = log.as_posix()
        result = subprocess.run(["git", "review", "--expect-state", token, "save", "--porcelain"],
                                cwd=self.repo, env=self.env, capture_output=True, timeout=120)
        self.assertEqual((result.returncode, result.stdout), (1, b""))
        self.assertIn(b"injected failure after metadata commit", result.stderr)
        events = [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines()]
        calls = [event["argv"][1:] for event in events if event["event"] == "start"]
        self.assertFalse([argv for argv in calls if len(argv) > 1 and argv[0] == "config" and
                          argv[1].startswith(f"branch.review-saved/{self.src}.")])
        self.assertEqual(count.read_bytes(), b"apply\n")
        self.assertEqual(self.git("branch", "--show-current").decode().strip(), self.cur)
        self.assertEqual(self.git("diff", "--binary", self.tip, f"review-saved/{self.src}"), self.private_diff)
        self.assert_prose()


if __name__ == "__main__":
    unittest.main(verbosity=2)
