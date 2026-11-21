"""Find conventional test directories from tracked buggy-snapshot paths only."""

from pathlib import PurePosixPath


def discover_test_roots(paths: list[str]) -> list[str]:
    roots = set()
    for path in paths:
        parsed = PurePosixPath(path)
        if parsed.is_absolute() or ".." in parsed.parts or parsed.suffix != ".py":
            continue
        for index, part in enumerate(parsed.parts[:-1]):
            if part in {"tests", "testing"}:
                roots.add("/".join(parsed.parts[:index + 1]))
                break
    return sorted(roots)
