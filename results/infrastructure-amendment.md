# Requests test-layout recovery

The main batch stopped after 24 completed generation jobs when the Requests
baseline setup could not discover a directory named `tests` or `testing`.
The frozen buggy checkout instead contains an executable root-level
`test_requests.py`. The traceback occurs before agent construction/generation;
no trajectory exists, and the failed setup attempt used zero model calls.

The failed attempt and original batch ledger are preserved. Neither completed
predictions nor their evaluation outcomes were changed or used for selection.

## Narrow compatibility version

`compatibility/root-test-files-v2/` is a copy of the runner with changes only to:

1. Discover root-level `test_*.py` files as permitted test paths.
2. Permit an exact configured Python test-file path in candidate checks, including
   an existing executable root-level test file.
3. Make that specific test file writable by the unprivileged user, while keeping
   the checkout parent and production files read-only.

The complete source diff is `compatibility/root-test-files-v2/change.diff`.
No model, prompt, budget, stopping rule, or oracle-review procedure changed.
Both Requests methods use this version; all other unfinished jobs use the
original frozen sources. Version/source hashes are recorded per run and in the
batch's infrastructure amendment. The original frozen source files stay intact.

An offline Docker smoke check verified Requests imports, denied production
writes, permitted edits to the existing root-level test, candidate capture, and
clean-base patch application. The first smoke check additionally identified its
executable Git mode; the final compatibility version handles that exact case.

`scripts/resume_batch.py` verifies the known zero-call setup failure, archives the
pre-recovery ledger, retries that setup in a new artifact directory, skips all
completed jobs, and resumes under the original $8 conservative estimated limit.
The evaluation recovery watcher waits for the existing watcher to exit before
adopting its ledger; it does not duplicate completed evaluations or regenerate
predictions. All 26 instances remain in both denominators.

This is a documented infrastructure amendment after method freeze. Report the
version difference and its narrow scope as a reproducibility limitation.
