# Main-study method freeze

The user selected the 26 instances from `SWT-bench x mini-swe.pdf` pages 31-32
on November 16, 2026: 13 historically Easy and 13 historically Hard instances.
These labels describe the lecture's historical results, not observed outcomes
of this study. The selection is `configs/instances.json`; generation-only inputs
and checksums are in `inputs/study-26/`. All 26 are included in each denominator.
The already explored `django__django-16485` development example is excluded.

Dataset: `princeton-nlp/SWE-bench_Verified`, pinned revision
`c104f840cc67f8b6eec6f759ebc8b2693d585d4a`. This is our existing pinned snapshot;
it has not been independently confirmed as the instructor's assigned revision.
The local Parquet SHA-256 is checked against the original download manifest.

## Comparison

- Same DeepSeek-Flash alias, non-thinking mode, temperature 0, 4,096 maximum
  output tokens, no retries, same generator prompt and framework checkout.
- Per-method/instance total: 30 attempted model steps, $1 conservative estimated
  token cost, 600 seconds from immediately before generation. Setup and official
  evaluation are timed separately. Timeouts shrink to remaining phase time;
  request costs are estimated before sending and charged from returned usage.
- Baseline spends its allowance in one generator conversation.
- Experimental generation receives at most 20 calls/$0.60/360 seconds. A fresh
  reviewer conversation uses the remaining shared allowance and may iterate up
  to three completed/submitted rounds. It retains its own history across rounds.
- Both receive a submission reminder when at most two phase calls remain.
- Stop at supported alignment, unresolvable uncertainty, resource limit, invalid
  revision, or round limit. Malformed review records consume rounds.
- Save all checkpoints. Select the latest structurally usable test patch;
  fall back to the earlier usable patch if a revision is invalid. No hidden
  evaluation outcome is used in selection. A valid review record is not required
  to preserve a structurally usable candidate after resource exhaustion; record
  this circumstance as a limitation in review-completion analysis.
- Buggy checkout only; Git history removed. No network or host mounts. Production
  files root-owned/read-only; agent commands use unprivileged user `nobody`.
  Existing buggy tests and documentation are allowed. Test roots are configured
  or discovered deterministically from tracked tests/testing directories.
- Oracle review is the sole deliberate workflow intervention. No mutation
  testing, mandatory simplification, or mandatory behavior separation.

## Execution and accounting

Sequential paired runs interleave Easy/Hard and alternate method order by pair.
One generation run per method/instance, with no outcome-based regeneration.
Each child saves code, prompts, resolved config, dependencies, environment
metadata, candidate patches, trajectories, and costs. The batch checks original
source and input hashes before each generation job.

The batch has an $8 conservative estimated spending ceiling, reserving room for
both $1 method caps before starting each pair. Unstarted jobs remain recorded.
The provider preflight reported $9.98 remaining USD credit and `deepseek-flash`
available. This ceiling does not guarantee completion of all jobs or equal
realized cost. Any stopped/unstarted cases remain in the assigned denominator.
The ledger uses conservative peak uncached token accounting, not invoice costs.

Evaluate frozen predictions with the unchanged official SWT-Bench harness in
unit-test mode, coverage enabled. Report per-instance applicability, `resolved`,
`coverage_delta_pred` (fraction), generation cost/time, evaluation time, and paired
outcome categories. Coverage availability must be reported separately; N/A is
not zero. Infrastructure failures and unchanged-prediction retries are separate
from generation failures. Do not discard failed or missing predictions.

Single-run variability, mutable model alias, convention-based path restrictions,
small selected sample, different historical evaluation protocols, and the
absence of an ablation are limitations. Historical lecture scores and the earlier
development baseline are not matched main-study comparators.
