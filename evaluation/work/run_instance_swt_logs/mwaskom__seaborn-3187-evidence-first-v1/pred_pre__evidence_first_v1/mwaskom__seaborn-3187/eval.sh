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
index c4b39f5..c62db0d 100644
--- a/tests/_core/test_scales.py
+++ b/tests/_core/test_scales.py
@@ -658,3 +658,21 @@ class TestTemporal:
         Temporal().label(concise=True)._setup(t, Coordinate(), ax.xaxis)
         formatter = ax.xaxis.get_major_formatter()
         assert isinstance(formatter, mpl.dates.ConciseDateFormatter)
+
+
+class TestContinuousLegendOffset:
+
+    def test_legend_labels_include_scalar_offset(self):
+
+        # Large values formatted by ScalarFormatter use a multiplicative offset
+        # (e.g. "1e6"); the legend labels must reflect that offset rather than
+        # showing bare mantissas like "1.0", "1.5", ...
+        x = pd.Series([1e6, 2e6, 3e6], name="x")
+        s = Continuous()._setup(x, Color())
+        values, labels = s._legend
+
+        assert values == [1e6, 1.5e6, 2e6, 2.5e6, 3e6]
+        # Each label should carry the offset information (either as a
+        # multiplicative factor or as the full value), not just "1.0" etc.
+        for label, value in zip(labels, values):
+            assert label != f"{value / 1e6:.1f}"

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(seaborn/_core/scales\.py|seaborn/utils\.py)' -m pytest --no-header -rA tests/_core/test_scales.py
cat coverage.cover
git checkout 22cdfb0c93f8ec78492d87edb810f10cb7f57a31
git apply /root/pre_state.patch
