#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD e6e300e729dd33956e5448d8be9a0b1540b4e53a >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff e6e300e729dd33956e5448d8be9a0b1540b4e53a
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/testing/test_skipping.py b/testing/test_skipping.py
index 0b1c0b4..2e3ba2e 100644
--- a/testing/test_skipping.py
+++ b/testing/test_skipping.py
@@ -1205,3 +1205,19 @@ def test_relpath_rootdir(testdir):
     result.stdout.fnmatch_lines(
         ["SKIPPED [[]1[]] tests/test_1.py:2: unconditional skip"]
     )
+
+
+def test_skip_location_with_runxfail(testdir):
+    """--runxfail should not affect the reported location of skip marks (#7435)."""
+    testdir.makepyfile(
+        """
+        import pytest
+        @pytest.mark.skip
+        def test_skip_location() -> None:
+            assert 0
+        """
+    )
+    result = testdir.runpytest("-rs", "--runxfail")
+    result.stdout.fnmatch_lines(
+        ["SKIPPED [[]1[]] test_skip_location_with_runxfail.py:2: unconditional skip"]
+    )

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(src/_pytest/skipping\.py)' -m pytest -rA testing/test_skipping.py
cat coverage.cover
git checkout e6e300e729dd33956e5448d8be9a0b1540b4e53a
git apply /root/pre_state.patch
