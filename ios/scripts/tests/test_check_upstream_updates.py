"""Offline regressions for the manual checker; no GitHub requests or Git writes.

Original Earshot: HellzYeahh and contributors (MIT); AI-assisted iOS port.
"""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
import urllib.error


SCRIPT = Path(__file__).resolve().parents[1] / "check-upstream-updates.py"
SPEC = importlib.util.spec_from_file_location("earshot_upstream_checker", SCRIPT)
checker = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = checker
SPEC.loader.exec_module(checker)

BASE = "a" * 40
HEAD = "b" * 40
OTHER = "c" * 40


def baseline():
    return checker.Baseline(checker.REPOSITORY, BASE, "0.4.0")


def commit(number, title="An upstream improvement"):
    return {"sha": "%040x" % number, "commit": {"message": title}}


def comparison(status="ahead", total=1, *, files=None, commits=None, merge_base=BASE):
    return {"status": status, "total_commits": total,
            "ahead_by": total if status in {"ahead", "diverged"} else 0,
            "behind_by": 1 if status in {"behind", "diverged"} else 0,
            "merge_base_commit": {"sha": merge_base},
            "commits": [commit(1)] if commits is None else commits,
            "files": [] if files is None else files}


class FakeGET:
    def __init__(self, pages, *, branch="main", head=HEAD, full_name=checker.REPOSITORY, base=BASE):
        self.pages = pages
        self.branch = branch
        self.head = head
        self.full_name = full_name
        self.base = base
        self.calls = []

    def __call__(self, path):
        self.calls.append(path)
        if path == checker.API_PATH:
            return {"full_name": self.full_name, "default_branch": self.branch}
        if path.startswith(checker.API_PATH + "/commits?"):
            return [{"sha": self.head}]
        for page, response in enumerate(self.pages, start=1):
            expected = checker.API_PATH + "/compare/" + self.base + "..." + self.head + "?per_page=100&page=" + str(page)
            if path == expected:
                return response
        raise AssertionError("Unexpected checker GET endpoint")


class ComparisonTests(unittest.TestCase):
    def test_identical_requires_exact_pinned_head_and_zero_counts(self):
        get = FakeGET([comparison("identical", 0, commits=[])], head=BASE)
        report = checker.check_upstream(baseline(), get)
        self.assertEqual(report.state, "identical")
        self.assertFalse(report.commits_capped)
        self.assertEqual(len(get.calls), 3)
        contradictory = FakeGET([comparison("identical", 0, commits=[])])
        self.assertEqual(checker.check_upstream(baseline(), contradictory).state, "manual-review")

    def test_ahead_is_only_accepted_with_baseline_merge_base(self):
        report = checker.check_upstream(baseline(), FakeGET([comparison()]))
        self.assertEqual(report.state, "ahead")
        for merge in [OTHER, None]:
            page = comparison()
            page["merge_base_commit"] = {"sha": merge} if merge else None
            self.assertEqual(checker.check_upstream(baseline(), FakeGET([page])).state, "manual-review")

    def test_behind_diverged_and_unknown_are_review_states(self):
        behind = comparison("behind", 0, commits=[], merge_base=HEAD)
        self.assertEqual(checker.check_upstream(baseline(), FakeGET([behind])).state, "behind")
        self.assertEqual(checker.check_upstream(baseline(), FakeGET([comparison("diverged")])).state, "diverged")
        self.assertEqual(checker.check_upstream(baseline(), FakeGET([comparison("unexpected")])).state, "manual-review")

    def test_pagination_pins_both_shas_and_collects_the_final_short_page(self):
        pages = [comparison(total=205, commits=[commit(i) for i in range(1, 101)]),
                 comparison(total=205, commits=[commit(i) for i in range(101, 201)]),
                 comparison(total=205, commits=[commit(i) for i in range(201, 206)])]
        get = FakeGET(pages, branch="feature/new/default")
        report = checker.check_upstream(baseline(), get)
        self.assertEqual(len(report.commits), 205)
        self.assertFalse(report.commits_capped)
        self.assertEqual(sum("/commits?" in call for call in get.calls), 1)
        self.assertIn("sha=feature%2Fnew%2Fdefault", get.calls[1])
        self.assertEqual(get.calls[2:], [checker.API_PATH + "/compare/" + BASE + "..." + HEAD + "?per_page=100&page=" + str(i) for i in range(1, 4)])

    def test_500_commit_bound_never_fetches_a_sixth_page(self):
        pages = [comparison(total=900, commits=[commit(i) for i in range(start, start + 100)]) for start in [1, 101, 201, 301, 401]]
        get = FakeGET(pages)
        report = checker.check_upstream(baseline(), get)
        self.assertEqual(len(report.commits), 500)
        self.assertTrue(report.commits_capped)
        self.assertEqual(len(get.calls), 7)
        self.assertIn("INCOMPLETE", checker.render_report(report))

    def test_exact_500_and_short_incomplete_pages_are_distinguished(self):
        pages = [comparison(total=500, commits=[commit(i) for i in range(start, start + 100)]) for start in [1, 101, 201, 301, 401]]
        self.assertFalse(checker.check_upstream(baseline(), FakeGET(pages)).commits_capped)
        short = checker.check_upstream(baseline(), FakeGET([comparison(total=3)]))
        self.assertTrue(short.commits_capped)
        self.assertEqual(len(short.commits), 1)

    def test_files_come_only_from_first_page_and_300_is_flagged(self):
        files = [{"filename": "protocol/File%d.kt" % i, "status": "modified"} for i in range(300)]
        pages = [comparison(total=101, files=files, commits=[commit(i) for i in range(1, 101)]),
                 comparison(total=101, files=[{"filename": "do-not-use", "status": "added"}], commits=[commit(101)])]
        report = checker.check_upstream(baseline(), FakeGET(pages))
        self.assertEqual(len(report.files), 300)
        self.assertTrue(report.files_capped)
        self.assertNotIn("do-not-use", checker.render_report(report))
        self.assertIn("POSSIBLY INCOMPLETE", checker.render_report(report))

    def test_rename_classifies_both_paths_and_preserves_licence_review(self):
        files = [{"filename": "protocol/Codec.kt", "previous_filename": "dsp/Codec.kt", "status": "renamed"},
                 {"filename": "app/Notice", "previous_filename": "docs/research/LICENSE", "status": "renamed"}]
        report = checker.check_upstream(baseline(), FakeGET([comparison(files=files)]))
        self.assertEqual(checker.classify_file(report.files[0]), ["DSP", "Protocol"])
        self.assertEqual(checker.classify_file(report.files[1]), ["Android app", "Docs / research", "Licences / notices"])
        self.assertEqual(checker.classify_file({"filename": "THIRD_PARTY_NOTICES.md"}), ["Licences / notices"])

    def test_remote_markup_controls_bidi_and_links_cannot_become_report_markup(self):
        hostile = '</code><script>alert("x")</script>\x1b[31m\u202e![x](https://evil.invalid)'
        file = {"filename": hostile, "previous_filename": "docs/<img src=x onerror=alert(1)>", "status": hostile}
        get = FakeGET([comparison(files=[file], commits=[commit(1, hostile + "\nprivate second line")])], branch=hostile)
        report = checker.check_upstream(baseline(), get)
        text = checker.render_report(report)
        self.assertIn("&lt;script&gt;", text)
        self.assertNotIn("<script>", text)
        self.assertNotIn("<img", text)
        self.assertNotIn("\x1b", text)
        self.assertNotIn("\u202e", text)
        self.assertNotIn("private second line", text)
        self.assertNotIn('href="https://evil.invalid', text)
        self.assertIn("<pre><code>", text)
        self.assertIn("HellzYeahh and contributors", text)
        self.assertIn("MIT", text)

    def test_malformed_shas_counts_and_foreign_repository_fail_closed(self):
        for sha in ["short", "../main", "A" * 40, HEAD + "/path"]:
            with self.subTest(sha_shape=len(sha)), self.assertRaises(checker.CheckError):
                checker.check_upstream(baseline(), FakeGET([comparison()], head=sha))
        with self.assertRaises(checker.CheckError):
            checker.check_upstream(baseline(), FakeGET([comparison()], full_name="someone/earshot"))
        for bad_count in [-1, True, "1"]:
            page = comparison(); page["total_commits"] = bad_count
            with self.assertRaises(checker.CheckError):
                checker.check_upstream(baseline(), FakeGET([page]))

    def test_duplicate_or_changed_comparison_pages_fail_closed(self):
        first = comparison(total=101, commits=[commit(i) for i in range(1, 101)])
        for second in [comparison(total=101, commits=[commit(1)]), comparison("diverged", total=101, commits=[commit(101)])]:
            with self.assertRaises(checker.CheckError):
                checker.check_upstream(baseline(), FakeGET([first, second]))


class BaselineAndCLITests(unittest.TestCase):
    def write_baseline(self, directory, value=None):
        path = Path(directory) / "baseline.json"
        path.write_text(json.dumps(value if value is not None else {"repository": checker.REPOSITORY, "imported_commit": BASE, "imported_version": "0.4.0"}), encoding="utf-8")
        return path

    def test_baseline_is_relative_to_script_repository_instead_of_cwd(self):
        self.assertEqual(checker.BASELINE_PATH, SCRIPT.parents[2] / "docs/upstream-baseline.json")
        for value in [None, {}, {"repository": "other/repo", "imported_commit": BASE, "imported_version": "0.4.0"},
                      {"repository": checker.REPOSITORY, "imported_commit": "main", "imported_version": "0.4.0"},
                      {"repository": checker.REPOSITORY, "imported_commit": BASE, "imported_version": ""}]:
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "baseline.json"
                path.write_text(json.dumps(value), encoding="utf-8")
                with self.assertRaises(checker.CheckError):
                    checker.load_baseline(path)

    def test_reviewed_boundary_keeps_android_import_provenance(self):
        payload = {"repository": checker.REPOSITORY, "imported_commit": BASE, "imported_version": "0.4.0",
                   "reviewed_commit": OTHER, "reviewed_version": "0.5.0", "review_audit": "docs/IOS_UPSTREAM_REVIEW.md"}
        with tempfile.TemporaryDirectory() as directory:
            loaded = checker.load_baseline(self.write_baseline(directory, payload))
        self.assertEqual(loaded.imported_commit, BASE)
        self.assertEqual(loaded.imported_version, "0.4.0")
        self.assertEqual(loaded.comparison_commit, OTHER)
        get = FakeGET([comparison(merge_base=OTHER)], base=OTHER)
        self.assertEqual(checker.check_upstream(loaded, get).state, "ahead")
        self.assertIn("/compare/" + OTHER + "..." + HEAD, get.calls[-1])

    def test_incomplete_or_invalid_review_metadata_fails_closed_before_requests(self):
        invalid = [{"reviewed_commit": "main", "reviewed_version": "0.5.0"},
                   {"reviewed_commit": OTHER}, {"reviewed_commit": OTHER, "reviewed_version": ""},
                   {"reviewed_version": "0.5.0"}, {"review_audit": "docs/review.md"},
                   {"reviewed_commit": OTHER, "reviewed_version": "0.5.0", "review_audit": {}},
                   {"reviewed_commit": "A" * 40, "reviewed_version": "0.5.0"}]
        for extra in invalid:
            with self.subTest(extra=extra), tempfile.TemporaryDirectory() as directory:
                payload = {"repository": checker.REPOSITORY, "imported_commit": BASE, "imported_version": "0.4.0", **extra}
                with self.assertRaises(checker.CheckError):
                    checker.load_baseline(self.write_baseline(directory, payload))
        get = mock.Mock()
        with self.assertRaises(checker.CheckError):
            checker.check_upstream(checker.Baseline(checker.REPOSITORY, BASE, "0.4.0", "../main", "0.5.0"), get)
        get.assert_not_called()

    def test_reviewed_identical_checks_reviewed_sha_instead_of_android_snapshot(self):
        reviewed = checker.Baseline(checker.REPOSITORY, BASE, "0.4.0", OTHER, "0.5.0")
        get = FakeGET([comparison("identical", 0, commits=[], merge_base=OTHER)], base=OTHER, head=OTHER)
        self.assertEqual(checker.check_upstream(reviewed, get).state, "identical")

    def test_review_report_preserves_provenance_and_escapes_audit_metadata(self):
        reviewed = checker.Baseline(checker.REPOSITORY, BASE, "0.4.0", OTHER, "0.5.0", '</code><script>audit</script>')
        report = checker.check_upstream(reviewed, FakeGET([comparison(merge_base=OTHER)], base=OTHER))
        text = checker.render_report(report)
        self.assertIn("Imported Android provenance: [" + BASE, text)
        self.assertIn("Pinned baseline: [" + OTHER, text)
        self.assertIn("0.4.0", text)
        self.assertIn("0.5.0", text)
        self.assertIn("&lt;script&gt;", text)
        self.assertNotIn("<script>", text)

    def test_reviewed_cli_check_never_advances_either_boundary(self):
        with tempfile.TemporaryDirectory() as directory:
            payload = {"repository": checker.REPOSITORY, "imported_commit": BASE, "imported_version": "0.4.0",
                       "reviewed_commit": OTHER, "reviewed_version": "0.5.0", "review_audit": "docs/review.md"}
            path = self.write_baseline(directory, payload)
            original = path.read_bytes()
            get = FakeGET([comparison("identical", 0, commits=[], merge_base=OTHER)], base=OTHER, head=OTHER)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(checker.main(["--output", str(Path(directory) / "review.md")], get_json=get, baseline_path=path), 0)
            self.assertEqual(path.read_bytes(), original)

    def test_success_writes_markdown_only_to_requested_path_and_fixed_stdout(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_baseline(directory)
            original = path.read_bytes()
            output = Path(directory) / "report.md"
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                result = checker.main(["--output", str(output)], get_json=FakeGET([comparison(commits=[commit(1, "UNTRUSTED TITLE")])]), baseline_path=path)
            self.assertEqual(result, 0)
            self.assertEqual(stdout.getvalue(), "Upstream check: updates available; manual review required.\n")
            self.assertEqual(stderr.getvalue(), "")
            self.assertIn("UNTRUSTED TITLE", output.read_text())
            self.assertEqual(path.read_bytes(), original)

    def test_output_cannot_replace_baseline_and_missing_output_exits_two(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_baseline(directory)
            original = path.read_bytes()
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(checker.main(["--output", str(path)], baseline_path=path), 2)
                with self.assertRaises(SystemExit) as error:
                    checker.main([])
            self.assertEqual(error.exception.code, 2)
            self.assertEqual(path.read_bytes(), original)

    def test_api_exception_cannot_leak_environment_credentials_or_remote_error_body(self):
        marker = "PRIVATE_TEST_CREDENTIAL_VALUE"
        def failing_get(path):
            raise urllib.error.HTTPError("https://evil.invalid/" + marker, 403, marker, None, None)
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_baseline(directory)
            stdout, stderr = io.StringIO(), io.StringIO()
            with mock.patch.dict(os.environ, {"GH_TOKEN": marker}), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                result = checker.main(["--output", str(Path(directory) / "report.md")], get_json=failing_get, baseline_path=path)
            self.assertEqual(result, 2)
            self.assertEqual(stdout.getvalue(), "")
            self.assertNotIn(marker, stderr.getvalue())
            self.assertNotIn("evil.invalid", stderr.getvalue())


class HTTPBoundaryTests(unittest.TestCase):
    def test_only_explicit_get_to_fixed_repository_and_token_stays_in_header(self):
        client = checker.GitHubGET("PRIVATE_TEST_CREDENTIAL_VALUE")
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = b'{"ok": true}'
        client._opener = mock.Mock()
        client._opener.open.return_value = response
        self.assertEqual(client(checker.API_PATH), {"ok": True})
        request = client._opener.open.call_args.args[0]
        self.assertEqual(request.get_method(), "GET")
        self.assertEqual(request.full_url, checker.API_ROOT + checker.API_PATH)
        self.assertNotIn("PRIVATE_TEST_CREDENTIAL_VALUE", request.full_url)
        for path in ["https://evil.invalid/", "//evil.invalid/", "/repos/other/repo", checker.API_PATH + "/../other", checker.API_PATH + "#fragment"]:
            with self.assertRaises(checker.CheckError):
                client(path)

    def test_http_errors_and_redirects_have_only_safe_fixed_messages(self):
        client = checker.GitHubGET("PRIVATE_TEST_CREDENTIAL_VALUE")
        for failure, message in [(urllib.error.HTTPError("secret-url", 403, "secret-body", None, None), "GitHub API returned HTTP 403."),
                                 (urllib.error.URLError("secret-reason"), "The GitHub API could not be reached.")]:
            client._opener = mock.Mock()
            client._opener.open.side_effect = failure
            with self.assertRaises(checker.CheckError) as error:
                client(checker.API_PATH)
            self.assertEqual(str(error.exception), message)
        with self.assertRaises(checker.CheckError) as error:
            checker.NoRedirects().redirect_request(None, None, 302, "secret", None, "https://evil.invalid/secret")
        self.assertNotIn("secret", str(error.exception))

    def test_unreadable_or_oversized_api_response_fails_without_echoing_body(self):
        client = checker.GitHubGET()
        for body in [b"NOT JSON secret", b"x" * (checker.MAX_RESPONSE_BYTES + 1)]:
            response = mock.MagicMock()
            response.__enter__.return_value.read.return_value = body
            client._opener = mock.Mock()
            client._opener.open.return_value = response
            with self.assertRaises(checker.CheckError) as error:
                client(checker.API_PATH)
            self.assertNotIn("secret", str(error.exception))


if __name__ == "__main__":
    unittest.main()
