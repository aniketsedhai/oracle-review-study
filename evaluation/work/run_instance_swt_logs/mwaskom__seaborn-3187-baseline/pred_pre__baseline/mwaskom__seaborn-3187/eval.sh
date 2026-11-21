#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 22cdfb0c93f8ec78492d87edb810f10cb7f57a31 >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 22cdfb0c93f8ec78492d87edb810f10cb7f57a31
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .[dev]
git apply -v - <<'EOF_114329324912'
diff --git a/tests/_core/test_scales.py b/tests/_core/test_scales.py
index c4b39f5..ddd7c3e 100644
--- a/tests/_core/test_scales.py
+++ b/tests/_core/test_scales.py
@@ -658,3 +658,31 @@ class TestTemporal:
         Temporal().label(concise=True)._setup(t, Coordinate(), ax.xaxis)
         formatter = ax.xaxis.get_major_formatter()
         assert isinstance(formatter, mpl.dates.ConciseDateFormatter)
+
+
+class TestContinuousLegendOffset:
+
+    @pytest.fixture
+    def x(self):
+        return pd.Series([1e6, 2e6, 3e6], name="x", dtype=float)
+
+    def test_legend_includes_offset(self, x):
+
+        s = Continuous()._setup(x, IntervalProperty())
+        values, labels = s._legend
+        # The offset must be represented in the legend labels
+        assert any("1e6" in label for label in labels)
+
+    def test_legend_labels_are_not_bare(self, x):
+
+        s = Continuous()._setup(x, IntervalProperty())
+        values, labels = s._legend
+        # Without the offset, labels would be e.g. "1.0", "1.5", ...
+        assert labels != ["1.0", "1.5", "2.0", "2.5", "3.0"]
+
+    def test_legend_offset_respects_rcparam(self, x):
+
+        with mpl.rc_context({"axes.formatter.useoffset": False}):
+            s = Continuous()._setup(x, IntervalProperty())
+            values, labels = s._legend
+        assert not any("1e6" in label for label in labels)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(seaborn/_core/scales\.py|seaborn/utils\.py)' -m pytest --no-header -rA tests/_core/test_scales.py
cat coverage.cover
git checkout 22cdfb0c93f8ec78492d87edb810f10cb7f57a31
git apply /root/pre_state.patch
