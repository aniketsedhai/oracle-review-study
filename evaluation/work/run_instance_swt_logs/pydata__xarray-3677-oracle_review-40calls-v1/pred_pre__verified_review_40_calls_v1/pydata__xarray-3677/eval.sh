#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD ef6e6a7b86f8479b9a1fecf15ad5b88a2326b31e >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff ef6e6a7b86f8479b9a1fecf15ad5b88a2326b31e
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/xarray/tests/test_merge.py b/xarray/tests/test_merge.py
index c1e6c7a..ff2a10b 100644
--- a/xarray/tests/test_merge.py
+++ b/xarray/tests/test_merge.py
@@ -159,6 +159,48 @@ class TestMergeMethod:
         with raises_regex(ValueError, "should be coordinates or not"):
             data.merge(data.reset_coords())
 
+    def test_merge_dataarray(self):
+        ds = xr.Dataset({"a": 0})
+        da = xr.DataArray(1, name="b")
+        expected = xr.merge([ds, da])
+        actual = ds.merge(da)
+        assert expected.identical(actual)
+        assert actual.identical(xr.Dataset({"a": 0, "b": 1}))
+
+    def test_merge_dataarray_with_dims(self):
+        ds = xr.Dataset({"a": ("x", [0, 1])}, coords={"x": [0, 1]})
+        da = xr.DataArray([2, 3], dims="x", coords={"x": [0, 1]}, name="b")
+        expected = xr.merge([ds, da])
+        actual = ds.merge(da)
+        assert expected.identical(actual)
+        assert actual.identical(
+            xr.Dataset({"a": ("x", [0, 1]), "b": ("x", [2, 3])}, {"x": [0, 1]})
+        )
+
+    def test_merge_dataarray_auto_align(self):
+        ds = xr.Dataset({"a": ("x", [1, 2])}, coords={"x": [0, 1]})
+        da = xr.DataArray([3, 4], dims="x", coords={"x": [1, 2]}, name="b")
+        expected = xr.Dataset(
+            {"a": ("x", [1, 2, np.nan]), "b": ("x", [np.nan, 3, 4])},
+            {"x": [0, 1, 2]},
+        )
+        assert expected.identical(ds.merge(da))
+        assert expected.identical(xr.merge([ds, da]))
+
+    def test_merge_dataarray_overwrite_vars(self):
+        ds = xr.Dataset({"a": 0})
+        da = xr.DataArray(1, name="a")
+        with pytest.raises(xr.MergeError):
+            ds.merge(da)
+        actual = ds.merge(da, overwrite_vars="a")
+        assert actual.identical(xr.Dataset({"a": 1}))
+
+    def test_merge_dataarray_unnamed(self):
+        ds = xr.Dataset({"a": 0})
+        da = xr.DataArray(1)
+        with raises_regex(ValueError, "must have a name"):
+            ds.merge(da)
+
     def test_merge_broadcast_equals(self):
         ds1 = xr.Dataset({"x": 0})
         ds2 = xr.Dataset({"x": ("y", [0, 0])})

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(xarray/core/dataset\.py)' -m pytest --no-header -rA  -p no:cacheprovider xarray/tests/test_merge.py
cat coverage.cover
git checkout ef6e6a7b86f8479b9a1fecf15ad5b88a2326b31e
git apply /root/pre_state.patch
