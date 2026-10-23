#!/usr/bin/env python3
"""Manually inspect upstream Earshot; never import changes or advance the baseline.

Original Earshot: HellzYeahh and contributors, MIT. This checker supports the
experimental AI-assisted native iOS port and does not claim upstream authorship.
Only public GitHub REST GET endpoints for that exact repository are permitted.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import html
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import unicodedata
import urllib.error
import urllib.parse
import urllib.request


REPOSITORY = "HellzYeahh/earshot"
API_ROOT = "https://api.github.com"
REPOSITORY_URL = "https://github.com/" + REPOSITORY
API_PATH = "/repos/" + REPOSITORY
BASELINE_PATH = Path(__file__).resolve().parents[2] / "docs/upstream-baseline.json"
SHA_PATTERN = re.compile(r"[0-9a-f]{40}\Z")
PAGE_SIZE = 100
MAX_COMMITS = 500
MAX_FILES = 300
MAX_RESPONSE_BYTES = 8 * 1024 * 1024


class CheckError(Exception):
    """Messages are fixed local text: never API bodies, request headers or tokens."""


@dataclass(frozen=True)
class Baseline:
    repository: str
    imported_commit: str
    imported_version: str
    reviewed_commit: str | None = None
    reviewed_version: str | None = None
    review_audit: str | None = None

    @property
    def comparison_commit(self) -> str:
        return self.reviewed_commit or self.imported_commit


@dataclass
class UpstreamReport:
    baseline: Baseline
    branch: str
    head: str
    merge_base: str | None
    state: str
    commits: list[dict]
    total_commits: int
    commits_capped: bool
    files: list[dict]
    files_capped: bool
    ahead_by: int
    behind_by: int


def validated_sha(value) -> str:
    if not isinstance(value, str) or not SHA_PATTERN.fullmatch(value):
        raise CheckError("GitHub returned an invalid commit identifier.")
    return value


def load_baseline(path: Path = BASELINE_PATH) -> Baseline:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeError):
        raise CheckError("The pinned upstream baseline could not be read.") from None
    if not isinstance(payload, dict) or payload.get("repository") != REPOSITORY:
        raise CheckError("The baseline must name the original Earshot repository.")
    sha = payload.get("imported_commit")
    if not isinstance(sha, str) or not SHA_PATTERN.fullmatch(sha):
        raise CheckError("The baseline must pin a complete lowercase commit SHA.")
    version = payload.get("imported_version")
    if not isinstance(version, str) or not version.strip() or len(version) > 100:
        raise CheckError("The baseline must include its imported version.")
    baseline = Baseline(REPOSITORY, sha, version, payload.get("reviewed_commit"),
                        payload.get("reviewed_version"), payload.get("review_audit"))
    validate_baseline(baseline)
    return baseline


def validate_baseline(baseline: Baseline) -> None:
    if baseline.repository != REPOSITORY:
        raise CheckError("The baseline must name the original Earshot repository.")
    validated_sha(baseline.imported_commit)
    if not isinstance(baseline.imported_version, str) or not baseline.imported_version.strip() or len(baseline.imported_version) > 100:
        raise CheckError("The baseline must include its imported version.")
    if baseline.reviewed_commit is None:
        if baseline.reviewed_version is not None or baseline.review_audit is not None:
            raise CheckError("Review metadata requires an explicit reviewed commit.")
        return
    validated_sha(baseline.reviewed_commit)
    if not isinstance(baseline.reviewed_version, str) or not baseline.reviewed_version.strip() or len(baseline.reviewed_version) > 100:
        raise CheckError("A reviewed baseline must include its reviewed version.")
    if baseline.review_audit is not None and (not isinstance(baseline.review_audit, str) or not baseline.review_audit.strip() or len(baseline.review_audit) > 2048):
        raise CheckError("The review audit reference must be bounded nonempty text.")


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        # An API redirect must never forward the optional token to another host.
        raise CheckError("GitHub redirected the request; manual review is required.")


class GitHubGET:
    def __init__(self, token: str | None = None):
        self._token = token
        self._opener = urllib.request.build_opener(NoRedirects())

    def __call__(self, path: str):
        parsed = urllib.parse.urlsplit(path)
        if (parsed.scheme or parsed.netloc or parsed.fragment or
                not (parsed.path == API_PATH or parsed.path.startswith(API_PATH + "/")) or
                ".." in parsed.path.split("/")):
            raise CheckError("The checker refused an endpoint outside upstream Earshot.")
        headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
                   "User-Agent": "Earshot-iOS-manual-upstream-check"}
        if self._token:
            headers["Authorization"] = "Bearer " + self._token
        try:
            request = urllib.request.Request(API_ROOT + path, headers=headers, method="GET")
            with self._opener.open(request, timeout=30) as response:
                raw = response.read(MAX_RESPONSE_BYTES + 1)
            if len(raw) > MAX_RESPONSE_BYTES:
                raise CheckError("The GitHub response exceeded the checker size limit.")
            return json.loads(raw)
        except urllib.error.HTTPError as error:
            raise CheckError("GitHub API returned HTTP %d." % error.code) from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise CheckError("The GitHub API could not be reached.") from None
        except (ValueError, UnicodeError):
            raise CheckError("GitHub returned unreadable JSON data.") from None


def nonnegative_int(value) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise CheckError("GitHub returned invalid comparison counts.")
    return value


def _commit_records(value) -> list[dict]:
    if not isinstance(value, list) or len(value) > PAGE_SIZE:
        raise CheckError("GitHub returned an invalid commit page.")
    records = []
    for item in value:
        if not isinstance(item, dict) or not isinstance(item.get("commit"), dict):
            raise CheckError("GitHub returned an invalid commit record.")
        sha = validated_sha(item.get("sha"))
        message = item["commit"].get("message")
        if not isinstance(message, str):
            raise CheckError("GitHub returned an invalid commit title.")
        records.append({"sha": sha, "title": message.splitlines()[0] if message.splitlines() else "(no title)"})
    return records


def _file_records(value) -> list[dict]:
    if not isinstance(value, list):
        raise CheckError("GitHub returned an invalid changed-file list.")
    records = []
    for item in value[:MAX_FILES]:
        if not isinstance(item, dict) or not isinstance(item.get("filename"), str):
            raise CheckError("GitHub returned an invalid changed-file record.")
        previous = item.get("previous_filename")
        status = item.get("status", "unknown")
        if (previous is not None and not isinstance(previous, str)) or not isinstance(status, str):
            raise CheckError("GitHub returned an invalid renamed-file record.")
        records.append({"filename": item["filename"], "previous_filename": previous, "status": status})
    return records


def check_upstream(baseline: Baseline, get_json) -> UpstreamReport:
    # Revalidate programmatic callers as strictly as the baseline file.
    validate_baseline(baseline)
    base = baseline.comparison_commit
    repository = get_json(API_PATH)
    if not isinstance(repository, dict) or repository.get("full_name") != REPOSITORY:
        raise CheckError("GitHub did not return the original Earshot repository.")
    branch = repository.get("default_branch")
    if not isinstance(branch, str) or not branch or len(branch) > 1024:
        raise CheckError("GitHub did not report a valid default branch.")
    # Query encoding keeps an untrusted branch name out of the URL path. Resolve
    # it once; every later page compares the same pair of immutable commit SHAs.
    query = urllib.parse.urlencode({"sha": branch, "per_page": 1})
    head_records = get_json(API_PATH + "/commits?" + query)
    if not isinstance(head_records, list) or len(head_records) != 1 or not isinstance(head_records[0], dict):
        raise CheckError("GitHub did not resolve the upstream default branch.")
    head = validated_sha(head_records[0].get("sha"))
    compare_path = API_PATH + "/compare/" + base + "..." + head
    first = get_json(compare_path + "?per_page=100&page=1")
    if not isinstance(first, dict):
        raise CheckError("GitHub returned an invalid comparison.")
    total = nonnegative_int(first.get("total_commits"))
    ahead = nonnegative_int(first.get("ahead_by"))
    behind = nonnegative_int(first.get("behind_by"))
    merge_record = first.get("merge_base_commit")
    merge_base = validated_sha(merge_record.get("sha")) if isinstance(merge_record, dict) else None
    state = first.get("status")
    if state == "identical":
        if head != base or ahead or behind or total:
            state = "manual-review"
    elif state == "ahead":
        if merge_base != base or not ahead or behind or total != ahead:
            state = "manual-review"
    elif state == "behind":
        if merge_base != head or not behind or ahead:
            state = "manual-review"
    elif state != "diverged":
        state = "manual-review"

    raw_files = first.get("files")
    files = _file_records(raw_files)
    commits = _commit_records(first.get("commits"))
    seen = {item["sha"] for item in commits}
    if len(seen) != len(commits):
        raise CheckError("GitHub returned duplicate commit records.")
    first_page_count = len(commits)
    for page in range(2, MAX_COMMITS // PAGE_SIZE + 1):
        if len(commits) >= total or first_page_count < PAGE_SIZE:
            break
        response = get_json(compare_path + "?per_page=100&page=" + str(page))
        if not isinstance(response, dict) or response.get("status") != first.get("status"):
            raise CheckError("GitHub changed the pinned comparison while paging.")
        records = _commit_records(response.get("commits"))
        for record in records:
            if record["sha"] in seen:
                raise CheckError("GitHub returned duplicate commit records.")
            seen.add(record["sha"])
        commits.extend(records)
        first_page_count = len(records)
    # Short pages can signal an incomplete API response as well as the hard cap.
    capped = total > len(commits)
    if len(commits) > total:
        state = "manual-review"
    return UpstreamReport(baseline, branch, head, merge_base, state, commits, total, capped,
                          files, len(raw_files) >= MAX_FILES, ahead, behind)


def safe_text(value: str, limit: int = 2048) -> str:
    # Remove terminal controls, surrogate codepoints and invisible/bidi format
    # controls, then HTML-escape. Remote Markdown never becomes report markup.
    cleaned = "".join(c for c in value if unicodedata.category(c) not in {"Cc", "Cf", "Cs"})
    if len(cleaned) > limit:
        cleaned = cleaned[:limit] + "… [truncated]"
    return html.escape(cleaned, quote=True)


def classify_file(record: dict) -> list[str]:
    categories = set()
    for path in (record["filename"], record.get("previous_filename")):
        if path is None:
            continue
        lower = path.lower()
        if lower.startswith("protocol/"):
            categories.add("Protocol")
        if lower.startswith("dsp/"):
            categories.add("DSP")
        if lower.startswith("app/"):
            categories.add("Android app")
        if lower.startswith("docs/") or lower.startswith("research/"):
            categories.add("Docs / research")
        name = PurePosixPath(lower).name
        if (name.startswith(("license", "licence", "notice", "copying", "copyright", "third_party_notice")) or
                any(part in {"licenses", "licences"} for part in PurePosixPath(lower).parts)):
            categories.add("Licences / notices")
    return sorted(categories) or ["Other"]


STATUS_MESSAGES = {
    "identical": "Upstream check: identical.",
    "ahead": "Upstream check: updates available; manual review required.",
    "behind": "Upstream check: behind; manual review required.",
    "diverged": "Upstream check: diverged; manual review required.",
    "manual-review": "Upstream check: comparison needs manual review.",
}


def render_report(report: UpstreamReport) -> str:
    baseline_sha = report.baseline.comparison_commit
    lines = ["# Manual Earshot upstream check", "",
             "Original: [Earshot by HellzYeahh and contributors](" + REPOSITORY_URL + "), MIT. "
             "This fork is an experimental AI-assisted native iOS port attempt.", "",
             STATUS_MESSAGES[report.state], "",
             "This check imports, merges and publishes nothing, and never advances the pinned baseline.", "",
             "Retained Android snapshot version:", "<pre><code>" + safe_text(report.baseline.imported_version, 100) + "</code></pre>", "",
             "- Imported Android provenance: [" + report.baseline.imported_commit + "](" + REPOSITORY_URL + "/commit/" + report.baseline.imported_commit + ")",
             "Upstream default branch (resolved once):", "<pre><code>" + safe_text(report.branch, 1024) + "</code></pre>", "",
             "- Pinned baseline: [" + baseline_sha + "](" + REPOSITORY_URL + "/commit/" + baseline_sha + ")",
             "- Resolved upstream head: [" + report.head + "](" + REPOSITORY_URL + "/commit/" + report.head + ")",
             "- Immutable comparison: [review commits and files](" + REPOSITORY_URL + "/compare/" + baseline_sha + "..." + report.head + ")",
             "- Ahead: %d; behind: %d." % (report.ahead_by, report.behind_by), ""]
    if report.baseline.reviewed_commit is not None:
        lines.extend(["The comparison starts at the separately reviewed native-port boundary. The retained Android snapshot and its original version are unchanged.", "",
                      "Reviewed upstream version:", "<pre><code>" + safe_text(report.baseline.reviewed_version, 100) + "</code></pre>", ""])
        if report.baseline.review_audit is not None:
            lines.extend(["Review audit reference:", "<pre><code>" + safe_text(report.baseline.review_audit) + "</code></pre>", ""])
    if report.merge_base:
        lines.extend(["- Reported merge base: [" + report.merge_base + "](" + REPOSITORY_URL + "/commit/" + report.merge_base + ")", ""])
    if report.state == "ahead":
        lines.extend(["The API reports the pinned baseline as the merge base. Review the changes manually for the native port; this is not a compatibility or safety assessment.", ""])
    elif report.state in {"behind", "diverged", "manual-review"}:
        lines.extend(["History needs manual review. Do not automatically import changes or replace the baseline.", ""])
    lines.extend(["## Commits", "", "Reported comparison count: %d. Listed: %d." % (report.total_commits, len(report.commits)), ""])
    if report.commits_capped:
        lines.extend(["**INCOMPLETE:** the reported commit list was truncated or capped. At most 500 commits are fetched, in pages of 100.", ""])
    if report.commits:
        lines.append("<ul>")
        for commit in report.commits:
            lines.append('<li><a href="' + REPOSITORY_URL + "/commit/" + commit["sha"] + '">' + commit["sha"][:12] + "</a> <code>" + safe_text(commit["title"], 300) + "</code></li>")
        lines.extend(["</ul>", ""])
    else:
        lines.extend(["No commits were returned for this comparison direction.", ""])
    lines.extend(["## Changed files", "", "Only the first comparison page supplies changed files; GitHub caps that list at 300. "
                  "Classification considers both the current and previous path of a rename.", ""])
    if report.files_capped:
        lines.extend(["**POSSIBLY INCOMPLETE:** 300 or more files were returned. The changed-file list may omit further changes; inspect the immutable comparison manually.", ""])
    if report.files:
        lines.extend(["<table>", "<thead><tr><th>Area</th><th>Change</th><th>Path</th></tr></thead>", "<tbody>"])
        for record in report.files:
            paths = safe_text(record["filename"])
            if record.get("previous_filename") is not None:
                paths = safe_text(record["previous_filename"]) + " → " + paths
            lines.append("<tr><td>" + ", ".join(classify_file(record)) + "</td><td><code>" + safe_text(record["status"], 80) + "</code></td><td><code>" + paths + "</code></td></tr>")
        lines.extend(["</tbody>", "</table>", ""])
    else:
        lines.extend(["No changed files were returned on the first comparison page.", ""])
    lines.extend(["## Limits and follow-up", "",
                  "- This is a manual, read-only GitHub REST check; it does not run on a schedule.",
                  "- Only the reported default branch is inspected, rather than every tag or branch.",
                  "- Commit titles and paths are untrusted source data, bounded and escaped in this report. Remote HTML and URLs are never used as links.",
                  "- File classification is a review aid, not proof of complete Android/iOS parity. Simulator tests do not verify headphone hardware.",
                  "- Protocol, DSP, Android app, research and licence changes need human review before any separately authorized native-port work.",
                  "- Preserve HellzYeahh and contributors’ authorship, the MIT licence and inherited research notices.", ""])
    return "\n".join(lines)


class SafeArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        self.exit(2, "Upstream check failed: use --output PATH.\n")


def main(argv=None, *, get_json=None, baseline_path: Path | None = None) -> int:
    parser = SafeArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="Markdown report path (prefer ignored test results or a temporary directory)")
    args = parser.parse_args(argv)
    baseline_path = BASELINE_PATH if baseline_path is None else baseline_path
    try:
        if args.output.resolve() == baseline_path.resolve():
            raise CheckError("The report must not overwrite the pinned baseline.")
        baseline = load_baseline(baseline_path)
        report = check_upstream(baseline, get_json if get_json is not None else GitHubGET(os.environ.get("GH_TOKEN")))
        try:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(render_report(report), encoding="utf-8")
        except OSError:
            raise CheckError("The Markdown report could not be written.") from None
        print(STATUS_MESSAGES[report.state])
        return 0
    except CheckError as error:
        print("Upstream check failed: " + str(error), file=sys.stderr)
        return 2
    except Exception:
        # Do not let a traceback expose headers, environment values or API text.
        print("Upstream check failed: unexpected local or API data error.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
