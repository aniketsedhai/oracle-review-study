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
index c4b39f5..0494f03 100644
--- a/tests/_core/test_scales.py
+++ b/tests/_core/test_scales.py
@@ -658,3 +658,54 @@ class TestTemporal:
         Temporal().label(concise=True)._setup(t, Coordinate(), ax.xaxis)
         formatter = ax.xaxis.get_major_formatter()
         assert isinstance(formatter, mpl.dates.ConciseDateFormatter)
+
+
+class TestContinuousLegendOffset:
+    """Regression tests for legend labels of large ranges (ScalarFormatter offset)."""
+
+    @pytest.fixture
+    def x(self):
+        return pd.Series([1e6, 2e6, 3e6], name="x", dtype=float)
+
+    def test_legend_labels_include_offset(self, x):
+
+        s = Continuous()._setup(x, Color())
+        values, labels = s._legend
+
+        # The raw values should be the actual data magnitudes
+        assert values[0] == pytest.approx(1e6)
+        assert values[-1] == pytest.approx(3e6)
+
+        # The offset must be represented somewhere in the legend labels
+        joined = " ".join(labels)
+        assert "1e6" in joined or "1E6" in joined or "10^6" in joined
+
+    def test_legend_labels_not_bare_small_numbers(self, x):
+
+        s = Continuous()._setup(x, Color())
+        _, labels = s._legend
+
+        # Without the offset, labels would be bare "1.0", "1.5", ...
+        # which misrepresents the data by six orders of magnitude.
+        assert not all(re.match(r"^\d\.\d$", label) for label in labels)
+
+    def test_legend_labels_with_offset_disabled(self, x):
+
+        with mpl.rc_context({"axes.formatter.useoffset": False}):
+            s = Continuous()._setup(x, Color())
+            _, labels = s._legend
+
+        # With offsets disabled, labels should carry the full magnitude
+        assert any("e+06" in label.lower() or "1e6" in label.lower()
+                   or "1000000" in label for label in labels)
+
+    def test_legend_labels_small_range_unaffected(self):
+
+        x = pd.Series([1.0, 2.0, 3.0], name="x", dtype=float)
+        s = Continuous()._setup(x, Color())
+        values, labels = s._legend
+
+        assert values[0] == pytest.approx(1.0)
+        assert values[-1] == pytest.approx(3.0)
+        for label in labels:
+            assert re.match(r"^\d(\.\d)?$", label)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(seaborn/_core/scales\.py|seaborn/utils\.py)' -m pytest --no-header -rA tests/_core/test_scales.py
cat coverage.cover
git checkout 22cdfb0c93f8ec78492d87edb810f10cb7f57a31
git apply /root/pre_state.patch
