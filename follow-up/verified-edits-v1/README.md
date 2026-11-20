# Verified edits: post-hoc development follow-up

This version was designed after inspecting the completed 26-instance study.
It does not replace or change the frozen baseline (13/26) and original review
workflow (12/26). No new benchmark effectiveness result is claimed.

## Change

The reviewer supplies a boolean `patch_changed`, its decision, and an exact
`validation_command` when a candidate needs validation. The controller:

1. Compares the patch before and after each review round.
2. Rejects a `revise` claim with no actual change, or a changed flag that disagrees
   with the saved patch. It asks for correction within the same round/call/cost/
   time limits. Honest `keep` and `uncertain` decisions do not require edits.
3. After an edit, executes the supplied test command with pipefail and a timeout
   bounded by remaining time, recording command, output, and return code.
4. Checks that validation did not modify the patch. If it did, it falls back to
   the previous usable candidate and records that reason.
5. Saves all attempts, including unverified claims and resource-limit stops.

Failure on buggy code is acceptable. These checks establish observed edits and
command execution, not oracle correctness or successful reproduction. A cosmetic
edit can satisfy a difference check; natural-language claims can still be wrong.
The reviewer must not make cosmetic edits just to satisfy the guard. Its supplied
validation command also requires inspection for issue relevance.

The prediction label is `oracle_review_verified_edits_v1`, and summaries identify
the run as `post_hoc_development_follow_up`. The model, generator prompt, and
resource limits are unchanged. This copy includes the documented Requests
root-level-test compatibility support. Existing repositories and main-study
predictions are untouched.

## Verification so far

All 39 local checks pass, including the framework adapter checks. New cases cover
false claims, correction followed by a real edit, actual test execution with
expected buggy-code failure, unchanged keep decisions, budget exhaustion, and
validation-side file mutation. An offline replay of the archived xarray record
detects `claimed_revision_without_patch_change`; see
`results/archived-record-check.json`.

These are software checks and an archived-record replay, not a new LLM benchmark
run. No additional model spending occurred while implementing this version.

From this directory, run local checks with:

```bash
../../../baseline-pilot/.venv/bin/python -B -m unittest discover -s tests -q
```

Before a live development run, provide `--framework` pointing to the unchanged
`Final_Project/mini-swe-agent` checkout and a generation-only instance file. The
copied launcher's default sibling-framework path is inappropriate for this nested
directory. Keep output separate from the original study, and never provide the
reference fix, evaluator logs, or golden tests to generation/review.

Any pilot on already inspected failures is a development check. A subsequent
26-instance comparison must be separately labeled as post-hoc and must include
all original instances, not only cases the original method failed.
