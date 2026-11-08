import os
import pathlib
import random
import subprocess
import tempfile
import unittest

HELPER = pathlib.Path(os.environ["META_TEST_HELPER"]).resolve()
OK = b"\0__review_config_ok__\n\0"


def invoke(command, payload=b""):
    return subprocess.run([str(HELPER), command], input=payload, capture_output=True, timeout=15)


def message(path, operations, ending=True):
    fields = [b"git-review-meta-write-v1", os.fsencode(path)]
    for kind, key, value in operations:
        fields += [kind.encode(), key.encode(), value]
    if ending:
        fields.append(b"end")
    return b"\0".join(fields) + b"\0"


def reference_snapshot(payload):
    canonical, readable = [], []
    for record in payload.split(b"\0")[:-1]:
        if b"\n" not in record:
            continue
        key, value = record.split(b"\n", 1)
        canonical.append(key + b"\t" + b"".join(b"\\0%03o" % b for b in value) + b"\n")
        if key != b"__review_config_ok__":
            readable.append(key + b"\t" + b"".join(
                b"\\0%03o" % b if b < 32 or b in (92, 127) else bytes([b]) for b in value) + b"\n")
    return b"".join(canonical) + b"__review_config_values__\n" + b"".join(readable) + b"__review_config_end__\n"


class HelperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gr-meta-")
        self.root = pathlib.Path(self.temp.name)
        self.config = self.root / "config"
        self.original = b"# preserve this\n[other]\n\tuntouched = yes\n"
        self.config.write_bytes(self.original)
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(self.root / "global"))

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args, status=0):
        result = subprocess.run(["git", *args], cwd=self.root, env=self.env,
                                capture_output=True, timeout=15)
        self.assertEqual(result.returncode, status, result.stderr)
        return result.stdout

    def apply(self, operations, path=None, allow_fallback=False):
        path = path or self.config
        before = path.read_bytes()
        result = invoke("apply", message(path, operations))
        if result.returncode == 78 and allow_fallback:
            self.assertEqual((result.stdout, result.stderr), (b"", b""))
            self.assertEqual(path.read_bytes(), before)
            self.assertFalse(pathlib.Path(str(path) + ".lock").exists())
            for kind, key, value in operations:
                if kind == "set":
                    self.git("config", "--file", str(path), key, value.decode("utf-8"))
                else:
                    subprocess.run(["git", "config", "--file", str(path), "--unset", key],
                                   cwd=self.root, env=self.env, capture_output=True, timeout=15)
            return
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b"")

    def assert_no_write(self, result):
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"error: metadata helper:", result.stderr)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertFalse(pathlib.Path(str(self.config) + ".lock").exists())

    def test_protocol(self):
        result = invoke("--protocol-version")
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b"git-review-meta\t1\n", b""))

    def test_snapshot_exact_literal(self):
        payload = b"branch.review/a.reviewmode\nwalk\0" + OK
        result = invoke("encode", payload)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, b"")
        self.assertEqual(result.stdout, b"branch.review/a.reviewmode\t\\0167\\0141\\0154\\0153\n"
                         b"__review_config_ok__\t\n__review_config_values__\n"
                         b"branch.review/a.reviewmode\twalk\n__review_config_end__\n")

    def test_snapshot_all_non_nul_bytes_empty_and_duplicate_values(self):
        payload = (b"branch.review/a.reviewsource\n" + bytes(range(1, 256)) + b"\0"
                   b"branch.review/a.reviewmode\n\0branch.review/a.reviewmode\nwalk\0" + OK)
        result = invoke("encode", payload)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, reference_snapshot(payload))

    def test_snapshot_missing_success_marker_cannot_invent_success(self):
        for payload in [b"", b"key\nvalue", b"key\nvalue\0", b"__review_config_ok__\n"]:
            with self.subTest(payload=payload):
                result = invoke("encode", payload)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, reference_snapshot(payload))
                self.assertNotIn(b"__review_config_ok__\t", result.stdout)

    def test_snapshot_random_records_and_incomplete_tail(self):
        rng = random.Random(705)
        records = [b"branch.review/test.reviewkey%d\n" % i +
                   bytes(rng.randrange(1, 256) for _ in range(rng.randrange(300))) + b"\0" for i in range(80)]
        payload = b"".join(records) + OK + b"ignored\npartial"
        result = invoke("encode", payload)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, reference_snapshot(payload))

    def test_grouped_values_and_unrelated_content(self):
        values = [b"", b"leading trailing  ", b"tabs\tLF\nCR\r\\quotes\"'", "niño 漢字".encode(),
                  b"$(touch injected); 'literal'", b"\1\177", b"last LF\n\n"]
        operations = [("set", f"branch.review-saved/test.reviewfield{i}", value) for i, value in enumerate(values)]
        self.apply(operations, allow_fallback=True)
        actual = self.git("config", "--file", str(self.config), "--null", "--get-regexp", "^branch[.]")
        expected = {key.encode(): value for _, key, value in operations}
        self.assertEqual(dict(row.split(b"\n", 1) for row in actual.split(b"\0") if row), expected)
        self.assertEqual(self.git("config", "--file", str(self.config), "other.untouched"), b"yes\n")
        self.assertIn(b"# preserve this", self.config.read_bytes())
        self.assertFalse((self.root / "injected").exists())

    def test_unicode_and_spaces_in_config_path(self):
        path = self.root / "carpeta ñ 漢" / "config con espacio"
        path.parent.mkdir()
        path.write_bytes(self.original)
        self.apply([("set", "branch.review-saved/test.reviewmode", b"walk")], path)
        self.assertEqual(self.git("config", "--file", str(path), "branch.review-saved/test.reviewmode"), b"walk\n")
        self.assertEqual(self.config.read_bytes(), self.original)

    def test_supported_printable_values_use_the_native_path(self):
        values = [b"", b" leading trailing  ", b"quote' back\\slash\"", "niño 漢字".encode(),
                  bytes(range(32, 127)), bytes(range(128, 256))]
        operations = [("set", f"branch.review-saved/test.reviewfield{i}", value) for i, value in enumerate(values)]
        self.apply(operations)
        actual = self.git("config", "--file", str(self.config), "--null", "--get-regexp", "^branch[.]")
        self.assertEqual(dict(row.split(b"\n", 1) for row in actual.split(b"\0") if row),
                         {key.encode(): value for _, key, value in operations})

    def test_missing_config_is_created_with_exact_value(self):
        self.config.unlink()
        result = invoke("apply", message(self.config, [("set", "branch.review/a.reviewmode", b"walk")]))
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b"", b""))
        self.assertEqual(self.git("config", "--file", str(self.config), "branch.review/a.reviewmode"), b"walk\n")
        self.assertFalse(pathlib.Path(str(self.config) + ".lock").exists())

    def test_duplicate_unset_is_ignored_as_with_git(self):
        self.config.write_bytes(self.original + b'[branch "review-saved/test"]\n\treviewmode = first\n\treviewmode = second\n')
        before = self.git("config", "--file", str(self.config), "--null", "--get-all",
                          "branch.review-saved/test.reviewmode")
        self.apply([("unset", "branch.review-saved/test.reviewmode", b""),
                    ("set", "other.untouched", b"updated")])
        self.assertEqual(self.git("config", "--file", str(self.config), "--null", "--get-all",
                                 "branch.review-saved/test.reviewmode"), before)
        self.assertEqual(self.git("config", "--file", str(self.config), "other.untouched"), b"updated\n")

    def test_unsupported_value_does_not_publish_an_earlier_operation(self):
        result = invoke("apply", message(self.config, [
            ("set", "other.untouched", b"candidate"), ("set", "branch.review/a.reviewtip", b"LF\n")]))
        self.assertEqual((result.returncode, result.stdout, result.stderr), (78, b"", b""))
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertFalse(pathlib.Path(str(self.config) + ".lock").exists())

    def test_missing_key_unset_is_optional_and_empty_stays_empty(self):
        self.apply([("unset", "branch.review-saved/test.reviewcontext", b""),
                    ("set", "branch.review-saved/test.reviewempty", b"")])
        self.assertEqual(self.git("config", "--file", str(self.config),
                                 "branch.review-saved/test.reviewempty"), b"\n")

    def test_invalid_later_key_rolls_back_earlier_change(self):
        self.assert_no_write(invoke("apply", message(self.config, [
            ("set", "other.untouched", b"candidate"), ("set", "invalid key", b"value")])))

    def test_duplicate_destination_key_rejects_batch_without_partial_write(self):
        self.config.write_bytes(self.original + b"[branch \"review-saved/test\"]\n\treviewmode = first\n\treviewmode = second\n")
        before = self.config.read_bytes()
        result = invoke("apply", message(self.config, [
            ("set", "other.untouched", b"candidate"),
            ("set", "branch.review-saved/test.reviewmode", b"whole")]))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(b"error:", result.stderr)
        self.assertEqual(self.config.read_bytes(), before)
        self.assertFalse(pathlib.Path(str(self.config) + ".lock").exists())

    def test_foreign_lock_is_kept_and_file_is_unchanged(self):
        lock = pathlib.Path(str(self.config) + ".lock")
        lock.write_bytes(b"foreign lock")
        result = invoke("apply", message(self.config, [("set", "other.untouched", b"candidate")]))
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"lock", result.stderr.lower())
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertEqual(lock.read_bytes(), b"foreign lock")

    def test_malformed_messages_do_not_write(self):
        valid = message(self.config, [("set", "other.untouched", b"candidate")])
        payloads = [b"", valid.replace(b"write-v1", b"write-v2"),
                    message(self.config, [("set", "other.untouched", b"candidate")], ending=False),
                    valid + b"extra\0", valid[:-1],
                    message(self.config, [("unknown", "other.untouched", b"candidate")])]
        for payload in payloads:
            with self.subTest(payload=payload):
                self.assert_no_write(invoke("apply", payload))

    def test_included_file_is_unchanged_and_write_goes_to_root(self):
        included = self.root / "included"
        key = "branch.review-saved/test.reviewmode"
        self.git("config", "--file", str(included), key, "included")
        self.git("config", "--file", str(self.config), "include.path", included.as_posix())
        before = included.read_bytes()
        self.apply([("set", "other.untouched", b"candidate"), ("set", key, b"whole")], allow_fallback=True)
        self.assertEqual(included.read_bytes(), before)
        self.assertEqual(self.git("config", "--file", str(self.config), key), b"whole\n")
        self.assertEqual(self.git("config", "--file", str(self.config), "--includes", key), b"whole\n")

    def test_root_value_with_same_key_in_include(self):
        included = self.root / "included"
        key = "branch.review-saved/test.reviewmode"
        self.git("config", "--file", str(included), key, "included")
        self.git("config", "--file", str(self.config), "include.path", included.as_posix())
        self.git("config", "--file", str(self.config), key, "root")
        before = included.read_bytes()
        self.apply([("set", key, b"updated")], allow_fallback=True)
        self.assertEqual(included.read_bytes(), before)
        self.assertEqual(self.git("config", "--file", str(self.config), key), b"updated\n")

    def test_symlink_target_is_rejected_without_changing_either_file(self):
        link = self.root / "linked"
        try:
            link.symlink_to(self.config)
        except OSError as error:
            self.skipTest(f"symlink unavailable: {error}")
        result = invoke("apply", message(link, [("set", "other.untouched", b"candidate")]))
        self.assertEqual((result.returncode, result.stdout, result.stderr), (78, b"", b""))
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertTrue(link.is_symlink())


if __name__ == "__main__":
    unittest.main(verbosity=2)
