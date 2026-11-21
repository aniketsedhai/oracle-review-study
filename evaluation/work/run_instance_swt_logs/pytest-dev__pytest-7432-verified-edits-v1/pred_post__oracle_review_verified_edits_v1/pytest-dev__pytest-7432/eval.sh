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
diff --git a/src/_pytest/skipping.py b/src/_pytest/skipping.py
--- a/src/_pytest/skipping.py
+++ b/src/_pytest/skipping.py
@@ -291,7 +291,8 @@ def pytest_runtest_makereport(item: Item, call: CallInfo[None]):
             else:
                 rep.outcome = "passed"
                 rep.wasxfail = xfailed.reason
-    elif (
+
+    if (
         item._store.get(skipped_by_mark_key, True)
         and rep.skipped
         and type(rep.longrepr) is tuple

EOF_114329324912
git apply -v - <<'EOF_114329324912'
diff --git a/testing/test_skipping.py b/testing/test_skipping.py
index 0b1c0b4..11c52ce 100644
--- a/testing/test_skipping.py
+++ b/testing/test_skipping.py
@@ -648,6 +648,30 @@ class TestSkip:
         result = testdir.runpytest("-rs")
         result.stdout.fnmatch_lines(["*unconditional skip*", "*1 skipped*"])
 
+    @pytest.mark.parametrize("runxfail", [False, True])
+    def test_skip_location(self, testdir, runxfail):
+        """Skip location should point to the test item, also with --runxfail.
+
+        Regression test: --runxfail used to make the reported skip location
+        point to pytest's internal skipping.py instead of the test file.
+        """
+        testdir.makepyfile(
+            """
+            import pytest
+            @pytest.mark.skip
+            def test_skip_location() -> None:
+                assert 0
+        """
+        )
+        args = ["-rs"]
+        if runxfail:
+            args.append("--runxfail")
+        result = testdir.runpytest(*args)
+        result.stdout.fnmatch_lines(
+            ["SKIPPED [[]1[]] test_skip_location.py:2: unconditional skip"]
+        )
+        assert result.ret == 0
+
 
 class TestSkipif:
     def test_skipif_conditional(self, testdir):
@@ -679,6 +703,30 @@ class TestSkipif:
         result.stdout.fnmatch_lines(["*SKIP*1*test_foo.py*platform*", "*1 skipped*"])
         assert result.ret == 0
 
+    @pytest.mark.parametrize("runxfail", [False, True])
+    def test_skipif_location(self, testdir, runxfail):
+        """Skipif location should point to the test item, also with --runxfail.
+
+        Regression test: --runxfail used to make the reported skip location
+        point to pytest's internal skipping.py instead of the test file.
+        """
+        testdir.makepyfile(
+            """
+            import pytest
+            @pytest.mark.skipif(True, reason="condition")
+            def test_skipif_location() -> None:
+                assert 0
+        """
+        )
+        args = ["-rs"]
+        if runxfail:
+            args.append("--runxfail")
+        result = testdir.runpytest(*args)
+        result.stdout.fnmatch_lines(
+            ["SKIPPED [[]1[]] test_skipif_location.py:2: condition"]
+        )
+        assert result.ret == 0
+
     def test_skipif_using_platform(self, testdir):
         item = testdir.getitem(
             """

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(src/_pytest/skipping\.py)' -m pytest -rA testing/test_skipping.py
cat coverage.cover
git checkout e6e300e729dd33956e5448d8be9a0b1540b4e53a
git apply /root/pre_state.patch
