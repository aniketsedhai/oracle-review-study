"""Protect the disposable checkout before giving shell access to the model."""

import json
from pathlib import PurePosixPath
import shlex


def protect_checkout(env, test_roots):
    """Root setup followed by unprivileged model commands; Linux images only.

    The production checkout stays root-owned/read-only. Existing permitted test
    directories and Git metadata are writable by nobody. The host is not mounted.
    This is a file-write boundary, not protection against all possible attempts
    to infer a fix or create alternate implementations under /tmp.
    """
    python_environment = env.execute({"command": "python3 -c " + shlex.quote(
        "import json,os; print(json.dumps({'PATH':os.environ['PATH']}))")})
    if python_environment["returncode"]:
        raise RuntimeError("Cannot determine installed Python environment")
    installed_path = json.loads(python_environment["output"])["PATH"]
    for root in test_roots:
        path = PurePosixPath(root)
        if path.is_absolute() or ".." in path.parts or str(path) in {".", ".git"}:
            raise ValueError("Unsafe test root")
    script = '''
import json, os, pathlib, pwd, stat
roots = json.loads(ROOTS)
base = pathlib.Path('/testbed')
user = pwd.getpwnam('nobody')
def entries(path):
    yield path
    for directory, dirs, files in os.walk(path, followlinks=False):
        for name in dirs + files:
            yield pathlib.Path(directory) / name
for path in entries(base):
    if not path.is_symlink():
        path.chmod(stat.S_IMODE(path.stat().st_mode) & ~0o222)
for relative in ['.git'] + roots:
    target = base / relative
    if not (target.is_dir() or target.is_file()) or target.is_symlink() or base not in target.resolve().parents:
        raise RuntimeError('Configured writable directory is missing or unsafe')
    for path in entries(target):
        os.chown(path, user.pw_uid, user.pw_gid, follow_symlinks=False)
        if not path.is_symlink():
            mode = stat.S_IMODE(path.stat().st_mode) | 0o600
            if path.is_dir(): mode |= 0o100
            path.chmod(mode)
print('Production read-only; test roots and Git metadata writable by nobody')
'''.replace("ROOTS", repr(json.dumps(test_roots)))
    result = env.execute({"command": "python3 -c " + shlex.quote(script)}, timeout=120)
    if result["returncode"]:
        raise RuntimeError("Checkout permission setup failed")
    env.config.interpreter = ["runuser", "-u", "nobody", "--", "bash", "-c"]
    env.config.env.update(HOME="/tmp", GIT_CONFIG_COUNT="1",
                          GIT_CONFIG_KEY_0="safe.directory", GIT_CONFIG_VALUE_0="/testbed",
                          PATH=installed_path, PYTHONPATH="/testbed")
    # Validate the boundary without actually writing production files.
    probe = env.execute({"command": "python3 -c " + shlex.quote(
        "import os,json; from pathlib import Path; "
        f"roots=json.loads({json.dumps(test_roots)!r}); "
        "assert os.geteuid() != 0; "
        "assert not os.access('/testbed', os.W_OK); "
        "assert all(os.access('/testbed/'+r, os.W_OK) for r in roots); "
        "assert all(not os.access(p, os.W_OK) for p in Path('/testbed').iterdir() "
        "if p.is_file() and p.name not in roots); print('Permission boundary verified')")})
    if probe["returncode"]:
        raise RuntimeError("Checkout permission probe failed")
    return {"setup": result, "probe": probe, "agent_user": "nobody", "test_roots": test_roots}
