#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 430fb1db88843300fb4baae3edc499bbfe073b0c >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 430fb1db88843300fb4baae3edc499bbfe073b0c
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/lib/matplotlib/tests/test_pickle.py b/lib/matplotlib/tests/test_pickle.py
index ec6bdcc..00a4271 100644
--- a/lib/matplotlib/tests/test_pickle.py
+++ b/lib/matplotlib/tests/test_pickle.py
@@ -282,3 +282,43 @@ def test_dynamic_norm():
 def test_vertexselector():
     line, = plt.plot([0, 1], picker=True)
     pickle.loads(pickle.dumps(VertexSelector(line)))
+
+
+def test_pickle_draggable_legend():
+    # Regression test for pickling a figure with a draggable legend.
+    # The draggable helper must not keep a reference to the (unpicklable)
+    # canvas, otherwise pickling the figure fails.
+    from matplotlib.backend_bases import FigureCanvasBase
+
+    class UnpicklableCanvas(FigureCanvasBase):
+        def __getstate__(self):
+            raise TypeError("cannot pickle 'FigureCanvasQTAgg' object")
+
+    fig, ax = plt.subplots()
+    ax.plot([0, 1, 2, 3, 4], [40, 43, 45, 47, 48], label="speed")
+    leg = ax.legend()
+    leg.set_draggable(True)
+    # Simulate a backend whose canvas cannot be pickled (e.g. QtAgg).
+    fig.set_canvas(UnpicklableCanvas(fig))
+    leg.set_draggable(False)
+    leg.set_draggable(True)
+
+    pickle.loads(pickle.dumps(fig))
+
+
+def test_pickle_draggable_annotation():
+    # Regression test for pickling a figure with a draggable annotation.
+    from matplotlib.backend_bases import FigureCanvasBase
+
+    class UnpicklableCanvas(FigureCanvasBase):
+        def __getstate__(self):
+            raise TypeError("cannot pickle 'FigureCanvasQTAgg' object")
+
+    fig, ax = plt.subplots()
+    ann = ax.annotate("foo", (0.5, 0.5))
+    ann.draggable(True)
+    fig.set_canvas(UnpicklableCanvas(fig))
+    ann.draggable(False)
+    ann.draggable(True)
+
+    pickle.loads(pickle.dumps(fig))

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(lib/matplotlib/offsetbox\.py)' -m pytest --no-header -rA  -p no:cacheprovider lib/matplotlib/tests/test_pickle.py
cat coverage.cover
git checkout 430fb1db88843300fb4baae3edc499bbfe073b0c
git apply /root/pre_state.patch
