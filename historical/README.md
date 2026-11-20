# Historical experiment source

The current `scripts/` directory was consolidated on November 20, after the
reported runs. The results remain tied to the following preserved source.
Nothing here should be edited to make an old result look like a new run.

| Experiment | Source/config location | Generation batch |
| --- | --- | --- |
| Initial baseline and oracle review, 30 calls | `historical/original-30-call/` | `runs/batch-20261116T073305630843Z/` |
| Requests layout amendment for both original methods | `compatibility/root-test-files-v2/` | Same batch; Requests jobs use this version |
| Verified review, 30 calls | `follow-up/verified-edits-v1/` | Its `runs/posthoc-26-20261116T125231955995Z/` |
| Evidence-first, 30 calls | `follow-up/evidence-first-v1/` | Its `runs/evidence-first-26-20261116T143134838264Z/` |
| Baseline and verified review, 40 calls | `follow-up/call-budget-40-v1/` | Its `runs/budget40-20261116T181519332333Z/` |

Paths in this table are relative to the repository root. Per-run `source/`
folders and metadata are the authoritative exact source snapshots. The original
root source was copied here before any November 20 edits. Historical launchers
may assume their original directory layout; use explicit framework, config,
input and output paths when studying reproduction, and do not accidentally
launch paid calls while reviewing code.

`results/pre-simplification-sha256.json` records hashes of preserved source and
selected raw artifacts before refactoring. Raw run folders are local and ignored
by normal Git rules; submission packaging must include the required selected
artifacts separately. No published artifact bundle is claimed by this index.
