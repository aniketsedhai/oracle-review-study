"""Generation/review orchestration, with injectable agent sessions for testing."""

import json
from pathlib import Path

from budget import Limits, SharedBudget
from patches import Candidate, capture_candidate


def checkpoint_candidate(env, test_roots: list[str], directory: Path) -> Candidate:
    """Capture and save a candidate, including records of rejected candidates.

    Call after generation and after each completed review round. The caller
    chooses a distinct directory for each checkpoint so records are not replaced.
    """
    if directory.exists():
        raise FileExistsError(f"Checkpoint already exists: {directory}")
    candidate = capture_candidate(env, test_roots)
    candidate.save(directory)
    return candidate


def parse_review(submission: str) -> dict:
    """Require a machine-readable decision; malformed records cannot claim alignment."""
    record = json.loads(submission)
    required = {"trigger", "expected_behavior", "evidence", "current_oracle",
                "alignment", "execution_evidence", "changes", "uncertainty",
                "decision", "continue_review", "stop_reason"}
    if not isinstance(record, dict) or not required.issubset(record):
        raise ValueError("Missing review fields")
    if record["decision"] not in {"keep", "revise", "uncertain"}:
        raise ValueError("Invalid review decision")
    if type(record["continue_review"]) is not bool:
        raise ValueError("continue_review must be a JSON boolean")
    if record["stop_reason"] not in {"aligned", "unresolved_uncertainty",
                                      "round_limit", "resource_limit", "continue"}:
        raise ValueError("Invalid stop reason")
    if record["continue_review"] != (record["stop_reason"] == "continue"):
        raise ValueError("Continuation and stopping reason disagree")
    return record


def run_workflow(*, instance: dict, method: str, env, config: dict,
                 run_directory: Path, session_factory, reviewer_prompt: str,
                 clock=None) -> dict:
    """Run one method on one instance; environment must already be prepared.

    session_factory(role, task, budget, phase_limits, output_directory) returns a
    session with run_until_submission() and continue_with(task). The generator
    and reviewer are distinct sessions; reviewer rounds reuse the same session.
    Sessions charge the shared ledger and enforce their phase limits.
    No evaluator/reference information is accepted by this interface.
    """
    if method not in {"baseline", "oracle_review"}:
        raise ValueError("Unknown method")
    roots = config["test_roots_by_repo"][instance["repo"]]
    if run_directory.exists():
        raise FileExistsError(run_directory)
    run_directory.mkdir(parents=True)
    budget = SharedBudget(Limits(**config["total_limits"]), **({"clock": clock} if clock else {}))
    generation_cap = (Limits(**config["experimental_generation_limits"])
                      if method == "oracle_review" else budget.limits)
    generator = session_factory("generator", instance["problem_statement"], budget,
                                budget.allowance(generation_cap), run_directory / "generator")
    generation_outcome = generator.run_until_submission()
    candidate = checkpoint_candidate(env, roots, run_directory / "generator" / "checkpoint")
    selected = candidate if candidate.usable else None
    selected_checkpoint = "generator/checkpoint" if selected else None
    rounds = []
    reason = "baseline_complete" if method == "baseline" else "no_usable_candidate"

    if method == "oracle_review" and selected is not None:
        if budget.stop_reason():
            reason = budget.stop_reason()
        else:
            task = (reviewer_prompt + "\n\nBUG REPORT\n" + instance["problem_statement"]
                    + "\n\nPERMITTED TEST ROOTS\n" + json.dumps(roots)
                    + "\n\nCANDIDATE PATCH (already applied)\n" + selected.patch
                    + "\n\nREVIEW ROUND 1\n" + review_submission_instructions())
            reviewer = session_factory("reviewer", task, budget, budget.allowance(),
                                       run_directory / "reviewer")
            for round_number in range(1, config["max_review_rounds"] + 1):
                if budget.stop_reason():
                    reason = budget.stop_reason()
                    break
                outcome = reviewer.run_until_submission()
                checkpoint = f"reviewer/round-{round_number:02d}"
                revised = checkpoint_candidate(env, roots, run_directory / checkpoint)
                # Selection uses structural checks only, never evaluator outcomes.
                if revised.usable:
                    selected, selected_checkpoint = revised, checkpoint
                record = None
                try:
                    record = parse_review(outcome.get("submission", ""))
                except (ValueError, TypeError):
                    pass
                entry = {"round": round_number, "outcome": outcome,
                         "record": record, "candidate_usable": revised.usable,
                         "budget": budget.snapshot()}
                (run_directory / checkpoint / "review.json").write_text(json.dumps(entry, indent=2) + "\n")
                rounds.append(entry)
                if not revised.usable:
                    reason = "invalid_revision_fallback"
                    break
                if budget.stop_reason():
                    reason = budget.stop_reason()
                    break
                if outcome.get("exit_status") != "Submitted":
                    reason = outcome.get("exit_status", "review_interrupted")
                    break
                if record is not None and not record["continue_review"]:
                    reason = record["stop_reason"]
                    break
                if round_number == config["max_review_rounds"]:
                    reason = "round_limit"
                    break
                # A missing/malformed record consumes a round; request correction
                # without resetting history or giving the reviewer a fresh budget.
                reviewer.continue_with(
                    f"REVIEW ROUND {round_number + 1}. "
                    + ("Resolve the actionable concern recorded in the previous round. " if record
                       else "Your review record was missing or malformed; provide a valid record. ")
                    + review_submission_instructions())

    final_patch = selected.patch if selected else ""
    (run_directory / "prediction.patch").write_text(final_patch)
    prediction = {"instance_id": instance["instance_id"],
                  "model_name_or_path": method, "model_patch": final_patch}
    (run_directory / "predictions.jsonl").write_text(json.dumps(prediction) + "\n")
    summary = {"instance_id": instance["instance_id"], "method": method,
               "generation_outcome": generation_outcome, "review_rounds": len(rounds),
               "selected_checkpoint": selected_checkpoint, "stop_reason": reason,
               "budget": budget.snapshot(), "evaluation": "not run"}
    (run_directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return summary


def review_submission_instructions() -> str:
    return '''Finish this round with one standalone bash tool call whose output is:
COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT
followed by one JSON object containing these keys:
trigger, expected_behavior, evidence, current_oracle, alignment,
execution_evidence, changes, uncertainty, decision, continue_review, stop_reason.
Use a JSON boolean for continue_review. Set stop_reason to continue only when
continue_review is true. Otherwise choose aligned, unresolved_uncertainty,
round_limit, or resource_limit. You may print both lines with a Python command.
Do not write the review record into the project checkout.
'''
