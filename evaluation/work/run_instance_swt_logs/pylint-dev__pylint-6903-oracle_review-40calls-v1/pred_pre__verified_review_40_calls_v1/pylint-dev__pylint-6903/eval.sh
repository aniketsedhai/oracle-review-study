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
diff --git a/tests/lint/unittest_lint.py b/tests/lint/unittest_lint.py
index 3dbde39..17c8df1 100644
--- a/tests/lint/unittest_lint.py
+++ b/tests/lint/unittest_lint.py
@@ -12,6 +12,7 @@ import os
 import re
 import sys
 import tempfile
+import unittest.mock
 from collections.abc import Iterable, Iterator
 from contextlib import contextmanager
 from importlib import reload
@@ -931,3 +932,56 @@ print(submodule1)
         with fix_import_path([tmpdir]):
             linter.check(["submodule2.py"])
     assert not linter.stats.by_msg
+
+
+@pytest.mark.parametrize(
+    "quota,period,shares,expected",
+    [
+        # cgroup v1 quota/period values that round down to zero must not be
+        # returned as zero (see https://github.com/PyCQA/pylint/issues/6673).
+        (-1, 100000, 2, 1),
+        (-1, 100000, 1023, 1),
+        (-1, 100000, 1024, 1),
+        (-1, 100000, 2048, 2),
+        (100000, 100000, 2, 1),
+        (50000, 100000, 2, 1),
+        (200000, 100000, 2, 2),
+    ],
+)
+def test_query_cpu_never_returns_zero(
+    quota: int, period: int, shares: int, expected: int
+) -> None:
+    """The number of CPUs detected in a container should never be zero."""
+    from pylint.lint.run import _query_cpu
+
+    def fake_is_file(self: Path) -> bool:
+        return str(self) in {
+            "/sys/fs/cgroup/cpu/cpu.cfs_quota_us",
+            "/sys/fs/cgroup/cpu/cpu.cfs_period_us",
+            "/sys/fs/cgroup/cpu/cpu.shares",
+        }
+
+    def fake_open(file: str, *args: object, **kwargs: object) -> StringIO:
+        values = {
+            "/sys/fs/cgroup/cpu/cpu.cfs_quota_us": quota,
+            "/sys/fs/cgroup/cpu/cpu.cfs_period_us": period,
+            "/sys/fs/cgroup/cpu/cpu.shares": shares,
+        }
+        return StringIO(f"{values[file]}\n")
+
+    with unittest.mock.patch.object(Path, "is_file", fake_is_file), unittest.mock.patch(
+        "builtins.open", fake_open
+    ):
+        result = _query_cpu()
+
+    assert result is not None
+    assert result >= 1
+    assert result == expected
+
+
+def test_cpu_count_never_returns_zero() -> None:
+    """_cpu_count should never return zero, even if _query_cpu returns zero."""
+    from pylint.lint import run as run_module
+
+    with unittest.mock.patch.object(run_module, "_query_cpu", return_value=0):
+        assert run_module._cpu_count() >= 1

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(pylint/lint/run\.py)' -m pytest --no-header -rA  -p no:cacheprovider tests/lint/unittest_lint.py
cat coverage.cover
git checkout ca80f03a43bc39e4cc2c67dc99817b3c9f13b8a6
git apply /root/pre_state.patch
