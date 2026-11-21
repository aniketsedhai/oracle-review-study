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
diff --git a/tests/_core/test_plot.py b/tests/_core/test_plot.py
index e4ba99e..d199c9a 100644
--- a/tests/_core/test_plot.py
+++ b/tests/_core/test_plot.py
@@ -2057,3 +2057,46 @@ class TestDefaultObject:
     def test_default_repr(self):
 
         assert repr(Default()) == "<default>"
+
+
+class TestLegendOffset:
+
+    @pytest.fixture
+    def xy(self):
+        return dict(x=[1, 2, 3, 4], y=[1, 2, 3, 4])
+
+    def test_continuous_legend_offset_in_title(self, xy):
+
+        # https://github.com/mwaskom/seaborn/issues/3151
+        s = pd.Series([1e6, 2e6, 3e6, 4e6], name="s")
+        p = Plot(**xy, pointsize=s).add(MockMark()).plot()
+        legend, = p._figure.legends
+        title = legend.get_title().get_text()
+        assert "1e6" in title
+
+    def test_continuous_legend_offset_labels(self, xy):
+
+        s = pd.Series([1e6, 2e6, 3e6, 4e6], name="s")
+        p = Plot(**xy, pointsize=s).add(MockMark()).plot()
+        legend, = p._figure.legends
+        labels = [t.get_text() for t in legend.get_texts()]
+        # The offset should not be duplicated in the labels
+        for label in labels:
+            assert "1e6" not in label
+
+    def test_continuous_legend_no_offset_small_range(self, xy):
+
+        s = pd.Series([1, 2, 3, 4], name="s")
+        p = Plot(**xy, pointsize=s).add(MockMark()).plot()
+        legend, = p._figure.legends
+        title = legend.get_title().get_text()
+        assert title == "s"
+
+    def test_continuous_legend_offset_respects_rcparam(self, xy):
+
+        s = pd.Series([1e6, 2e6, 3e6, 4e6], name="s")
+        with mpl.rc_context({"axes.formatter.useoffset": False}):
+            p = Plot(**xy, pointsize=s).add(MockMark()).plot()
+        legend, = p._figure.legends
+        title = legend.get_title().get_text()
+        assert "1e6" not in title

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(seaborn/_core/scales\.py|seaborn/utils\.py)' -m pytest --no-header -rA tests/_core/test_plot.py
cat coverage.cover
git checkout 22cdfb0c93f8ec78492d87edb810f10cb7f57a31
git apply /root/pre_state.patch
