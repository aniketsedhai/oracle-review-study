"""Rebuild paired tables from preserved generation and official evaluation files.

Unavailable coverage stays null. Unprocessed evaluations stay pending rather
than silently becoming failures. Final class scores retain all 26 instances.
"""

import argparse
from collections import Counter
import csv
from datetime import datetime, timezone
import json
from pathlib import Path
from statistics import mean

ROOT = Path(__file__).resolve().parents[1]
METHODS = ("baseline", "oracle_review")


def summarize(batch: Path):
    generation = json.loads((batch / "batch.json").read_text())
    selection = json.loads((batch / "selection-manifest.json").read_text())
    evaluation_path = ROOT / "evaluation/batches" / batch.name / "evaluation-batch.json"
    evaluation = json.loads(evaluation_path.read_text()) if evaluation_path.exists() else {"jobs": {}}
    by_job = {(job["instance_id"], job["method"]): job for job in generation["jobs"]}
    rows = []
    for instance in sorted(selection["instances"], key=lambda item: item["instance_id"]):
        row = {"instance_id": instance["instance_id"], "repo": instance["repo"], "stratum": instance["stratum"]}
        for method in METHODS:
            job = by_job[(instance["instance_id"], method)]
            run = Path(job["run_directory"]) if job.get("run_directory") else None
            status = evaluation["jobs"].get(instance["instance_id"] + "/" + method, {})
            evaluation_status = status.get("status", "pending")
            pending = evaluation_status in {"pending", "not_evaluated"} and job["status"] == "generation_finished"
            official = None
            if status.get("summary_path"):
                report = json.loads(Path(status["summary_path"]).read_text())
                official = report.get("official_report", {}).get(instance["instance_id"])
            summary = job.get("summary", {})
            stats = summary.get("budget", {})
            reviews = [json.loads(path.read_text()) for path in sorted(run.glob("reviewer/round-*/review.json"))] if run else []
            generator = run / "generator/checkpoint/candidate.json" if run else None
            selected = run / summary["selected_checkpoint"] / "candidate.json" if run and summary.get("selected_checkpoint") else None
            changed = None
            if generator and generator.exists() and selected and selected.exists():
                initial, final = json.loads(generator.read_text()), json.loads(selected.read_text())
                changed = initial["patch_sha256"] != final["patch_sha256"]
            item = {
                "generation_status": job["status"], "evaluation_status": evaluation_status,
                "pending": pending,
                "resolved": bool(official.get("resolved")) if official else (None if pending else False),
                "applicable": bool(official.get("patch_successfully_applied")) if official else (None if pending else False),
                "coverage_delta_pred": official.get("coverage_delta_pred") if official else None,
                "coverage_pred": official.get("coverage_pred") if official else None,
                "added_f2p": official.get("added_f2p") if official else None,
                "model_calls": stats.get("model_calls"), "estimated_cost_usd": stats.get("estimated_cost_usd"),
                "generation_seconds": stats.get("elapsed_seconds"), "evaluation_seconds": status.get("evaluation_seconds"),
                "review_attempts": len(reviews), "valid_review_records": sum(review.get("record") is not None for review in reviews),
                "review_decisions": [review["record"]["decision"] for review in reviews if review.get("record")],
                "review_stop_reason": summary.get("stop_reason"), "final_patch_changed": changed,
                "run_directory": str(run) if run else None,
                "report_path": status.get("summary_path"),
                "tests_pred": official.get("tests_pred", {}) if official else {},
            }
            row[method] = item
        if any(row[method]["pending"] for method in METHODS):
            row["paired_outcome"] = "pending"
        else:
            first, second = [row[method]["resolved"] for method in METHODS]
            row["paired_outcome"] = "both" if first and second else "baseline_only" if first else "review_only" if second else "neither"
        rows.append(row)
    n = len(rows)
    totals = {}
    for method in METHODS:
        values = [row[method] for row in rows]
        available = [item["coverage_delta_pred"] for item in values if item["coverage_delta_pred"] is not None]
        successful_coverage = [item["coverage_delta_pred"] for item in values if item["resolved"] and item["coverage_delta_pred"] is not None]
        successes = sum(item["resolved"] is True for item in values)
        totals[method] = {
            "assigned": n, "successes": successes, "success_rate_over_assigned": successes / n,
            "applicable": sum(item["applicable"] is True for item in values),
            "pending": sum(item["pending"] for item in values),
            "missing_predictions": sum(item["evaluation_status"] == "missing_prediction" for item in values),
            "unevaluated_infrastructure": sum(item["evaluation_status"].startswith("unevaluated") for item in values),
            "coverage_delta_mean_available": mean(available) if available else None,
            "coverage_available_n": len(available),
            "successful_coverage_delta_mean": mean(successful_coverage) if successful_coverage else None,
            "successful_coverage_available_n": len(successful_coverage),
            "estimated_cost_usd": sum(item["estimated_cost_usd"] or 0 for item in values),
            "generation_seconds_mean": mean([item["generation_seconds"] for item in values if item["generation_seconds"] is not None]),
            "generation_time_available_n": sum(item["generation_seconds"] is not None for item in values),
            "evaluation_seconds_total": sum(item["evaluation_seconds"] or 0 for item in values),
            "review_attempts": sum(item["review_attempts"] for item in values),
            "instances_with_valid_review": sum(item["valid_review_records"] > 0 for item in values),
            "instances_with_changed_patch": sum(item["final_patch_changed"] is True for item in values),
            "stop_reasons": dict(Counter(item["review_stop_reason"] for item in values)),
        }
    counts = dict(Counter(row["paired_outcome"] for row in rows))
    complete = all(totals[method]["pending"] == 0 for method in METHODS) and generation.get("stop_reason") is not None
    cases = []
    if complete:
        # Disagreements first, followed by both-success and neither-success.
        # Lexical ID order within each group; fill sparse categories by ID.
        for categories in (("baseline_only", "review_only"), ("both",), ("neither",)):
            group = [row["instance_id"] for row in rows if row["paired_outcome"] in categories]
            cases.extend(group[:2])
        for row in rows:
            if len(cases) >= 6:
                break
            if row["instance_id"] not in cases:
                cases.append(row["instance_id"])
    return {"snapshot_utc": datetime.now(timezone.utc).isoformat(), "complete": complete,
            "batch": str(batch), "assigned_instances": n, "methods": totals,
            "paired_counts": counts, "case_selection": cases,
            "case_selection_rule": "Two disagreements, two both-successes, two neither-successes, lexical ID order within groups; fill sparse groups by lexical ID",
            "rows": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch", type=Path, required=True)
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()
    result = summarize(args.batch.resolve())
    if args.require_complete and not result["complete"]:
        raise SystemExit("Evaluation remains incomplete; refusing final-result export")
    output = ROOT / "results/main-study"
    output.mkdir(parents=True, exist_ok=True)
    (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    with (output / "paired-outcomes.csv").open("w", newline="") as handle:
        columns = ["instance_id", "repo", "stratum", "paired_outcome"] + [
            method + "_" + field for method in METHODS for field in (
                "evaluation_status", "resolved", "applicable", "coverage_delta_pred", "estimated_cost_usd", "generation_seconds")]
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        for row in result["rows"]:
            flat = {key: row[key] for key in columns[:4]}
            for method in METHODS:
                flat.update({method + "_" + field: row[method][field] for field in (
                    "evaluation_status", "resolved", "applicable", "coverage_delta_pred", "estimated_cost_usd", "generation_seconds")})
            writer.writerow(flat)
    print(json.dumps({key: result[key] for key in ("complete", "assigned_instances", "methods", "paired_counts", "case_selection")}, indent=2))


if __name__ == "__main__":
    main()
