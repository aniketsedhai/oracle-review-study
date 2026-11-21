#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD ca80f03a43bc39e4cc2c67dc99817b3c9f13b8a6 >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff ca80f03a43bc39e4cc2c67dc99817b3c9f13b8a6
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/tests/lint/test_pylinter.py b/tests/lint/test_pylinter.py
index f982787..8bd8e56 100644
--- a/tests/lint/test_pylinter.py
+++ b/tests/lint/test_pylinter.py
@@ -2,8 +2,9 @@
 # For details: https://github.com/PyCQA/pylint/blob/main/LICENSE
 # Copyright (c) https://github.com/PyCQA/pylint/blob/main/CONTRIBUTORS.txt
 
+from pathlib import Path
 from typing import Any, NoReturn
-from unittest.mock import patch
+from unittest.mock import mock_open, patch
 
 import pytest
 from astroid import AstroidBuildingError
@@ -11,6 +12,8 @@ from py._path.local import LocalPath  # type: ignore[import]
 from pytest import CaptureFixture
 
 from pylint.lint.pylinter import PyLinter
+from pylint.lint.run import _cpu_count
+from pylint.testutils._run import _Run
 from pylint.utils import FileState
 
 
@@ -41,3 +44,55 @@ def test_check_deprecation(linter: PyLinter, recwarn):
     linter.check("myfile.py")
     msg = recwarn.pop()
     assert "check function will only accept sequence" in str(msg)
+
+
+# Regression tests for https://github.com/PyCQA/pylint/issues/6702:
+# ``--jobs=0`` crashed when the cgroup CPU detection returned 0.
+_CGROUP_CPU_FILES = {
+    "/sys/fs/cgroup/cpu/cpu.cfs_quota_us": "-1",
+    "/sys/fs/cgroup/cpu/cpu.cfs_period_us": "100000",
+    "/sys/fs/cgroup/cpu/cpu.shares": "2",
+}
+
+
+def _fake_cgroup_open(path: Any, *args: Any, **kwargs: Any) -> Any:
+    """Pretend the cgroup CPU files contain the values from the bug report."""
+    if str(path) in _CGROUP_CPU_FILES:
+        return mock_open(read_data=_CGROUP_CPU_FILES[str(path)])()
+    return _real_open(path, *args, **kwargs)
+
+
+_real_open = open
+
+
+def test_cpu_count_never_zero() -> None:
+    """The number of CPUs used for ``--jobs=0`` must never be 0."""
+    with patch("pylint.lint.run.Path.is_file", return_value=True), patch(
+        "builtins.open", _fake_cgroup_open
+    ):
+        assert _cpu_count() >= 1
+
+
+def test_jobs_zero_does_not_crash() -> None:
+    """Running pylint with ``--jobs=0`` must not crash when the detected
+    number of CPUs is 0 (see issue #6702).
+    """
+    recorded_jobs = []
+
+    def _fake_check_parallel(linter: Any, jobs: int, *args: Any, **kwargs: Any) -> None:
+        recorded_jobs.append(jobs)
+
+    with patch("pylint.lint.run.Path.is_file", return_value=True), patch(
+        "builtins.open", _fake_cgroup_open
+    ), patch("pylint.lint.pylinter.check_parallel", _fake_check_parallel):
+        with pytest.raises(SystemExit) as cm:
+            _Run(
+                [
+                    "--jobs=0",
+                    "--persistent=no",
+                    "--disable=all",
+                    str(Path(__file__).parent.parent / "input" / "noext"),
+                ]
+            )
+    assert cm.value.code == 0
+    assert recorded_jobs == [1]

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(pylint/lint/run\.py)' -m pytest --no-header -rA  -p no:cacheprovider tests/lint/test_pylinter.py
cat coverage.cover
git checkout ca80f03a43bc39e4cc2c67dc99817b3c9f13b8a6
git apply /root/pre_state.patch
