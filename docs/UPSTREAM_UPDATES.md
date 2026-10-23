# Checking the original Earshot for updates

This is the **AI-assisted native iOS port attempt** of [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot),
MIT. Preserve [the original licence](../LICENSE), [full credits](../THIRD_PARTY_NOTICES.md),
the Android source and protocol research when reviewing or adapting future upstream work.

## Branches and scope

On 23 October 2026, the fork's default branch was changed to `codex/native-ios-port`.
GitHub's default branch controls the landing page, fresh clones and default pull-request base.
The fork's `main` remains the original Android 0.4.0 snapshot. The original repository's default
branch remains `main`; its settings and branches are independent of this fork.

No upstream remote or upstream push destination is needed. The only configured remote is the
owner's fork. Keep pushes explicitly limited to that fork and run the privacy guard first.
Personal Xcode signing settings and keys stay local.

Use the checker for this port rather than GitHub's **Sync fork** action on the iOS default branch.
That action integrates upstream Git history; the native port needs deliberate review and Swift
adaptation. Checking for updates and importing them are separate operations here.

## Run a check

On GitHub, open [Check upstream updates](https://github.com/bdupreez/earshot-ios/actions/workflows/check-upstream-updates.yml)
under Actions, select **Run workflow**, use the iOS branch and inspect the completed run's Summary.
The workflow is manual, restricted to this fork, and has `contents: read` permission. It uses
GitHub's temporary built-in token, without a personal token, developer-account secret or signing
key. Checkout does not persist credentials. Upstream code is never checked out or executed.

Locally, from this repository:

```sh
python3 ios/scripts/check-upstream-updates.py --output ios/TestResults/upstream-update-check.md
```

Python 3 and network access are required. Public API reads work without authentication, subject
to GitHub's public rate limit. An existing `GH_TOKEN` environment variable can authenticate the
GET requests; the checker never writes that value into the report. The local output path is
ignored by Git. Open the Markdown report to inspect commits, changed areas and comparison links.

The first hosted [verification run](https://github.com/bdupreez/earshot-ios/actions/runs/39867056544)
passed on 23 October 2026: 18 regression tests, the live upstream check and summary publication.
The same checker also passed locally. Its initial live comparison found 42 newer commits, with
300 changed files returned and possible file-list truncation explicitly flagged. This is a dated
observation; run the check again for current information.

The complete 42-commit range was deliberately reconciled and simulator-tested in the
[0.75 native audit](IOS_UPSTREAM_075_AUDIT.md). The reviewed boundary now records 0.75.0 at
`9e6c4912531ec6e159eded862d1b6ffa55094199`, while the retained Android import remains 0.4.0.
The actual [23 October local report](UPSTREAM_075_CHECK.md) resolved that same upstream tip:
**identical, zero ahead/behind**. Future checks start after this reviewed range. The expanded
workflow runs all checker and project/privacy regressions. Actual fork-hosted
[run 39892166974](https://github.com/bdupreez/earshot-ios/actions/runs/39892166974) at
`5ad2e373943555c9f2c203a858d3d9fac78795b8` passed: 36 Python cases passed, two macOS project-parser
cases were skipped on Ubuntu (both passed locally on macOS), and the live reviewed comparison
returned **identical**. Summary publication also succeeded. This verifies the new reviewed
boundary independently of the historical 18-test run above.

## What the report means

The imported baseline is pinned in [upstream-baseline.json](upstream-baseline.json), initially
upstream 0.4.0 at `d6ceffa7a028f2809840160bf8323715d24384cb`. The checker resolves upstream's
default branch to one immutable commit, then compares that commit with a separately reviewed
boundary when one is present, falling back to the imported baseline for older files.
Comparing upstream directly with the iOS branch would confuse intentional port changes with
new upstream work.

- Identical history means there are no newer changes relative to the selected comparison boundary.
- Ahead history identifies newer upstream commits for review.
- Behind, diverged or unexpected ancestry needs manual history review; it is not reported as current.
- API failures fail the check and do not establish that upstream is unchanged.

Commit listings are paginated and bounded to 500 entries. GitHub's comparison API supplies at
most 300 changed files on the first page; a report at that limit may omit files. Both old and new
paths are considered for renames. Area summaries therefore help triage, but cannot prove that
an omitted subsystem is unchanged. The report labels limits and links to the fixed comparison.
Remote subjects, paths and branch text are treated as untrusted data and escaped before display.

The check does not advance the baseline, import code, synchronize a branch, open an issue/PR,
or execute on a schedule. Running it repeatedly reports changes since the last deliberate review
boundary (or import when there is no separate review boundary).

## Porting an update deliberately

Review the reported commit range, licensing changes and the retained Android implementation.
Protocol, model and DSP changes may need a native Swift adaptation; Android Bluetooth/background
features do not automatically become possible on iOS. Keep original authorship and research
credits. Port selected work on a `codex/` branch, run appropriate native tests and preserve actual
Xcode evidence. Physical headphone effects still need a device test.

Keep `imported_commit` and `imported_version` as provenance for the retained Android tree. A native
port can finish reviewing a newer upstream range without replacing that historical snapshot.
After the entire range has been deliberately ported or reconciled, validated and documented, add
`reviewed_commit` (a complete lowercase 40-character SHA) and `reviewed_version` to
`upstream-baseline.json`. An optional `review_audit` string records the audit document or review
reference; it is bounded and escaped in the report, never executed or used as a remote link.
The checker compares from `reviewed_commit` when present, while displaying both boundaries.
Review metadata without a valid reviewed SHA and version is rejected. Existing three-field
baseline files continue to compare from their imported snapshot.

Do not set the reviewed boundary just because a check ran, or after porting only one selected fix.
The checker never writes either boundary. The completed, validated review must explicitly advance
it; preserve 0.4.0 and its imported SHA unless the retained Android snapshot itself changes.
Publish progress only to this fork after the index privacy check; preserve local signing edits.

Reference: [GitHub's comparison API and pagination limits](https://docs.github.com/en/rest/commits/commits#compare-two-commits).
