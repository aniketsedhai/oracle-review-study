"""Resume a batch after the verified zero-model-call Requests setup failure.

Never regenerate completed predictions. Original frozen sources remain unchanged;
only Requests uses the documented root-test-file compatibility version.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch", type=Path, required=True)
    parser.add_argument("--key-file", type=Path, required=True)
    args = parser.parse_args()
    batch = args.batch.resolve()
    path = batch / "batch.json"
    ledger = json.loads(path.read_text())
    if ledger.get("stop_reason") != "unknown_usage_after_launcher_failure":
        raise SystemExit("This recovery requires the known initial setup failure")
    failures = [job for job in ledger["jobs"] if job["status"] == "launcher_failed_missing_summary"]
    if len(failures) != 1 or failures[0]["instance_id"] != "psf__requests-2931":
        raise SystemExit("Unexpected failure; inspect manually")
    failed = failures[0]
    failed_run = Path(failed["run_directory"])
    log = (batch / (failed_run.name + ".log")).read_text()
    if "No supported tests/testing directories discovered" not in log or list(failed_run.glob("**/trajectory.json")):
        raise SystemExit("Cannot establish zero-model-call setup failure")
    backup = batch / ("batch-before-recovery-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + ".json")
    backup.write_bytes(path.read_bytes())
    failed["attempts"] = [{"run_directory": str(failed_run), "status": "setup_failure_before_agent",
                           "model_calls": 0, "estimated_cost_usd": 0}]
    failed["status"] = "not_started"
    ledger.pop("stop_reason")
    compatibility = ROOT / "compatibility/root-test-files-v2"
    compatibility_hashes = {str(p.relative_to(compatibility)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for folder in ("scripts", "prompts") for p in (compatibility / folder).glob("*") if p.is_file()}
    ledger["infrastructure_amendment"] = {
        "reason": "Requests uses root-level test_requests.py; no supported directory existed",
        "scope": "Both Requests methods use compatibility/root-test-files-v2; other jobs use original frozen sources",
        "compatibility_sha256": compatibility_hashes,
        "completed_predictions_regenerated": False,
        "previous_attempt_preserved": str(failed_run)}

    def save():
        path.write_text(json.dumps(ledger, indent=2) + "\n")
    save()
    from docker_startup import ensure_docker_ready
    ensure_docker_ready()
    config = json.loads((batch / "config.json").read_text())
    cap = config["total_limits"]["estimated_cost_usd"]
    manifest = json.loads((batch / "selection-manifest.json").read_text())
    inputs = ROOT / "inputs/study-26"
    for index in range(0, len(ledger["jobs"]), 2):
        pair = ledger["jobs"][index:index+2]
        pending = [job for job in pair if job["status"] == "not_started"]
        if not pending:
            continue
        if ledger["estimated_cost_usd"] + len(pending) * cap > ledger["study_cost_limit_usd"]:
            ledger["stop_reason"] = "insufficient_remaining_allowance_for_pair"
            save()
            return
        image = pair[0]["image"]
        with (batch / (pair[0]["instance_id"] + "-image-resume.log")).open("w") as log:
            exists = subprocess.run(["docker", "image", "inspect", image], stdout=log, stderr=log)
            if exists.returncode:
                try:
                    pulled = subprocess.run(["docker", "pull", "--platform", "linux/amd64", image],
                                            stdout=log, stderr=log, timeout=600)
                    available = pulled.returncode == 0
                except subprocess.TimeoutExpired:
                    available = False
                if not available:
                    for job in pending:
                        job["status"] = "infrastructure_image_unavailable"
                    save()
                    continue
        for job in pending:
            for relative, digest in ledger["source_sha256"].items():
                if hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() != digest:
                    raise SystemExit("Original frozen source changed")
            for relative, digest in compatibility_hashes.items():
                if hashlib.sha256((compatibility / relative).read_bytes()).hexdigest() != digest:
                    raise SystemExit("Compatibility source changed")
            task = inputs / job["input_path"]
            if hashlib.sha256(task.read_bytes()).hexdigest() != job["input_sha256"]:
                raise SystemExit("Instance input checksum mismatch")
            is_requests = job["instance_id"] == "psf__requests-2931"
            launcher_root = compatibility if is_requests else ROOT
            run_name = job["instance_id"] + "-" + job["method"]
            if job.get("attempts"):
                run_name += "-setup-retry01"
            run = batch / run_name
            if run.exists():
                raise SystemExit("Refusing to overwrite an existing generation attempt")
            job.update(status="running", run_directory=str(run),
                       runner_version="root-test-files-v2" if is_requests else "original-frozen")
            save()
            command = [sys.executable, "-B", str(launcher_root / "scripts/run_study.py"),
                       "--method", job["method"], "--instance", str(task), "--image", image,
                       "--config", str(batch / "config.json"), "--output-dir", str(run),
                       "--discover-test-roots", "--framework", str(ROOT.parent / "mini-swe-agent"),
                       "--key-file", str(args.key_file.resolve())]
            print(f"{job['instance_id']} / {job['method']}", flush=True)
            with (batch / (run_name + ".log")).open("w") as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
            job["launcher_returncode"] = result.returncode
            summary = run / "summary.json"
            if not summary.exists():
                job["status"] = "launcher_failed_missing_summary"
                ledger["stop_reason"] = "unknown_usage_after_launcher_failure"
                save()
                return
            data = json.loads(summary.read_text())
            job.update(status="generation_finished", summary=data)
            ledger["estimated_cost_usd"] += data["budget"]["estimated_cost_usd"]
            save()
    ledger["stop_reason"] = "all_jobs_attempted"
    save()
    print("Generation batch finished", flush=True)


if __name__ == "__main__":
    main()
