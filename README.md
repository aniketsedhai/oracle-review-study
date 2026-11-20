# OracleCheck: bug-reproducing test generation

SE 433 final project by Aniket Sedhai. This project compares three changes to
mini-swe-agent test generation against a common DeepSeek-Flash baseline.

The code in `scripts/` is the simplified, shared implementation prepared on
November 20. The reported experiments ran on November 16 using the preserved
versions listed below. Simplification does not replace those measurements or
change their saved predictions.

## Start here

Read these files in order:

1. [methods.py](scripts/methods.py): which prompt and review options each method uses.
2. [study.json](configs/study.json): model and resource limits.
3. [controller.py](scripts/controller.py): generate, capture, optionally review, and save.
4. [agent_session.py](scripts/agent_session.py): drive the existing mini-swe-agent conversation.
5. [review.py](scripts/review.py): parse decisions and verify claimed edits.
6. [patches.py](scripts/patches.py): capture and check the actual test-file changes.

[run_study.py](scripts/run_study.py) connects these pieces to Docker and the API.
You can understand the experiment before reading every setup and logging detail.

## Methods

| CLI method | Before writing tests | After generation |
| --- | --- | --- |
| `baseline` | Normal generator prompt | Save the patch |
| `oracle_review` | Same generator prompt | Fresh reviewer can keep or revise |
| `verified_review` | Same generator prompt | Review plus edit-claim and execution checks |
| `evidence_first` | Explicit trigger, supported expectation, observation, failure relevance | Save the patch; no separate reviewer |

All methods can inspect buggy code, documentation and existing tests, execute
commands, and revise tests. A fresh reviewer has no generator conversation
history; later rounds retain reviewer history. None receives a reference fix,
reference tests, internet access, or evaluator feedback during generation.

One patch may contain multiple test functions. A structurally usable patch is
not a guarantee that its assertions are correct.

## Results

The selected lecture-slide set contains 13 Easy and 13 Hard instances; see
[instances.json](configs/instances.json). The labels are historical lecture
categories, not difficulty classifications established by this experiment.

| Method | 30-call total cap | 40-call total cap |
| --- | --- | --- |
| Baseline | 13/26 | 10/26 |
| Oracle review | 12/26 | Not run |
| Review with edit verification | 13/26 | 12/26 |
| Evidence-first | 13/26 | Not run |

These are official SWT-Bench `resolved` counts, with all 26 in every denominator.
They do not mean every function in a successful patch was valid: inspected cases
include errored tests classified as unmatched. No tested configuration exceeded
13/26. Follow-ups were exploratory, designed after inspecting earlier results;
there was one generation per method/instance at each budget, not repeated trials.

Curated results are in [results/](results/), including the
[four-method comparison](results/four-method-comparison.json) and
[40-call comparison](results/call-budget-40-comparison.json).

## Limits and stopping

At 30 calls, each method/instance shares 600 seconds and a $1 estimated-cost cap.
Review generation receives at most 20 calls, 360 seconds and $0.60; review uses
whatever remains. At 40 calls, generation receives at most 25 calls for review
methods. See [study-40-calls.json](configs/study-40-calls.json).

Stop at submission, a resource limit, invalid revision, or at most three review
attempts. The reviewer can stop as aligned or uncertain. A false edit claim
requires correction in verified review, within the same remaining budget.

At a limit, capture the files and retain the latest structurally usable candidate.
Fall back to a previous usable candidate if a revision is invalid. An unfinished
but structurally usable test can therefore reach evaluation. If there is no
usable candidate, write an empty prediction and count the instance unsuccessful.

Cost accounting uses $0.30/million input tokens and $1.20/million output tokens,
without cache discounts. These are conservative estimates, not actual bills.
Batch ceilings reserve full per-run caps before starting an instance group and
can stop the batch early; unstarted instances remain in its ledger.

## Running locally

Generation and evaluation need separate environments, Docker, a DeepSeek key,
and pinned external checkouts. On the project laptop, generation dependencies
are already in `../baseline-pilot/.venv/`; evaluation dependencies are in
`../baseline-pilot/evaluation/.venv/`. The Python below refers to that existing
installation. No command in this section starts a paid run unless explicitly
marked.

For a fresh installation, use Python 3.12 and install the recorded dependencies
in separate virtual environments:

```bash
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements-generation.txt
python3.12 -m venv ../baseline-pilot/evaluation/.venv
../baseline-pilot/evaluation/.venv/bin/python -m pip install -r requirements-evaluation.txt
```

Use `.venv/bin/python` for generation instead of the laptop-specific
`../baseline-pilot/.venv/bin/python` in the examples below. Install Docker Desktop
and place the exact upstream mini-swe-agent checkout at `../mini-swe-agent/`
and the harness at `../baseline-pilot/evaluation/harness/`. The separate evidence
archive already contains their recorded source snapshots and licenses in those
locations. If cloning instead, use the upstream repositories and commits listed
in the reproducibility section. The launchers check Git commit/status, so initialize
an extracted source snapshot as a clean repository or use the actual pinned Git
checkout; no model behavior depends on a newly initialized source commit.

Download the pinned evaluator snapshot using the URL and SHA-256 recorded in
`configs/dataset-snapshot.json`, placing the Parquet and manifest in
`../baseline-pilot/evaluation/`. These are evaluator-only inputs. Prepared
`inputs/study-26/` files already omit reference fixes/tests.

Run unpaid tests:

```bash
../baseline-pilot/.venv/bin/python -B -m unittest discover -s tests -v
```

Inspect the single-instance interface:

```bash
python3 -B scripts/run_study.py --help
```

Plan all four methods without Docker/API execution:

```bash
python3 -B scripts/run_batch.py --manifest inputs/study-26/manifest.json \
  --methods baseline oracle_review verified_review evidence_first
```

A new single-instance run **makes paid API calls**:

```bash
../baseline-pilot/.venv/bin/python -B scripts/run_study.py \
  --method verified_review \
  --instance inputs/study-26/pydata__xarray-3677.json \
  --image docker.io/swebench/sweb.eval.x86_64.pydata_1776_xarray-3677:latest \
  --framework ../mini-swe-agent --discover-test-roots \
  --key-file ../baseline-pilot/.env
```

Use `--config configs/study-40-calls.json` for the larger allowance.
The key stays on the host; it is not mounted in Docker or written to run metadata.
For a batch, `run_batch.py` additionally requires `--execute`,
`--confirm-selected-set` and a key. Its default estimated batch ceiling is $8.

Official unit-test evaluation is separate. `evaluate_run.py` grades one frozen
run; `follow_evaluation.py` follows a batch and prepares evaluator-only references.
The latter expects the pinned Parquet snapshot and its manifest in
`../baseline-pilot/evaluation/`. Existing records are not overwritten. Neither
program repairs predictions or sends evaluator results back to the model.

## Reproducibility and historical code

- mini-swe-agent 2.4.6: `04d809ceab9df28f9adaed044884180159172930`.
- SWT-Bench harness: `be12d4c8e7a5315a6bd60b0cad72736e96a4af3e`.
- SWE-bench Verified revision: `c104f840cc67f8b6eec6f759ebc8b2693d585d4a`.
- This was the user-selected slide set and pinned local revision, not a separately
  confirmed instructor-assigned revision.

Use external source checkouts without modifying them. Each historical run saved
its own source, prompts, resolved config, dependency lock, candidate checkpoints,
trajectory and environment metadata. See [the historical index](historical/README.md)
for the exact code used by each experiment.

## Folder map

| Folder | Purpose |
| --- | --- |
| `scripts/`, `prompts/`, `configs/` | One maintained implementation for all methods |
| `tests/` | Unpaid behavioral checks, including comparison with frozen controllers |
| `inputs/study-26/` | Generation-only issue inputs and checksums |
| `results/` | Small result summaries and provenance |
| `runs/`, `evaluation/` | Local experiment evidence; raw work is excluded from normal Git tracking |
| `historical/`, `compatibility/`, `follow-up/` | Preserved experiment source; not additional active implementations to study |

`check_provider.py`, `prepare_study.py`, `docker_startup.py`, `test_layout.py`,
`isolation.py` and `runtime.py` are setup and runtime-protection utilities,
not additional research methods. The obsolete batch-recovery script is preserved
only with the historical source; it is not part of the shared runner.

## Supporting material outside this repository

Report sources, slides, rehearsal notes, personal code walkthroughs and
maintenance records are stored in `../oracle-review-study-support/`. They are
not dependencies of the project runner.

## Source provenance

The Python files in `scripts/`, `analysis/` and `tests/` are project-specific
supporting code, primarily authored with Codex assistance and reviewed with
Aniket. Historical folders preserve earlier versions of that supporting code.

| Project file | Reused component or role |
| --- | --- |
| `agent_session.py` | Calls upstream mini-swe-agent `DefaultAgent` |
| `runtime.py` | Extends upstream `LitellmModel`; adds phase guards |
| `run_study.py` | Uses upstream `DockerEnvironment`; adds study setup |
| `evaluate_run.py` | Invokes the unchanged SWT-Bench evaluator |
| `controller.py`, `review.py`, `methods.py` | Our review orchestration and edit verification |
| `patches.py`, `budget.py` | Our patch checks and shared-budget ledger |
| Other scripts | Our batch, preparation, startup, isolation and discovery utilities |
| Prompts and study configs | Our method instructions and settings |
| Generation inputs | SWE-bench issue data, not issue descriptions authored by us |
| Prediction patches and review records | DeepSeek-generated outputs |
| Official reports and pre/post logs | SWT-Bench execution evidence |

External agent/evaluator source belongs to its upstream contributors and is
included with licenses in the separate artifact archive. Python libraries,
LiteLLM, Docker, Git, and project test frameworks are dependencies, not our
original implementations.

## Contributions and disclosure

Aniket selected the scope and instance set and reviewed the prompts and main
code. Codex assisted workflow design, implementation, experiment operation,
analysis, documentation and writing. DeepSeek generated tests and review records.
The implementation was simplified after the experiments for reviewability.

Never commit populated environment files, API keys, virtual environments or
unreviewed raw logs. Final source/artifact packaging and repository publication
are separate from running or simplifying the workflow.

## Exporting final results

After unpacking the evidence archive beside this source tree, run
`python3 -B analysis/export_all.py`. It checks selected prediction hashes and
rebuilds the complete six-configuration CSV and JSON in `results/final/`.
Original official reports are not rewritten; environment-blocked annotations
supplement their scores.

The final report and Overleaf source are submitted separately. Trajectories/logs
are distributed in the accompanying evidence archive rather than normal Git
tracking. That archive includes all 156 reported runs and evaluation evidence.
