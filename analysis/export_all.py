"""Export all completed experiments from unchanged per-instance evidence.

No model calls or evaluator reruns. Missing predictions remain unsuccessful.
Environment annotations supplement, rather than overwrite, official reports.
"""
import csv
import hashlib
import json
from pathlib import Path
from statistics import mean

ROOT = Path(__file__).resolve().parents[1]


def locate(recorded_path):
    path = Path(recorded_path)
    # Prefer this extracted checkout, even if the old laptop path still exists.
    marker = "/oracle-review-study/"
    if marker in str(path):
        return ROOT / str(path).split(marker, 1)[1]
    if path.exists():
        return path
    return ROOT / path


def export():
    rows = []
    groups = []
    for experiment in json.loads((ROOT / "configs/experiments.json").read_text()):
        batch = ROOT / experiment["batch"]
        ledger = json.loads((batch / "batch.json").read_text())
        evaluation = json.loads((ROOT / "evaluation/batches" / batch.name / "evaluation-batch.json").read_text())
        jobs = []
        for job in ledger["jobs"]:
            key = job["instance_id"] + "/" + job["method"]
            entry = evaluation["jobs"][key]
            if entry["status"] not in {"evaluated", "missing_prediction"}:
                raise ValueError("Incomplete evaluation: " + key)
            run = locate(job["run_directory"])
            summary = json.loads((run / "summary.json").read_text())
            report = {}
            if entry.get("summary_path"):
                report = json.loads(locate(entry["summary_path"]).read_text())["official_report"][job["instance_id"]]
            selected = summary.get("selected_checkpoint")
            patch = (run / "prediction.patch").read_bytes()
            if selected:
                candidate = json.loads((run / selected / "candidate.json").read_text())
                if hashlib.sha256(patch).hexdigest() != candidate["patch_sha256"]:
                    raise ValueError("Selected prediction changed: " + key)
            elif patch:
                raise ValueError("Patch without selected checkpoint: " + key)
            actions = 0
            for trajectory in [run / "generator/trajectory.json", run / "reviewer/trajectory.json"]:
                if trajectory.exists():
                    messages = json.loads(trajectory.read_text())["messages"]
                    actions += sum(len(m.get("extra", {}).get("actions", [])) for m in messages if m.get("role") == "assistant")
            tests = report.get("tests_pred", {})
            logs = list((ROOT / "evaluation/work/run_instance_swt_logs" / run.name).glob("pred*/*/test_output.txt"))
            no_test_completed = not tests.get("FAIL_TO_PASS") and not tests.get("PASS_TO_PASS")
            blocked = bool(tests.get("UNMATCHED")) and no_test_completed and any(
                "No module named 'roman'" in log.read_text(errors="replace") for log in logs)
            row = {
                "experiment": experiment["name"], "method": job["method"], "call_cap": experiment["call_cap"],
                "instance_id": job["instance_id"], "stratum": job["stratum"],
                "official_resolved": bool(report.get("resolved")),
                "applicable": bool(report.get("patch_successfully_applied")),
                "status": "unevaluated_environment" if blocked else entry["status"],
                "environment_note": "Missing roman dependency in pre/post setup" if blocked else "",
                "coverage_delta_pred": report.get("coverage_delta_pred"),
                "model_calls": summary["budget"]["model_calls"], "bash_actions": actions,
                "estimated_cost_usd": summary["budget"]["estimated_cost_usd"],
                "workflow_seconds": summary["budget"]["elapsed_seconds"],
                "evaluation_seconds": entry.get("evaluation_seconds", 0),
                "f2p": len(tests.get("FAIL_TO_PASS", [])), "f2f": len(tests.get("FAIL_TO_FAIL", [])),
                "unmatched": len(tests.get("UNMATCHED", [])),
                "run": str(run.relative_to(ROOT)), "stop_reason": summary["stop_reason"],
            }
            rows.append(row)
            jobs.append(row)
        for method in dict.fromkeys(job["method"] for job in jobs):
            values = [job for job in jobs if job["method"] == method]
            if len(values) != 26:
                raise ValueError("Expected all 26 instances")
            coverage = [v["coverage_delta_pred"] for v in values if v["coverage_delta_pred"] is not None]
            success_cov = [v["coverage_delta_pred"] for v in values if v["official_resolved"] and v["coverage_delta_pred"] is not None]
            groups.append({
                "experiment": experiment["name"], "method": method, "call_cap": experiment["call_cap"],
                "role": experiment["role"], "n": len(values),
                "resolved": sum(v["official_resolved"] for v in values),
                "easy_resolved": sum(v["official_resolved"] for v in values if v["stratum"] == "easy"),
                "hard_resolved": sum(v["official_resolved"] for v in values if v["stratum"] == "hard"),
                "applicable": sum(v["applicable"] for v in values),
                "missing": sum(v["status"] == "missing_prediction" for v in values),
                "environment_blocked": sum(v["status"] == "unevaluated_environment" for v in values),
                "coverage_mean": mean(coverage) if coverage else None, "coverage_n": len(coverage),
                "successful_coverage_mean": mean(success_cov) if success_cov else None,
                "successful_coverage_n": len(success_cov),
                "model_calls": sum(v["model_calls"] for v in values),
                "bash_actions": sum(v["bash_actions"] for v in values),
                "estimated_cost_usd": sum(v["estimated_cost_usd"] for v in values),
                "workflow_seconds_mean": mean(v["workflow_seconds"] for v in values),
                "evaluation_seconds_total": sum(v["evaluation_seconds"] for v in values),
            })
    out = ROOT / "results/final"
    out.mkdir(exist_ok=True)
    (out / "all-experiments.json").write_text(json.dumps({"groups": groups, "rows": rows}, indent=2) + "\n")
    with (out / "per-instance.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps(groups, indent=2))


if __name__ == "__main__":
    export()
