"""Read reviewer decisions and, for verified review, check actual edits.

These checks concern JSON, file changes, and execution. They do not establish
whether an assertion is semantically correct.
"""

import json


def parse_review(submission, verify_edits=False):
    record = json.loads(submission)
    required = {
        "trigger", "expected_behavior", "evidence", "current_oracle",
        "alignment", "execution_evidence", "changes", "uncertainty",
        "decision", "continue_review", "stop_reason",
    }
    if not isinstance(record, dict) or not required.issubset(record):
        raise ValueError("Missing review fields")
    if record["decision"] not in {"keep", "revise", "uncertain"}:
        raise ValueError("Invalid review decision")
    if type(record["continue_review"]) is not bool:
        raise ValueError("continue_review must be a JSON boolean")
    if record["stop_reason"] not in {
        "aligned", "unresolved_uncertainty", "round_limit", "resource_limit", "continue"
    }:
        raise ValueError("Invalid stop reason")
    if record["continue_review"] != (record["stop_reason"] == "continue"):
        raise ValueError("Continuation and stopping reason disagree")
    if verify_edits:
        if type(record.get("patch_changed")) is not bool:
            raise ValueError("patch_changed must be a JSON boolean")
        if "validation_command" in record and not isinstance(record["validation_command"], str):
            raise ValueError("validation_command must be a string")
    return record


def check_revision_claim(before, after, record):
    changed = before.patch != after.patch
    declared = record.get("patch_changed") if record else None
    claimed = bool(record and (record["decision"] == "revise" or declared is True))
    issues = []
    if claimed and not changed:
        issues.append("claimed_revision_without_patch_change")
    if declared is not None and declared != changed:
        issues.append("declared_patch_change_mismatch")
    return {"patch_changed": changed, "revision_claimed": claimed, "issues": issues}


def validate_edit(env, record, budget, checkpoint):
    """Execute the reviewer's test command and save its real output.

    A nonzero test exit is allowed: a test should fail on buggy code. The caller
    separately captures the files again to check that validation did not edit them.
    """
    command = record.get("validation_command", "").strip()
    if not command:
        return None, "changed_patch_missing_validation_command"
    if budget.remaining().seconds <= 0:
        return None, "changed_patch_not_validated_before_deadline"
    try:
        result = env.execute(
            {"command": "set -o pipefail\n" + command},
            timeout=min(60, budget.remaining().seconds),
        )
    except Exception as error:
        result = {"returncode": -1, "output": "", "exception_type": type(error).__name__}
    result = {"command": command, "candidate_checkpoint": checkpoint, **result}
    return result, None


def review_submission_instructions(verify_edits=False):
    if not verify_edits:
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

    return '''Finish this round with one standalone bash tool call whose output is:
COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT
followed by one JSON object containing these keys:
trigger, expected_behavior, evidence, current_oracle, alignment,
execution_evidence, changes, uncertainty, decision, continue_review, stop_reason, patch_changed,
validation_command. validation_command is the exact focused test command to run
against the saved candidate; use an empty string if no edit was made and no
validation is pending. Do not include file edits in validation_command. The
controller executes it with pipefail and records the real exit status after a
patch change. Failing on buggy code is acceptable; unrelated failures require
inspection. Do not claim an edit unless it appears in the working tree.
patch_changed must be a JSON boolean reflecting actual changes in this round.
Use a JSON boolean for continue_review. Set stop_reason to continue only when
continue_review is true. Otherwise choose aligned, unresolved_uncertainty,
round_limit, or resource_limit. You may print both lines with a Python command.
Do not write the review record into the project checkout.
'''
