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
diff --git a/pylint/lint/run.py b/pylint/lint/run.py
--- a/pylint/lint/run.py
+++ b/pylint/lint/run.py
@@ -58,6 +58,13 @@ def _query_cpu() -> int | None:
             cpu_shares = int(file.read().rstrip())
         # For AWS, gives correct value * 1024.
         avail_cpu = int(cpu_shares / 1024)
+
+    # In K8s Pods also a fraction of a single core could be available
+    # As multiprocessing is not able to run only a "fraction" of process
+    # assume we have 1 CPU available
+    if avail_cpu == 0:
+        avail_cpu = 1
+
     return avail_cpu
 
 

EOF_114329324912
git apply -v - <<'EOF_114329324912'
diff --git a/tests/lint/test_run_pylint.py b/tests/lint/test_run_pylint.py
new file mode 100644
index 0000000..e95c298
--- /dev/null
+++ b/tests/lint/test_run_pylint.py
@@ -0,0 +1,131 @@
+# Licensed under the GPL: https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
+# For details: https://github.com/PyCQA/pylint/blob/main/LICENSE
+# Copyright (c) https://github.com/PyCQA/pylint/blob/main/CONTRIBUTORS.txt
+
+"""Tests for pylint.lint.run, in particular the CPU detection helpers."""
+
+from __future__ import annotations
+
+import os
+from pathlib import Path
+from unittest.mock import patch
+
+import pytest
+
+from pylint.lint import run as run_module
+from pylint.lint.run import _cpu_count, _query_cpu
+from pylint.testutils._run import _Run as Run
+
+
+def _write(path: Path, content: str) -> None:
+    path.write_text(content, encoding="utf-8")
+
+
+def test_query_cpu_returns_none_without_cgroup_files(tmp_path: Path) -> None:
+    """No cgroup files at all: nothing can be determined."""
+    with patch.object(run_module, "Path", return_value=tmp_path / "missing"):
+        assert _query_cpu() is None
+
+
+def test_query_cpu_quota_minus_one_falls_back_to_shares(tmp_path: Path) -> None:
+    """AWS Batch style: quota is -1, so cpu.shares is used instead."""
+    quota = tmp_path / "cpu.cfs_quota_us"
+    period = tmp_path / "cpu.cfs_period_us"
+    shares = tmp_path / "cpu.shares"
+    _write(quota, "-1\n")
+    _write(period, "100000\n")
+    _write(shares, "2048\n")
+
+    def fake_path(value: str) -> Path:
+        return {
+            "/sys/fs/cgroup/cpu/cpu.cfs_quota_us": quota,
+            "/sys/fs/cgroup/cpu/cpu.cfs_period_us": period,
+            "/sys/fs/cgroup/cpu/cpu.shares": shares,
+        }.get(value, Path("/nonexistent"))
+
+    with patch.object(run_module, "Path", side_effect=fake_path), patch.object(
+        run_module, "open", create=True
+    ) as mock_open:
+        mock_open.side_effect = lambda value, *args, **kwargs: open(  # noqa
+            fake_path(value), *args, **kwargs
+        )
+        result = _query_cpu()
+    assert result == 2
+
+
+def test_query_cpu_quota_and_period(tmp_path: Path) -> None:
+    """A valid quota/period pair is used to compute the available CPUs."""
+    quota = tmp_path / "cpu.cfs_quota_us"
+    period = tmp_path / "cpu.cfs_period_us"
+    _write(quota, "200000\n")
+    _write(period, "100000\n")
+
+    def fake_path(value: str) -> Path:
+        return {
+            "/sys/fs/cgroup/cpu/cpu.cfs_quota_us": quota,
+            "/sys/fs/cgroup/cpu/cpu.cfs_period_us": period,
+        }.get(value, Path("/nonexistent"))
+
+    with patch.object(run_module, "Path", side_effect=fake_path), patch.object(
+        run_module, "open", create=True
+    ) as mock_open:
+        mock_open.side_effect = lambda value, *args, **kwargs: open(  # noqa
+            fake_path(value), *args, **kwargs
+        )
+        result = _query_cpu()
+    assert result == 2
+
+
+def test_query_cpu_never_returns_zero_for_small_shares(tmp_path: Path) -> None:
+    """Regression test: cpu.shares of 2 used to yield 0 (2 // 1024)."""
+    quota = tmp_path / "cpu.cfs_quota_us"
+    period = tmp_path / "cpu.cfs_period_us"
+    shares = tmp_path / "cpu.shares"
+    _write(quota, "-1\n")
+    _write(period, "100000\n")
+    _write(shares, "2\n")
+
+    def fake_path(value: str) -> Path:
+        return {
+            "/sys/fs/cgroup/cpu/cpu.cfs_quota_us": quota,
+            "/sys/fs/cgroup/cpu/cpu.cfs_period_us": period,
+            "/sys/fs/cgroup/cpu/cpu.shares": shares,
+        }.get(value, Path("/nonexistent"))
+
+    with patch.object(run_module, "Path", side_effect=fake_path), patch.object(
+        run_module, "open", create=True
+    ) as mock_open:
+        mock_open.side_effect = lambda value, *args, **kwargs: open(  # noqa
+            fake_path(value), *args, **kwargs
+        )
+        result = _query_cpu()
+    assert result is not None
+    assert result >= 1
+
+
+def test_cpu_count_never_returns_zero() -> None:
+    """_cpu_count must always return a usable (>= 1) number of processes."""
+    with patch.object(run_module, "_query_cpu", return_value=0):
+        assert _cpu_count() >= 1
+
+
+def test_cpu_count_uses_query_cpu_when_smaller() -> None:
+    with patch.object(run_module, "_query_cpu", return_value=1), patch.object(
+        os, "sched_getaffinity", return_value={0, 1, 2, 3}, create=True
+    ):
+        assert _cpu_count() == 1
+
+
+def test_run_with_jobs_zero_does_not_crash(tmp_path: Path) -> None:
+    """Regression test: --jobs=0 must not crash when CPU detection yields 0."""
+    module = tmp_path / "my_module.py"
+    _write(module, "import os\n")
+
+    with patch.object(run_module, "_query_cpu", return_value=0), patch(
+        "pylint.lint.pylinter.check_parallel"
+    ) as mock_check_parallel:
+        Run([str(module), "--jobs=0", "--exit-zero"], exit=False)
+    # The number of jobs handed to multiprocessing must be at least 1.
+    mock_check_parallel.assert_called_once()
+    jobs = mock_check_parallel.call_args[0][1]
+    assert jobs >= 1

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(pylint/lint/run\.py)' -m pytest --no-header -rA  -p no:cacheprovider tests/lint/test_run_pylint.py
cat coverage.cover
git checkout ca80f03a43bc39e4cc2c67dc99817b3c9f13b8a6
git apply /root/pre_state.patch
