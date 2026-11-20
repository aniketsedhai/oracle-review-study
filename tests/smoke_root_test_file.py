"""Offline Requests layout check for the documented infrastructure amendment."""
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "compatibility/root-test-files-v2/scripts"))
sys.path.insert(0, str(ROOT.parent / "mini-swe-agent/src"))
with tempfile.TemporaryDirectory() as runtime:
    os.environ.update(MSWEA_GLOBAL_CONFIG_DIR=runtime, MSWEA_SILENT_STARTUP="1")
    from minisweagent.environments.docker import DockerEnvironment
    from isolation import protect_checkout
    from patches import capture_candidate, permitted_path
    from test_layout import discover_test_roots
    assert discover_test_roots(["test_requests.py", "requests/api.py"]) == ["test_requests.py"]
    assert permitted_path("test_requests.py", ["test_requests.py"])
    assert not permitted_path("requests/api.py", ["test_requests.py"])
    env = DockerEnvironment(image="docker.io/swebench/sweb.eval.x86_64.psf_1776_requests-2931:latest",
                            cwd="/testbed", run_args=["--rm", "--network", "none", "--platform", "linux/amd64"],
                            env={"PYTHONDONTWRITEBYTECODE": "1"})
    try:
        protect_checkout(env, ["test_requests.py"])
        code = '''
from pathlib import Path
import requests
try:
    with open('/testbed/requests/__init__.py', 'a'):
        raise AssertionError('Production writable')
except PermissionError:
    pass
p=Path('/testbed/test_requests.py')
p.write_text(p.read_text()+'\\n# Permission smoke check\\n')
print('Production denied, existing root-level test writable, imports available')
'''
        result = env.execute({"command": "python3 -c " + shlex.quote(code)})
        print(result["output"])
        assert result["returncode"] == 0
        candidate = capture_candidate(env, ["test_requests.py"])
        assert candidate.usable, candidate.reason
        assert candidate.changed_paths == ["test_requests.py"]
        print("Root-level test candidate capture and clean-base application passed")
    finally:
        subprocess.run(["docker", "stop", "-t", "2", env.container_id], capture_output=True, timeout=30)
        env.container_id = None
