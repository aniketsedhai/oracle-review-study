"""Opt-in offline Docker check, separate from ordinary unit-test discovery."""

import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT.parents[2] / "mini-swe-agent/src"))
with tempfile.TemporaryDirectory() as runtime:
    os.environ.update(MSWEA_GLOBAL_CONFIG_DIR=runtime, MSWEA_SILENT_STARTUP="1")
    from minisweagent.environments.docker import DockerEnvironment
    from isolation import protect_checkout
    env = DockerEnvironment(image="docker.io/swebench/sweb.eval.x86_64.django_1776_django-16485:latest",
                            cwd="/testbed", run_args=["--rm", "--network", "none", "--platform", "linux/amd64"],
                            env={"PYTHONDONTWRITEBYTECODE": "1"})
    try:
        print(json.dumps(protect_checkout(env, ["tests"]), indent=2))
        script = '''
from pathlib import Path
try:
    with open('/testbed/django/__init__.py', 'a') as handle:
        raise AssertionError('Production file was writable')
except PermissionError:
    print('Production write denied')
test = Path('/testbed/tests/test_permission_probe.py')
test.write_text('assert True\\n')
assert test.read_text() == 'assert True\\n'
test.unlink()
print('Test-file creation succeeded')
'''
        result = env.execute({"command": "python3 -c " + shlex.quote(script)})
        print(json.dumps(result, indent=2))
        assert result["returncode"] == 0
        result = env.execute({"command": "python3 tests/runtests.py template_tests.filter_tests.test_floatformat"}, timeout=60)
        print(json.dumps(result, indent=2))
        assert result["returncode"] == 0
    finally:
        subprocess.run(["docker", "stop", "-t", "2", env.container_id], capture_output=True, timeout=30)
        env.container_id = None
