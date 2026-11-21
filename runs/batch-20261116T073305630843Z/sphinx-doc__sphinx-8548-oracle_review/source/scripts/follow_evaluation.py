"""Evaluate finished, frozen jobs without regenerating any predictions.

Run in the evaluator virtual environment. One evaluation runs at a time; this
can follow a generation batch, using separate evaluator-only files and no API.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
OLD = ROOT.parent / "baseline-pilot/evaluation"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch", type=Path, required=True)
    parser.add_argument("--follow", action="store_true")
    parser.add_argument("--wait-for-pid", type=int,
                        help="Wait for an earlier evaluator watcher to exit before adopting its ledger")
    args = parser.parse_args()
    if args.wait_for_pid:
        print(f"Waiting for earlier evaluation watcher {args.wait_for_pid}; no duplicate evaluations", flush=True)
        while True:
            try:
                os.kill(args.wait_for_pid, 0)
            except ProcessLookupError:
                break
            time.sleep(10)
    batch = args.batch.resolve()
    selection = json.loads((batch / "selection-manifest.json").read_text())
    provenance = json.loads((OLD / "input-manifest.json").read_text())
    snapshot = OLD / "dataset-snapshot.parquet"
    if any(selection[key] != provenance[key] for key in ("dataset", "dataset_revision")):
        raise SystemExit("Reference dataset/revision does not match selected study")
    if hashlib.sha256(snapshot.read_bytes()).hexdigest() != provenance["snapshot_sha256"]:
        raise SystemExit("Reference snapshot checksum mismatch")
    output = ROOT / "evaluation/batches" / batch.name
    output.mkdir(parents=True, exist_ok=True)
    reference_file = output / "instance-evaluator-only.json"
    import pyarrow.parquet as pq
    ids = {item["instance_id"] for item in selection["instances"]}
    references = [row for row in pq.read_table(snapshot).to_pylist() if row["instance_id"] in ids]
    if {row["instance_id"] for row in references} != ids:
        raise SystemExit("Missing reference instances")
    if not reference_file.exists():
        reference_file.write_text(json.dumps(references, indent=2) + "\n")
    ledger_file = output / "evaluation-batch.json"
    ledger = json.loads(ledger_file.read_text()) if ledger_file.exists() else {
        "generation_batch": str(batch), "instance_count": len(ids), "jobs": {},
        "mode": "unit_test", "policy": "no generation or outcome-based patch selection"}

    def save():
        ledger_file.write_text(json.dumps(ledger, indent=2) + "\n")

    while True:
        generation = json.loads((batch / "batch.json").read_text())
        for job in generation["jobs"]:
            key = job["instance_id"] + "/" + job["method"]
            prior = ledger["jobs"].get(key)
            if (prior and prior["status"] != "not_evaluated") or job["status"] != "generation_finished":
                continue
            run = Path(job["run_directory"])
            patch = run / "prediction.patch"
            entry = {"instance_id": job["instance_id"], "method": job["method"],
                     "generation_run": str(run)}
            if not patch.exists() or not patch.read_bytes():
                entry.update(status="missing_prediction", resolved=False, applicable=False)
                ledger["jobs"][key] = entry
                save()
                continue
            summary = json.loads((run / "summary.json").read_text())
            selected = summary["selected_checkpoint"]
            candidate = json.loads((run / selected / "candidate.json").read_text())
            if hashlib.sha256(patch.read_bytes()).hexdigest() != candidate["patch_sha256"]:
                raise SystemExit("Final patch does not match selected checkpoint")
            destination = ROOT / "evaluation/runs" / run.name
            # Do not overwrite or automatically retry an interrupted evaluator.
            # Existing completed summaries can be adopted on a watcher restart.
            if not destination.exists():
                command = [sys.executable, "-B", str(ROOT / "scripts/evaluate_run.py"),
                           "--run", str(run), "--references", str(reference_file),
                           "--reference-manifest", str(OLD / "input-manifest.json")]
                print(f"Evaluating {key}", flush=True)
                with (output / (run.name + ".log")).open("w") as log:
                    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
                entry["launcher_returncode"] = result.returncode
            report = destination / "evaluation-summary.json"
            if report.exists():
                result = json.loads(report.read_text())
                official = result.get("official_report", {}).get(job["instance_id"])
                entry.update(status="evaluated" if official else "unevaluated_missing_report",
                             summary_path=str(report), evaluation_seconds=result["evaluation_seconds"])
                if official:
                    entry.update(resolved=official.get("resolved", False),
                                 applicable=official.get("patch_successfully_applied", False),
                                 coverage_delta_pred=official.get("coverage_delta_pred"))
            else:
                entry["status"] = "unevaluated_infrastructure_failure"
            ledger["jobs"][key] = entry
            save()
            print(f"{key}: {entry['status']}, resolved={entry.get('resolved', 'N/A')}", flush=True)
        # Generation can have resumed while a long evaluation was running.
        latest_generation = json.loads((batch / "batch.json").read_text())
        newly_ready = any(job["status"] == "generation_finished" and
                          (job["instance_id"] + "/" + job["method"] not in ledger["jobs"] or
                           ledger["jobs"].get(job["instance_id"] + "/" + job["method"], {}).get("status") == "not_evaluated")
                          for job in latest_generation["jobs"])
        if args.follow and newly_ready:
            continue
        generation = latest_generation
        if not args.follow or generation.get("stop_reason"):
            ledger["generation_stop_reason"] = generation.get("stop_reason", "still_running")
            # Fill every assigned job, including unstarted/infrastructure failures.
            for job in generation["jobs"]:
                key = job["instance_id"] + "/" + job["method"]
                if key not in ledger["jobs"]:
                    ledger["jobs"][key] = {"instance_id": job["instance_id"], "method": job["method"],
                                          "status": "not_evaluated", "generation_status": job["status"]}
            save()
            return
        time.sleep(10)


if __name__ == "__main__":
    main()
