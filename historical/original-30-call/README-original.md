# Oracle Review Study

SE 433 final project: evaluate whether evidence-grounded oracle review improves
bug-reproducing unit tests generated with mini-swe-agent and DeepSeek.

## Study design

- Baseline: generate a test patch, freeze it, then evaluate it.
- Experimental method: generate a candidate, review it in a fresh conversation
  using the same model, optionally revise it, freeze it, then evaluate it.
- Use the official SWT-Bench evaluator in unit-test mode.
- Keep reference fixes, golden tests, and evaluator artifacts out of generation
  and review. Existing tests in the buggy checkout are allowed.
- Prioritize oracle correctness. Mutation testing is excluded. Simplification,
  behavior separation, and ablation are optional future extensions.

Provisional per-method, per-instance limits are 30 model calls, 600 seconds, and
$1. The experimental generator is limited to 20 calls, 360 seconds, and $0.60;
review uses the remaining shared allowance, with at most three review rounds.
These settings must be checked in a pilot and frozen before the main study.
The instance set and dataset revision still require confirmation.

## Repository layout

| Directory | Purpose |
| --- | --- |
| `configs/` | Model, budget, dataset, and environment configuration |
| `prompts/` | Versioned generator and reviewer instructions |
| `scripts/` | Generation/review controller, evaluation launchers, and analysis |
| `tests/` | Checks for controller behavior and artifact handling |
| `results/` | Small, curated summaries and reproducibility manifests |

This repository contains the reviewer prompt, candidate capture, shared budget
ledger, workflow controller, and a mini-swe-agent session adapter. The controller
supports baseline and review paths, round checkpoints, structured review records,
and fallback to an earlier structurally usable patch. `scripts/run_study.py`
provides the Docker/API launcher. Request and command timeouts are clamped to
remaining phase time. Requests are refused when a conservative payload/output
cost estimate exceeds the remaining allowance. Estimates are not invoice
guarantees: provider pricing/tokenization can differ, and termination overhead
can exceed the nominal deadline. Actual recorded usage is not clipped.

Cost accounting currently carries forward the pilot's $0.30/million input and
$1.20/million output assumptions. Verify current model availability and provider
pricing before a paid pilot. The integrated launcher has not yet been tested
with a real model and Docker. These local tests establish control-flow behavior,
not experimental effectiveness.

Run the local, unpaid checks with `python3 -B -m unittest discover -s tests -v`.
To include the real framework adapter check using existing dependencies, use
`../baseline-pilot/.venv/bin/python -B -m unittest discover -s tests -v`.

## Development pilot command

From this repository, the following launches a paid generation/review run using
the previously explored Django example. It is a development example, not an
unseen evaluation instance. Do not launch before checking pricing and the Docker
image contents for reference artifacts. Credentials remain on the host.

```bash
../baseline-pilot/.venv/bin/python -B scripts/run_study.py \
  --method oracle_review \
  --instance ../baseline-pilot/instance.json \
  --image docker.io/swebench/sweb.eval.x86_64.django_1776_django-16485:latest \
  --key-file ../baseline-pilot/.env
```

Use `--method baseline` for a new baseline run under this launcher's identical
generation prompt and runtime guards. The earlier pilot is historical setup
evidence, not an exactly matched baseline for this new runner. Only Django's
test roots are configured so far; other repositories require inspection first.
Official evaluation remains a separate step after predictions are frozen.

The launcher checks the Docker engine before setting up the experiment. On macOS
it opens Docker Desktop automatically if needed and waits up to 120 seconds for
a successful Docker API query. Startup/setup are outside the generation budget.
Use `--no-start-docker` to disable opening the app, or
`--docker-startup-timeout 180` to change the startup wait. Missing Docker or failed
startup stops the launcher before any model request.

## Checkout write isolation

After preparing the buggy snapshot, the launcher protects production files and
runs agent commands as Linux user `nobody`. Only configured test directories and
Git metadata are writable in the checkout. The installed Python environment is
preserved, the container network is disabled, and host directories are not
mounted. This prevents direct writes to production files, including temporary
edits restored before final diff capture. It does not prove absence of model
memorization or prevent writing alternate code under `/tmp`.

An opt-in offline smoke test verifies denied production writes, permitted test
creation, and execution of the existing Django test module:

```bash
../baseline-pilot/.venv/bin/python -B tests/smoke_docker_isolation.py
```

The first live development run exposed a temporary production edit and an
unfinished review record. Its original artifacts are preserved and its summary
is marked `development_only_production_edit_violation`; exclude it from the main
study. Isolation and a two-call submission reminder were added in response.

## Evaluate a frozen development prediction

Use the existing evaluator virtual environment, separate from generation:

```bash
../baseline-pilot/evaluation/.venv/bin/python -B scripts/evaluate_run.py \
  --run runs/20261116T052358279326Z-oracle_review
```

The default reference input is the earlier pinned Django evaluator-only snapshot.
The launcher checks dataset revision, instance ID, base commit, and prediction
consistency before copying evaluation inputs into a separate directory. Other
instances require an appropriate `--references` file and `--reference-manifest`.
It invokes the unchanged harness in unit-test mode with coverage enabled and
removes API-key variables from the evaluator subprocess. It never updates the
generation patch or feeds evaluation results back to the agent. Each invocation
uses a new output directory; retries must retain the identical frozen prediction
and be recorded explicitly rather than overwriting prior attempts.

## Prepare the paired study

`configs/proposed-instances.json` records the slides' 13 Easy and 13 Hard IDs.
Its status is proposed: neither this set nor our existing pinned snapshot revision
has been independently confirmed as the instructor's assigned set/revision.
Resolve that before launching the main study.

`scripts/prepare_study.py` validates the local benchmark snapshot checksum and
dataset revision, then reads only generation-facing Parquet columns. It writes
task JSON files and a manifest with input hashes, strata, and image names.
`scripts/run_batch.py --manifest PATH` prints a free plan by default. Executing
requires both `--execute` and `--confirm-selected-set`. It interleaves Easy/Hard
instances, alternates which method runs first, and preserves all assigned jobs
in its ledger even if unstarted or unsuccessful. Generation and evaluation are
separate; the batch does not run evaluation automatically.

The default conservative estimated study spending limit is $8. Before starting
a pair, it reserves room for two whole per-run caps. Unstarted cases stay in the
denominator; do not silently reduce the selected set afterward. Unknown usage
after a missing run summary stops the batch rather than assuming zero spending.
Image pulls have a ten-minute timeout. No automatic resume or regeneration is
implemented; interrupted jobs require explicit inspection of preserved artifacts.

For unconfigured repositories, the launcher can inspect tracked buggy-snapshot
paths and permit only directories named `tests` or `testing`, including nested
ones. It records the resulting roots in the run config before isolation. This
is a deterministic convention-based policy, not proof that every file in those
directories is a test; unsupported layouts stop and require inspection.
The earlier baseline scripts and pilot
records remain in `../baseline-pilot/`; no files have been migrated yet.

## Existing repositories

Use the existing mini-swe-agent checkout at `../mini-swe-agent/` without modifying
it. Keep evaluator source checkouts separate as well. Record their exact commits
in experiment manifests rather than copying their source into this repository.

## Secrets and run artifacts

Never commit API keys or populated environment files. Keep credentials outside
the repository or supply them through the process environment. `.gitignore`
excludes local environments, raw run outputs, caches, and evaluator-only data.
Review curated artifacts before committing them: ignore rules alone cannot
prevent secrets from being embedded in logs or other files.

## Next steps

1. Walk through the existing baseline runner together.
2. Finalize and version the reviewer prompt and controller rules.
3. Bring over the necessary supporting code with its provenance recorded.
4. Implement bounded review and artifact recording.
5. Validate the pipeline on development examples before the main study.
