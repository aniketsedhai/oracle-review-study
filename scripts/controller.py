"""One readable generation/review loop for all four study methods.

The historical versions that produced the reported results are preserved. This
shared implementation is a later refactor, not the source of those measurements.
"""

import json

from budget import Limits, SharedBudget
from methods import METHODS
from patches import capture_candidate
from review import (
    check_revision_claim, parse_review, review_submission_instructions, validate_edit,
)


def checkpoint_candidate(env, test_roots, directory):
    """Save even rejected candidates so that the decision can be inspected later."""
    if directory.exists():
        raise FileExistsError(f"Checkpoint already exists: {directory}")
    candidate = capture_candidate(env, test_roots)
    candidate.save(directory)
    return candidate


def run_workflow(*, instance, method, env, config, run_directory, session_factory,
                 reviewer_prompt, clock=None):
    # 1. Set the method and one shared allowance for this instance.
    if method not in METHODS:
        raise ValueError("Unknown method")
    options = METHODS[method]
    verify_edits = options["verify_edits"]
    roots = config["test_roots_by_repo"][instance["repo"]]
    run_directory.mkdir(parents=True, exist_ok=False)
    limits = Limits(**config["total_limits"])
    budget = SharedBudget(limits) if clock is None else SharedBudget(limits, clock=clock)
    generation_cap = limits
    if options["review"]:
        generation_cap = Limits(**config["experimental_generation_limits"])

    # 2. Generate tests. Capture the files even if a resource limit interrupts it.
    generator = session_factory(
        "generator", instance["problem_statement"], budget,
        budget.allowance(generation_cap), run_directory / "generator",
    )
    generation_outcome = generator.run_until_submission()
    candidate = checkpoint_candidate(env, roots, run_directory / "generator/checkpoint")
    selected = candidate if candidate.usable else None
    selected_checkpoint = "generator/checkpoint" if selected else None
    rounds = []
    pending_validation = False
    reason = "baseline_complete" if not options["review"] else "no_usable_candidate"

    # 3. Only review methods create a second conversation. Its rounds reuse history.
    if options["review"] and selected is not None:
        reason = budget.stop_reason()
        if reason is None:
            task = (reviewer_prompt + "\n\nBUG REPORT\n" + instance["problem_statement"]
                    + "\n\nPERMITTED TEST ROOTS\n" + json.dumps(roots)
                    + "\n\nCANDIDATE PATCH (already applied)\n" + selected.patch
                    + "\n\nREVIEW ROUND 1\n" + review_submission_instructions(verify_edits))
            reviewer = session_factory(
                "reviewer", task, budget, budget.allowance(), run_directory / "reviewer",
            )
            for number in range(1, config["max_review_rounds"] + 1):
                if budget.stop_reason():
                    reason = budget.stop_reason()
                    break
                previous, previous_checkpoint = selected, selected_checkpoint
                previous_pending = pending_validation
                outcome = reviewer.run_until_submission()
                checkpoint = f"reviewer/round-{number:02d}"
                revised = checkpoint_candidate(env, roots, run_directory / checkpoint)
                if revised.usable:
                    selected, selected_checkpoint = revised, checkpoint
                try:
                    record = parse_review(outcome.get("submission", ""), verify_edits)
                except (ValueError, TypeError):
                    record = None

                # 4. Verified review additionally checks claimed edits and execution.
                guard = {"issues": []}
                validation = None
                validation_mutated_patch = False
                if verify_edits:
                    guard = check_revision_claim(previous, revised, record)
                    pending_validation = pending_validation or guard["patch_changed"]
                    if revised.usable and record is not None and pending_validation:
                        validation, issue = validate_edit(env, record, budget, checkpoint)
                        if issue:
                            guard["issues"].append(issue)
                        if validation is not None:
                            directory = run_directory / checkpoint
                            (directory / "validation.json").write_text(json.dumps(validation, indent=2) + "\n")
                            after = checkpoint_candidate(env, roots, directory / "after-validation")
                            validation_mutated_patch = not after.usable or after.patch != revised.patch
                            if validation_mutated_patch:
                                guard["issues"].append("validation_modified_patch")
                                selected, selected_checkpoint = previous, previous_checkpoint
                                pending_validation = previous_pending
                            elif validation.get("returncode") == -1:
                                guard["issues"].append("validation_command_did_not_complete")
                            else:
                                pending_validation = False

                entry = {"round": number, "outcome": outcome, "record": record,
                         "candidate_usable": revised.usable, "budget": budget.snapshot()}
                if verify_edits:
                    entry.update(revision_guard=guard, validation=validation)
                (run_directory / checkpoint / "review.json").write_text(json.dumps(entry, indent=2) + "\n")
                rounds.append(entry)

                # 5. Stop or continue. An unusable edit never replaces an earlier patch.
                if not revised.usable:
                    reason = "invalid_revision_fallback"
                    break
                if validation_mutated_patch:
                    reason = "validation_modified_patch_fallback"
                    break
                if budget.stop_reason():
                    reason = "unverified_revision_resource_limit" if guard["issues"] else budget.stop_reason()
                    break
                if outcome.get("exit_status") != "Submitted":
                    reason = outcome.get("exit_status", "review_interrupted")
                    break
                if record is not None and not guard["issues"] and not record["continue_review"]:
                    reason = record["stop_reason"]
                    break
                if number == config["max_review_rounds"]:
                    reason = "unverified_revision_round_limit" if guard["issues"] else "round_limit"
                    break
                reviewer.continue_with(continuation_message(number + 1, record, guard, validation, verify_edits))

    # 6. Submit the selected test-only diff. Evaluation is a separate program.
    patch = selected.patch if selected else ""
    (run_directory / "prediction.patch").write_text(patch)
    prediction = {"instance_id": instance["instance_id"],
                  "model_name_or_path": method, "model_patch": patch}
    (run_directory / "predictions.jsonl").write_text(json.dumps(prediction) + "\n")
    summary = {"instance_id": instance["instance_id"], "method": method,
               "generation_outcome": generation_outcome, "review_rounds": len(rounds),
               "selected_checkpoint": selected_checkpoint, "stop_reason": reason,
               "budget": budget.snapshot(), "evaluation": "not run"}
    if verify_edits:
        summary.update(
            revision_guard_failures=sum(bool(item["revision_guard"]["issues"]) for item in rounds),
            selected_patch_validation_pending=pending_validation,
        )
    (run_directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return summary


def continuation_message(number, record, guard, validation, verify_edits):
    """The next round gets earlier reviewer history plus this explicit feedback."""
    message = f"REVIEW ROUND {number}. "
    if guard["issues"]:
        message += ("CONTROLLER CHECK FAILED: " + ", ".join(guard["issues"]) + ". "
                    "A reported revision must exist in the actual files, not only in the review record. "
                    "Perform the supported edit and run the relevant tests, or honestly report no change/uncertainty. "
                    "Include validation_command for the current candidate. "
                    "Revision claims refer to changes made in this round. ")
    if validation:
        message += "Actual validation output:\n" + validation.get("output", "")[-12000:] + "\n"
    if record:
        message += "Resolve the actionable concern recorded in the previous round. "
    else:
        message += "Your review record was missing or malformed; provide a valid record. "
    return message + review_submission_instructions(verify_edits)
