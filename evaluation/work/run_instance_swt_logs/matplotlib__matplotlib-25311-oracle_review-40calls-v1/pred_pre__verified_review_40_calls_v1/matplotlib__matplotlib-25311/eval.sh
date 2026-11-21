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
index ec6bdcc..f44b978 100644
--- a/lib/matplotlib/tests/test_pickle.py
+++ b/lib/matplotlib/tests/test_pickle.py
@@ -282,3 +282,46 @@ def test_dynamic_norm():
 def test_vertexselector():
     line, = plt.plot([0, 1], picker=True)
     pickle.loads(pickle.dumps(VertexSelector(line)))
+
+
+def _pickle_draggable_legend_subprocess():
+    import pickle
+    import matplotlib.pyplot as plt
+
+    fig, ax = plt.subplots()
+    ax.plot([0, 1, 2], [0, 1, 2], label="speed")
+    leg = ax.legend()
+    leg.set_draggable(True)
+    pickle.dumps(fig)
+
+
+def test_pickle_draggable_legend():
+    fig, ax = plt.subplots()
+    ax.plot([0, 1, 2], [0, 1, 2], label="speed")
+    leg = ax.legend()
+    leg.set_draggable(True)
+
+    fig2 = pickle.loads(pickle.dumps(fig))
+    leg2 = fig2.axes[0].get_legend()
+    assert leg2.get_draggable()
+    # The unpickled draggable must be bound to the unpickled artist.
+    assert leg2._draggable.ref_artist is leg2
+    fig2.canvas.draw()
+
+
+def test_pickle_draggable_annotation():
+    fig, ax = plt.subplots()
+    ann = ax.annotate("foo", (0.5, 0.5))
+    ann.draggable(True)
+
+    fig2 = pickle.loads(pickle.dumps(fig))
+    ann2 = fig2.axes[0].texts[0]
+    assert ann2._draggable is not None
+    assert ann2._draggable.ref_artist is ann2
+    fig2.canvas.draw()
+
+
+def test_pickle_draggable_legend_subprocess():
+    # Pickling must also work when the figure is created with a GUI-like
+    # canvas that cannot itself be pickled (e.g. FigureCanvasQTAgg).
+    subprocess_run_helper(_pickle_draggable_legend_subprocess, timeout=60)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(lib/matplotlib/offsetbox\.py)' -m pytest --no-header -rA  -p no:cacheprovider lib/matplotlib/tests/test_pickle.py
cat coverage.cover
git checkout 430fb1db88843300fb4baae3edc499bbfe073b0c
git apply /root/pre_state.patch
