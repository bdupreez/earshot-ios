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

## What the report means

The imported baseline is pinned in [upstream-baseline.json](upstream-baseline.json), initially
upstream 0.4.0 at `d6ceffa7a028f2809840160bf8323715d24384cb`. The checker resolves upstream's
default branch to one immutable commit, then compares that commit with this imported baseline.
Comparing upstream directly with the iOS branch would confuse intentional port changes with
new upstream work.

- Identical history means there are no newer changes relative to the imported snapshot.
- Ahead history identifies newer upstream commits for review.
- Behind, diverged or unexpected ancestry needs manual history review; it is not reported as current.
- API failures fail the check and do not establish that upstream is unchanged.

Commit listings are paginated and bounded to 500 entries. GitHub's comparison API supplies at
most 300 changed files on the first page; a report at that limit may omit files. Both old and new
paths are considered for renames. Area summaries therefore help triage, but cannot prove that
an omitted subsystem is unchanged. The report labels limits and links to the fixed comparison.
Remote subjects, paths and branch text are treated as untrusted data and escaped before display.

The check does not advance the baseline, import code, synchronize a branch, open an issue/PR,
or execute on a schedule. Running it repeatedly reports changes since the last deliberate import.

## Porting an update deliberately

Review the reported commit range, licensing changes and the retained Android implementation.
Protocol, model and DSP changes may need a native Swift adaptation; Android Bluetooth/background
features do not automatically become possible on iOS. Keep original authorship and research
credits. Port selected work on a `codex/` branch, run appropriate native tests and preserve actual
Xcode evidence. Physical headphone effects still need a device test.

Advance the imported baseline only after its entire range has been deliberately incorporated or
explicitly reconciled and documented. Selectively porting one fix is not enough to claim that all
upstream commits have been imported. Update the provenance notes alongside any baseline change.
Publish progress only to this fork after the index privacy check; preserve local signing edits.

Reference: [GitHub's comparison API and pagination limits](https://docs.github.com/en/rest/commits/commits#compare-two-commits).
