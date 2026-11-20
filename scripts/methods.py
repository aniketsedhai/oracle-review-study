"""The four methods share one runner; only these choices differ."""

METHODS = {
    "baseline": {
        "generator_prompt": "generator.md",
        "reviewer_prompt": "oracle_reviewer.md",
        "review": False,
        "verify_edits": False,
    },
    "oracle_review": {
        "generator_prompt": "generator.md",
        "reviewer_prompt": "oracle_reviewer.md",
        "review": True,
        "verify_edits": False,
    },
    "verified_review": {
        "generator_prompt": "generator.md",
        "reviewer_prompt": "verified_reviewer.md",
        "review": True,
        "verify_edits": True,
    },
    "evidence_first": {
        "generator_prompt": "evidence_first.md",
        "reviewer_prompt": "oracle_reviewer.md",
        "review": False,
        "verify_edits": False,
    },
}
