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

This repository currently contains the project scaffold only. The review
controller has not been implemented. The earlier baseline scripts and pilot
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
