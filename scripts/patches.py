"""Capture test candidates from an environment without importing the agent framework.

The environment needs only execute({"command": ...}), making this usable with
DockerEnvironment and testable with a temporary local Git repository.
"""

from dataclasses import asdict, dataclass
from pathlib import Path, PurePosixPath
import hashlib
import base64
import json
import shlex


@dataclass
class Candidate:
    patch: str
    changed_paths: list[str]
    usable: bool
    reason: str
    whitespace_check_returncode: int | None = None

    def save(self, directory: Path) -> None:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "candidate.patch").write_text(self.patch)
        record = asdict(self)
        record.pop("patch")
        record["patch_bytes"] = len(self.patch.encode())
        record["patch_sha256"] = hashlib.sha256(self.patch.encode()).hexdigest()
        (directory / "candidate.json").write_text(json.dumps(record, indent=2) + "\n")


def permitted_path(path: str, test_roots: list[str]) -> bool:
    """Use explicit repository-specific roots, never a universal tests/ assumption."""
    parsed = PurePosixPath(path)
    if parsed.is_absolute() or ".." in parsed.parts or not path.endswith(".py"):
        return False
    for root in test_roots:
        if root.endswith(".py"):
            if path == root:
                return True
        elif path.startswith(root.rstrip("/") + "/"):
            return True
    return False


def check_forward_application(env, patch: str) -> dict:
    """Check the exact saved patch against HEAD in a temporary Git index.

    The index represents the clean buggy snapshot. Neither the agent's working
    files nor its normal index are reset or changed. This checks application,
    not execution; it does not create a second installed project environment.
    """
    encoded = base64.b64encode(patch.encode()).decode("ascii")
    script = f"""
import base64, os, subprocess, tempfile
with tempfile.TemporaryDirectory(prefix='oracle-patch-check-') as directory:
    environment = dict(os.environ, GIT_INDEX_FILE=os.path.join(directory, 'index'))
    subprocess.run(['git', 'read-tree', 'HEAD'], env=environment, check=True)
    result = subprocess.run(
        ['git', 'apply', '--cached', '--check', '--whitespace=nowarn', '-'],
        env=environment, input=base64.b64decode({encoded!r}))
    raise SystemExit(result.returncode)
"""
    return env.execute({"command": "python3 -c " + shlex.quote(script)})


def capture_candidate(env, test_roots: list[str]) -> Candidate:
    """Capture changes relative to HEAD; HEAD must be the pristine buggy snapshot.

    This does not validate oracle correctness or prohibit semantic weakening.
    Whitespace warnings are recorded but do not by themselves invalidate a patch.
    """
    def command(text):
        return env.execute({"command": text})

    # Intent-to-add includes newly generated test files in the diff.
    added = command("git add -N -- .")
    if added["returncode"]:
        return Candidate("", [], False, "intent_to_add_failed")
    names = command("git diff HEAD --name-only -z --no-renames")
    if names["returncode"]:
        return Candidate("", [], False, "retrival_of_changed_paths_name_failed")
    # NUL separators also handle file names containing spaces or newlines.
    paths = [path for path in names["output"].split("\0") if path]
    if not paths:
        return Candidate("", paths, False, "no_changes")
    if not all(permitted_path(path, test_roots) for path in paths):
        return Candidate("", paths, False, "disallowed_paths")

    # Block binary files and special modes (symlinks, executable files, submodules).
    stats = command("git diff HEAD --numstat --no-renames")
    if stats["returncode"]:
        return Candidate("", paths, False, "diff_stats_failed")
    if any(line.startswith("-\t-\t") for line in stats["output"].splitlines()):
        return Candidate("", paths, False, "binary_changes")
    quoted_paths = " ".join(shlex.quote(path) for path in paths)
    modes = command(f"git ls-files --stage -- {quoted_paths}")
    if modes["returncode"]:
        return Candidate("", paths, False, "file_modes_failed")
    for line in modes["output"].splitlines():
        metadata, _, path = line.partition("\t")
        mode = metadata.split()[0]
        existing_root_test = path in test_roots and path.endswith(".py")
        if mode != "100644" and not (mode == "100755" and existing_root_test):
            return Candidate("", paths, False, "unsupported_file_mode")
    special = command(f"find {quoted_paths} -prune -type l -print")
    # find can report missing deleted files; deletions still need semantic review.
    if special["output"].strip() and special["returncode"] == 0:
        return Candidate("", paths, False, "symlink_changes")

    diff = command("git diff HEAD --binary --no-ext-diff --no-renames")
    if diff["returncode"] or not diff["output"]:
        return Candidate("", paths, False, "diff_extraction_failed")
    whitespace = command("git diff HEAD --check")
    check = check_forward_application(env, diff["output"])
    if check["returncode"]:
        return Candidate("", paths, False, "forward_apply_check_failed", whitespace["returncode"])
    return Candidate(diff["output"], paths, True, "captured", whitespace["returncode"])
