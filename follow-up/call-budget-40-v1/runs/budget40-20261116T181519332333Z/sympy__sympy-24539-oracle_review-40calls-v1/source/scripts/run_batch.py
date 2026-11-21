"""Plan or execute sequential paired runs; planning is the default and is free."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
STUDY = ROOT.parents[1]


def make_jobs(manifest):
    """Interleave easy/hard instances and alternate which method runs first."""
    groups = {label: sorted([item for item in manifest["instances"] if item["stratum"] == label],
                             key=lambda item: item["instance_id"]) for label in ("easy", "hard")}
    if sum(map(len, groups.values())) != len(manifest["instances"]):
        raise ValueError("Every instance must have easy or hard stratum")
    instances = []
    for index in range(max(map(len, groups.values()), default=0)):
        for label in ("easy", "hard"):
            if index < len(groups[label]):
                instances.append(groups[label][index])
    jobs = []
    for index, item in enumerate(instances):
        methods = ["baseline", "oracle_review"] if index % 2 == 0 else ["oracle_review", "baseline"]
        jobs.extend(dict(item, method=method, pair=index + 1, status="not_started") for method in methods)
    return jobs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--config", type=Path, default=ROOT / "configs/study.json")
    parser.add_argument("--execute", action="store_true", help="Actually launch paid runs")
    parser.add_argument("--confirm-selected-set", action="store_true", help="Acknowledge this selected instance set/revision")
    parser.add_argument("--key-file", type=Path)
    parser.add_argument("--study-cost-limit", type=float, default=8.0,
                        help="Conservative estimated generation spending limit for this batch")
    args = parser.parse_args()
    manifest_path = args.manifest.resolve()
    manifest = json.loads(manifest_path.read_text())
    config = json.loads(args.config.read_text())
    jobs = make_jobs(manifest)
    if not args.execute:
        print(json.dumps({"paid_calls": False, "instances": len(manifest["instances"]),
                          "jobs": jobs, "note": "Proposed set: confirm assignment/revision before executing"}, indent=2))
        return
    if not args.confirm_selected_set:
        raise SystemExit("Confirm the chosen instance set/revision before executing")
    per_run_cap = config["total_limits"]["estimated_cost_usd"]
    if args.study_cost_limit < 2 * per_run_cap:
        raise SystemExit("Study allowance must accommodate one complete pair at the configured caps")
    from docker_startup import ensure_docker_ready
    ensure_docker_ready()
    batch = ROOT / "runs" / ("budget40-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
    batch.mkdir(parents=True)
    (batch / "config.json").write_text(json.dumps(config, indent=2) + "\n")
    (batch / "selection-manifest.json").write_bytes(manifest_path.read_bytes())
    source_hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                     for folder in ("scripts", "prompts") for p in (ROOT / folder).glob("*") if p.is_file()}
    ledger = {"study_role": "post_hoc_40_call_budget_experiment", "new_pair_cutoff_utc": "2026-11-16T19:45:00+00:00", "instance_count": len(manifest["instances"]), "jobs": jobs,
              "estimated_cost_usd": 0.0, "study_cost_limit_usd": args.study_cost_limit,
              "source_sha256": source_hashes, "evaluation": "separate; not launched here"}

    def save():
        (batch / "batch.json").write_text(json.dumps(ledger, indent=2) + "\n")
    save()
    print(f"Batch directory: {batch}", flush=True)
    for index in range(0, len(jobs), 2):
        # Reserve enough for a whole pair before starting either method. This
        # reduces budget-driven imbalance; unstarted cases stay in the ledger.
        if ledger["estimated_cost_usd"] + 2 * per_run_cap > args.study_cost_limit:
            ledger["stop_reason"] = "insufficient_remaining_allowance_for_pair"
            save()
            break
        if datetime.now(timezone.utc) >= datetime.fromisoformat("2026-11-16T19:45:00+00:00"):
            ledger["stop_reason"] = "presentation_deadline_no_new_pairs"
            save()
            break
        pair = jobs[index:index + 2]
        image = pair[0]["image"]
        with (batch / (pair[0]["instance_id"] + "-image.log")).open("w") as log:
            inspect = subprocess.run(["docker", "image", "inspect", image], stdout=log, stderr=log)
            if inspect.returncode:
                try:
                    pulled = subprocess.run(["docker", "pull", "--platform", "linux/amd64", image],
                                            stdout=log, stderr=log, timeout=600)
                    available = pulled.returncode == 0
                except subprocess.TimeoutExpired:
                    available = False
                if not available:
                    for job in pair:
                        job["status"] = "infrastructure_image_unavailable"
                    save()
                    continue
        for job in pair:
            for relative, digest in source_hashes.items():
                if hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() != digest:
                    raise SystemExit("Source changed during batch; stop to preserve method consistency")
            task = manifest_path.parent / job["input_path"]
            if hashlib.sha256(task.read_bytes()).hexdigest() != job["input_sha256"]:
                raise SystemExit("Generation input changed after selection preparation")
            run = batch / (job["instance_id"] + "-" + job["method"] + "-40calls-v1")
            job.update(status="running", run_directory=str(run))
            save()
            command = [sys.executable, "-B", str(ROOT / "scripts/run_study.py"),
                       "--method", job["method"], "--instance", str(task), "--image", image,
                       "--config", str(batch / "config.json"), "--output-dir", str(run),
                       "--discover-test-roots", "--framework", str(STUDY.parent / "mini-swe-agent")]
            if args.key_file:
                command.extend(["--key-file", str(args.key_file.resolve())])
            print(f"{job['instance_id']} / {job['method']}", flush=True)
            with (batch / (run.name + ".log")).open("w") as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
            job["launcher_returncode"] = result.returncode
            summary = run / "summary.json"
            if summary.exists():
                data = json.loads(summary.read_text())
                job.update(status="generation_finished", summary=data)
                ledger["estimated_cost_usd"] += data["budget"]["estimated_cost_usd"]
            else:
                job["status"] = "launcher_failed_missing_summary"
                # Do not assume a missing summary means no provider cost. Stop
                # rather than silently undercounting and starting further jobs.
                ledger["stop_reason"] = "unknown_usage_after_launcher_failure"
                save()
                return
            save()
    ledger.setdefault("stop_reason", "all_jobs_attempted")
    save()
    print(f"Finished generation batch; inspect {batch / 'batch.json'}", flush=True)


if __name__ == "__main__":
    main()
