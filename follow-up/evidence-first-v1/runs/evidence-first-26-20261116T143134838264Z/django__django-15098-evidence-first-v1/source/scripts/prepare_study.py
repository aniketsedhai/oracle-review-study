"""Extract generation-only task files from a pinned, local benchmark snapshot.

Use the evaluator virtual environment for pyarrow. Reference fields are never
written to generation inputs; they remain in the separate evaluator snapshot.
"""

import argparse
import hashlib
import json
from pathlib import Path


def prepare(selection, rows, output):
    requested = [item["instance_id"] for item in selection["instances"]]
    if len(set(requested)) != len(requested):
        raise ValueError("Duplicate selected instances")
    by_id = {row["instance_id"]: row for row in rows}
    missing = sorted(set(requested) - set(by_id))
    if missing:
        raise ValueError(f"Selected IDs absent from pinned snapshot: {missing}")
    if output.exists():
        raise FileExistsError(output)
    output.mkdir(parents=True)
    tasks = []
    for selected in selection["instances"]:
        row = by_id[selected["instance_id"]]
        instance = {key: row[key] for key in ("instance_id", "repo", "base_commit", "problem_statement")}
        instance.update(dataset=selection["dataset"], dataset_revision=selection["dataset_revision"])
        path = output / (instance["instance_id"] + ".json")
        path.write_text(json.dumps(instance, indent=2) + "\n")
        tasks.append(dict(selected, repo=instance["repo"], input_path=path.name,
                          input_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                          image="docker.io/swebench/sweb.eval.x86_64." + instance["instance_id"].replace("__", "_1776_") + ":latest"))
    manifest = {key: selection[key] for key in ("status", "source", "dataset", "dataset_revision")}
    manifest.update(instances=tasks, instance_count=len(tasks), fields="generation-facing only")
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selection", type=Path, required=True)
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--snapshot-manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    selection = json.loads(args.selection.read_text())
    provenance = json.loads(args.snapshot_manifest.read_text())
    if any(selection[key] != provenance[key] for key in ("dataset", "dataset_revision")):
        raise SystemExit("Selected dataset/revision does not match snapshot provenance")
    digest = hashlib.sha256(args.snapshot.read_bytes()).hexdigest()
    if digest != provenance["snapshot_sha256"]:
        raise SystemExit("Benchmark snapshot checksum mismatch")
    import pyarrow.parquet as pq
    # Read only generation-facing columns, even though the pinned snapshot also
    # contains reference answers for separate evaluation.
    rows = pq.read_table(args.snapshot, columns=["instance_id", "repo", "base_commit", "problem_statement"]).to_pylist()
    manifest = prepare(selection, rows, args.output)
    print(f"Prepared {manifest['instance_count']} generation-only instance files in {args.output}")


if __name__ == "__main__":
    main()
