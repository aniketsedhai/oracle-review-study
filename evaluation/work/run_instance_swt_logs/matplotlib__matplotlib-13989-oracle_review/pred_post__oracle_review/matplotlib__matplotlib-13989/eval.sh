#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD a3e2897bfaf9eaac1d6649da535c4e721c89fa69 >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff a3e2897bfaf9eaac1d6649da535c4e721c89fa69
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/lib/matplotlib/axes/_axes.py b/lib/matplotlib/axes/_axes.py
--- a/lib/matplotlib/axes/_axes.py
+++ b/lib/matplotlib/axes/_axes.py
@@ -6686,7 +6686,7 @@ def hist(self, x, bins=None, range=None, density=None, weights=None,
 
         density = bool(density) or bool(normed)
         if density and not stacked:
-            hist_kwargs = dict(density=density)
+            hist_kwargs['density'] = density
 
         # List to store all the top coordinates of the histograms
         tops = []

EOF_114329324912
git apply -v - <<'EOF_114329324912'
diff --git a/lib/matplotlib/tests/test_axes.py b/lib/matplotlib/tests/test_axes.py
index cff4325..fc20da4 100644
--- a/lib/matplotlib/tests/test_axes.py
+++ b/lib/matplotlib/tests/test_axes.py
@@ -6369,3 +6369,31 @@ def test_hist_nan_data():
 
     assert np.allclose(bins, nanbins)
     assert np.allclose(edges, nanedges)
+
+
+def test_hist_range_density():
+    # Test that the range argument is respected when density=True.
+    # https://github.com/matplotlib/matplotlib/issues/13804
+    rng = np.random.RandomState(19680801)
+    data = rng.rand(10)
+    for bins in ['auto', 5]:
+        mpl_heights, bin_edges, _ = plt.hist(data, bins, range=(0, 1),
+                                             density=True)
+        assert bin_edges[0] == 0
+        assert bin_edges[-1] == 1
+        np_heights, np_edges = np.histogram(data, bins, range=(0, 1),
+                                            density=True)
+        assert_allclose(bin_edges, np_edges)
+        assert_allclose(mpl_heights, np_heights)
+
+
+def test_hist_range_density_multiple_datasets():
+    # Test that the range argument is respected when density=True and
+    # multiple datasets are passed.
+    rng = np.random.RandomState(19680801)
+    data = [rng.rand(10), rng.rand(20)]
+    _, bin_edges, _ = plt.hist(data, 'auto', range=(0, 1), density=True)
+    assert bin_edges[0] == 0
+    assert bin_edges[-1] == 1
+    np_edges = np.histogram(np.concatenate(data), 'auto', range=(0, 1))[1]
+    assert_allclose(bin_edges, np_edges)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(lib/matplotlib/axes/_axes\.py)' -m pytest --no-header -rA  -p no:cacheprovider lib/matplotlib/tests/test_axes.py
cat coverage.cover
git checkout a3e2897bfaf9eaac1d6649da535c4e721c89fa69
git apply /root/pre_state.patch
