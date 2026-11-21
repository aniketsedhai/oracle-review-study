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
diff --git a/tests/lint/test_run_pylint.py b/tests/lint/test_run_pylint.py
new file mode 100644
index 0000000..851ef67
--- /dev/null
+++ b/tests/lint/test_run_pylint.py
@@ -0,0 +1,130 @@
+# Licensed under the GPL: https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
+# For details: https://github.com/PyCQA/pylint/blob/main/LICENSE
+# Copyright (c) https://github.com/PyCQA/pylint/blob/main/CONTRIBUTORS.txt
+
+"""Tests for pylint.lint.run, in particular the CPU detection helpers."""
+
+from __future__ import annotations
+
+import io
+import os
+from unittest.mock import patch
+
+from pylint.lint import run as run_module
+from pylint.lint.run import _cpu_count, _query_cpu
+
+
+class _FakePath:
+    """Minimal stand-in for pathlib.Path used to fake cgroup files."""
+
+    def __init__(self, name: str, files: dict[str, str]) -> None:
+        self._name = str(name)
+        self._files = files
+
+    def is_file(self) -> bool:
+        return self._name in self._files
+
+    def __str__(self) -> str:
+        return self._name
+
+    def __fspath__(self) -> str:
+        return self._name
+
+    def __repr__(self) -> str:
+        return f"_FakePath({self._name!r})"
+
+
+def _patch_cgroup(files: dict[str, str]):
+    """Patch Path and open so that only ``files`` appear to exist."""
+
+    def _path_factory(name) -> _FakePath:
+        return _FakePath(name, files)
+
+    def _open(name, *args, **kwargs) -> io.StringIO:
+        return io.StringIO(files[str(name)])
+
+    return (
+        patch.object(run_module, "Path", _path_factory),
+        patch.object(run_module, "open", _open, create=True),
+    )
+
+
+def test_query_cpu_quota_and_period() -> None:
+    files = {
+        "/sys/fs/cgroup/cpu/cpu.cfs_quota_us": "200000\n",
+        "/sys/fs/cgroup/cpu/cpu.cfs_period_us": "100000\n",
+    }
+    path_patch, open_patch = _patch_cgroup(files)
+    with path_patch, open_patch:
+        assert _query_cpu() == 2
+
+
+def test_query_cpu_shares() -> None:
+    files = {"/sys/fs/cgroup/cpu/cpu.shares": "2048\n"}
+    path_patch, open_patch = _patch_cgroup(files)
+    with path_patch, open_patch:
+        assert _query_cpu() == 2
+
+
+def test_query_cpu_shares_rounds_down_to_zero() -> None:
+    """Regression test: a tiny cpu.shares value must not yield 0."""
+    files = {"/sys/fs/cgroup/cpu/cpu.shares": "2\n"}
+    path_patch, open_patch = _patch_cgroup(files)
+    with path_patch, open_patch:
+        result = _query_cpu()
+    assert result is not None
+    assert result >= 1
+
+
+def test_query_cpu_quota_rounds_down_to_zero() -> None:
+    """Regression test: a fractional quota must not yield 0."""
+    files = {
+        "/sys/fs/cgroup/cpu/cpu.cfs_quota_us": "50000\n",
+        "/sys/fs/cgroup/cpu/cpu.cfs_period_us": "100000\n",
+    }
+    path_patch, open_patch = _patch_cgroup(files)
+    with path_patch, open_patch:
+        result = _query_cpu()
+    assert result is not None
+    assert result >= 1
+
+
+def test_query_cpu_no_cgroup_files() -> None:
+    path_patch, open_patch = _patch_cgroup({})
+    with path_patch, open_patch:
+        assert _query_cpu() is None
+
+
+def test_cpu_count_never_zero_with_tiny_shares() -> None:
+    """Regression test for the reported crash: --jobs=0 must not resolve to 0."""
+    files = {"/sys/fs/cgroup/cpu/cpu.shares": "2\n"}
+    path_patch, open_patch = _patch_cgroup(files)
+    with path_patch, open_patch:
+        assert _cpu_count() >= 1
+
+
+def test_cpu_count_never_zero_with_fractional_quota() -> None:
+    files = {
+        "/sys/fs/cgroup/cpu/cpu.cfs_quota_us": "50000\n",
+        "/sys/fs/cgroup/cpu/cpu.cfs_period_us": "100000\n",
+    }
+    path_patch, open_patch = _patch_cgroup(files)
+    with path_patch, open_patch:
+        assert _cpu_count() >= 1
+
+
+def test_cpu_count_uses_min_of_share_and_affinity() -> None:
+    files = {"/sys/fs/cgroup/cpu/cpu.shares": "2048\n"}
+    path_patch, open_patch = _patch_cgroup(files)
+    with path_patch, open_patch, patch.object(
+        os, "sched_getaffinity", lambda _pid: {0, 1, 2, 3}, create=True
+    ):
+        assert _cpu_count() == 2
+
+
+def test_cpu_count_without_cgroup_uses_affinity() -> None:
+    path_patch, open_patch = _patch_cgroup({})
+    with path_patch, open_patch, patch.object(
+        os, "sched_getaffinity", lambda _pid: {0, 1, 2}, create=True
+    ):
+        assert _cpu_count() == 3

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(pylint/lint/run\.py)' -m pytest --no-header -rA  -p no:cacheprovider tests/lint/test_run_pylint.py
cat coverage.cover
git checkout ca80f03a43bc39e4cc2c67dc99817b3c9f13b8a6
git apply /root/pre_state.patch
