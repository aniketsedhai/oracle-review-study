"""Grade a frozen prediction using the unchanged official unit-test harness.

Evaluator-only inputs must never be supplied to run_study.py or an agent session.
This launcher reuses a pinned local reference snapshot; it makes no model calls.
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
OLD_EVALUATION = ROOT.parent / "baseline-pilot/evaluation"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def prepare_inputs(run, references, provenance, output):
    instance = json.loads((run / "instance.json").read_text())
    prediction = json.loads((run / "predictions.jsonl").read_text())
    patch_bytes = (run / "prediction.patch").read_bytes()
    if prediction["instance_id"] != instance["instance_id"] or prediction["model_patch"].encode() != patch_bytes:
        raise ValueError("Frozen prediction and patch do not match")
    if not patch_bytes:
        raise ValueError("No prediction patch; record an unsuccessful generation rather than evaluate it")
    if any(instance[key] != provenance[key] for key in ("dataset", "dataset_revision")):
        raise ValueError("Evaluator snapshot dataset/revision does not match generation")
    matches = [row for row in references if row["instance_id"] == instance["instance_id"]]
    if len(matches) != 1 or matches[0]["base_commit"] != instance["base_commit"]:
        raise ValueError("Missing or mismatched evaluator reference instance")
    output.mkdir(parents=True, exist_ok=False)
    (output / "predictions-frozen.jsonl").write_bytes((run / "predictions.jsonl").read_bytes())
    (output / "instance-evaluator-only.json").write_text(json.dumps(matches, indent=2) + "\n")
    manifest = {"generation_run": str(run), "instance_id": instance["instance_id"],
                "prediction_sha256": sha(patch_bytes), "dataset": instance["dataset"],
                "dataset_revision": instance["dataset_revision"], "reference_provenance": provenance,
                "reference_instance_sha256": sha(json.dumps(matches, sort_keys=True).encode()),
                "reference_artifacts": "evaluator-only; never passed to generation or review"}
    (output / "input-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return instance, prediction, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--references", type=Path, default=OLD_EVALUATION / "instance-evaluator-only.json")
    parser.add_argument("--reference-manifest", type=Path, default=OLD_EVALUATION / "input-manifest.json")
    parser.add_argument("--harness", type=Path, default=OLD_EVALUATION / "harness")
    args = parser.parse_args()
    run, harness = args.run.resolve(), args.harness.resolve()
    if subprocess.check_output(["git", "-C", str(harness), "status", "--porcelain"], text=True).strip():
        raise SystemExit("Harness has local changes; inspect before evaluation")
    output = ROOT / "evaluation/runs" / run.name
    instance, prediction, manifest = prepare_inputs(
        run, json.loads(args.references.read_text()), json.loads(args.reference_manifest.read_text()), output)
    work = ROOT / "evaluation/work"
    work.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ)
    for key in list(environment):
        if key.endswith("API_KEY") or key.endswith("API_TOKEN"):
            environment.pop(key)
    environment.update(PYTHONPATH=os.pathsep.join([str(harness), str(harness / "src")]),
                       PYTHONDONTWRITEBYTECODE="1", PYTHON_DOTENV_DISABLED="1")
    if "DOCKER_HOST" not in environment:
        environment["DOCKER_HOST"] = subprocess.check_output(
            ["docker", "context", "inspect", "--format", "{{.Endpoints.docker.Host}}"], text=True).strip()
    command = [sys.executable, "-B", "-m", "src.main",
               "--dataset_name", str(output / "instance-evaluator-only.json"),
               "--predictions_path", str(output / "predictions-frozen.jsonl"),
               "--instance_ids", instance["instance_id"], "--run_id", run.name,
               "--max_workers", "1", "--compute_coverage", "true", "--exec_mode", "unit_test",
               "--timeout", "600", "--cache_level", "instance", "--clean", "false", "--build_mode", "api"]
    record = {"command": command, "working_directory": str(work), "exec_mode": "unit_test",
              "harness_commit": subprocess.check_output(["git", "-C", str(harness), "rev-parse", "HEAD"], text=True).strip(),
              "credential_environment_removed": True}
    (output / "run-manifest.json").write_text(json.dumps(record, indent=2) + "\n")
    (output / "requirements.lock.txt").write_text(subprocess.check_output([sys.executable, "-m", "pip", "freeze"], text=True))
    started = time.monotonic()
    print(f"Official unit-test evaluation started. Logs: {output}", flush=True)
    with (output / "official-console.log").open("w") as log:
        result = subprocess.run(command, cwd=work, env=environment, stdout=log, stderr=subprocess.STDOUT)
    record.update(returncode=result.returncode, evaluation_seconds=time.monotonic() - started)
    if sha((run / "prediction.patch").read_bytes()) != manifest["prediction_sha256"]:
        raise RuntimeError("Generation patch changed during evaluation")
    (output / "run-manifest.json").write_text(json.dumps(record, indent=2) + "\n")
    report_path = work / "run_instance_swt_logs" / run.name / prediction["model_name_or_path"] / instance["instance_id"] / "report.json"
    summary = {"instance_id": instance["instance_id"], "harness_returncode": result.returncode,
               "evaluation_seconds": record["evaluation_seconds"], "report_path": str(report_path),
               "prediction_sha256": manifest["prediction_sha256"]}
    if report_path.exists():
        summary["official_report"] = json.loads(report_path.read_text())
    else:
        summary["status"] = "unevaluated_missing_instance_report"
    (output / "evaluation-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == "__main__":
    main()
