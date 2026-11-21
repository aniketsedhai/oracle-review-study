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
index ec6bdcc..1bf4bcd 100644
--- a/lib/matplotlib/tests/test_pickle.py
+++ b/lib/matplotlib/tests/test_pickle.py
@@ -282,3 +282,37 @@ def test_dynamic_norm():
 def test_vertexselector():
     line, = plt.plot([0, 1], picker=True)
     pickle.loads(pickle.dumps(VertexSelector(line)))
+
+
+def test_draggable_legend():
+    fig, ax = plt.subplots()
+    ax.plot([0, 1], label="speed")
+    leg = ax.legend()
+    leg.set_draggable(True)
+    fig2 = pickle.loads(pickle.dumps(fig))
+    leg2 = fig2.axes[0].get_legend()
+    assert leg2.get_draggable()
+    # The unpickled draggable helper must be wired to the new figure's canvas
+    # and to the unpickled legend, so that dragging still works.
+    draggable = leg2._draggable
+    assert draggable.ref_artist is leg2
+    assert draggable.ref_artist.figure is fig2
+    assert draggable.canvas is fig2.canvas
+    # The pick/release callbacks must be registered on the new canvas.
+    for cid in draggable.cids:
+        assert any(cid in d for d in fig2.canvas.callbacks.callbacks.values())
+
+
+def test_draggable_annotation():
+    fig, ax = plt.subplots()
+    ann = ax.annotate("foo", (0.5, 0.5))
+    ann.draggable()
+    fig2 = pickle.loads(pickle.dumps(fig))
+    ann2 = fig2.axes[0].texts[0]
+    assert ann2._draggable is not None
+    draggable = ann2._draggable
+    assert draggable.ref_artist is ann2
+    assert draggable.ref_artist.figure is fig2
+    assert draggable.canvas is fig2.canvas
+    for cid in draggable.cids:
+        assert any(cid in d for d in fig2.canvas.callbacks.callbacks.values())

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(lib/matplotlib/offsetbox\.py)' -m pytest --no-header -rA  -p no:cacheprovider lib/matplotlib/tests/test_pickle.py
cat coverage.cover
git checkout 430fb1db88843300fb4baae3edc499bbfe073b0c
git apply /root/pre_state.patch
