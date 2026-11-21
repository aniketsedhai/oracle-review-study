"""One fresh evidence-first generation run on every selected instance, explicitly post-hoc.

No outcome-based instance selection or reuse of the development pilot. Baseline
and original-review predictions remain frozen in the original study.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

VERSION = Path(__file__).resolve().parents[1]
STUDY = VERSION.parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--key-file", type=Path)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--study-cost-limit", type=float, default=3.5)
    args = parser.parse_args()
    manifest_path = args.manifest.resolve()
    manifest = json.loads(manifest_path.read_text())
    from run_batch import make_jobs
    jobs = [dict(job, method="evidence_first_v1") for job in make_jobs(manifest)
            if job["method"] == "baseline"]
    if not args.execute:
        print(json.dumps({"post_hoc": True, "instance_count": len(jobs), "paid_calls": False,
                          "study_cost_limit_usd": args.study_cost_limit, "jobs": jobs}, indent=2))
        return
    if not args.key_file:
        raise SystemExit("Supply the host key file")
    config = json.loads((VERSION / "configs/study.json").read_text())
    cap = config["total_limits"]["estimated_cost_usd"]
    if args.study_cost_limit < cap:
        raise SystemExit("Study allowance must cover at least one full per-instance cap")
    from docker_startup import ensure_docker_ready
    ensure_docker_ready()
    batch = VERSION / "runs" / ("evidence-first-26-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
    batch.mkdir(parents=True)
    (batch / "selection-manifest.json").write_bytes(manifest_path.read_bytes())
    (batch / "config.json").write_text(json.dumps(config, indent=2) + "\n")
    source_hashes = {str(p.relative_to(VERSION)): hashlib.sha256(p.read_bytes()).hexdigest()
                     for folder in ("scripts", "prompts") for p in (VERSION / folder).glob("*") if p.is_file()}
    ledger = {"study_role": "post_hoc_evidence_first_final_experiment", "instance_count": len(jobs),
              "jobs": jobs, "estimated_cost_usd": 0.0, "study_cost_limit_usd": args.study_cost_limit,
              "source_sha256": source_hashes, "development_pilot_reused": False,
              "original_comparison": str(STUDY / "runs/batch-20261116T073305630843Z"),
              "evaluation": "separate official unit-test evaluation"}
    def save():
        (batch / "batch.json").write_text(json.dumps(ledger, indent=2) + "\n")
    save()
    print(f"Follow-up batch: {batch}", flush=True)
    for job in jobs:
        if ledger["estimated_cost_usd"] + cap > args.study_cost_limit:
            ledger["stop_reason"] = "insufficient_remaining_allowance_for_run"
            save()
            return
        for relative, digest in source_hashes.items():
            if hashlib.sha256((VERSION / relative).read_bytes()).hexdigest() != digest:
                raise SystemExit("Follow-up source changed after freeze")
        task = manifest_path.parent / job["input_path"]
        if hashlib.sha256(task.read_bytes()).hexdigest() != job["input_sha256"]:
            raise SystemExit("Selected task input changed")
        with (batch / (job["instance_id"] + "-image.log")).open("w") as log:
            image = subprocess.run(["docker", "image", "inspect", job["image"]], stdout=log, stderr=log)
        if image.returncode:
            job["status"] = "infrastructure_image_unavailable"
            save()
            continue
        run = batch / (job["instance_id"] + "-evidence-first-v1")
        job.update(status="running", run_directory=str(run))
        save()
        command = [sys.executable, "-B", str(VERSION / "scripts/run_study.py"),
                   "--method", "baseline", "--instance", str(task), "--image", job["image"],
                   "--config", str(batch / "config.json"), "--framework", str(STUDY.parent / "mini-swe-agent"),
                   "--output-dir", str(run), "--discover-test-roots", "--key-file", str(args.key_file.resolve())]
        print(job["instance_id"], flush=True)
        with (batch / (run.name + ".log")).open("w") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        job["launcher_returncode"] = result.returncode
        summary = run / "summary.json"
        if not summary.exists():
            job["status"] = "launcher_failed_missing_summary"
            ledger["stop_reason"] = "unknown_usage_after_launcher_failure"
            save()
            return
        job.update(status="generation_finished", summary=json.loads(summary.read_text()))
        ledger["estimated_cost_usd"] += job["summary"]["budget"]["estimated_cost_usd"]
        save()
    ledger["stop_reason"] = "all_jobs_attempted"
    save()
    print("All follow-up generation jobs attempted", flush=True)


if __name__ == "__main__":
    main()
