"""Check observable patch changes, not the semantic truth of review prose."""


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
