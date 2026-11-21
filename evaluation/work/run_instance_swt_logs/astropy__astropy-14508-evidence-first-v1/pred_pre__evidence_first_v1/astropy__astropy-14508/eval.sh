#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD a3f4ae6cd24d5ecdf49f213d77b3513dd509a06c >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff a3f4ae6cd24d5ecdf49f213d77b3513dd509a06c
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .[test] --verbose
git apply -v - <<'EOF_114329324912'
diff --git a/astropy/io/fits/tests/test_header.py b/astropy/io/fits/tests/test_header.py
index a8f4e11..e076745 100644
--- a/astropy/io/fits/tests/test_header.py
+++ b/astropy/io/fits/tests/test_header.py
@@ -3176,3 +3176,29 @@ def test_subclass():
     assert copy_.comments["c"] == "no comment"
     my_header.extend((("d", 4.0),))
     assert my_header.comments["d"] == "no comment"
+
+
+def test_float_value_not_expanded_unnecessarily():
+    """Regression test for a float value being expanded to a longer string
+    representation than necessary, which forced comments to be truncated.
+
+    A valid FITS card such as
+    ``HIERARCH ESO IFM CL RADIUS = 0.009125 / [m] radius arround actuator to avoid``
+    should be reproducible via ``fits.Card`` without the value being expanded
+    to ``0.009124999999999999``.
+    """
+    expected = (
+        "HIERARCH ESO IFM CL RADIUS = 0.009125 "
+        "/ [m] radius arround actuator to avoid    "
+    )
+    # Sanity check: this is a valid 80-character FITS card.
+    assert len(expected) == 80
+
+    c = fits.Card(
+        "HIERARCH ESO IFM CL RADIUS",
+        0.009125,
+        "[m] radius arround actuator to avoid",
+    )
+    assert str(c) == expected
+    assert c.value == 0.009125
+    assert c.comment == "[m] radius arround actuator to avoid"

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(astropy/io/fits/card\.py)' -m pytest --no-header -rA  -p no:cacheprovider astropy/io/fits/tests/test_header.py
cat coverage.cover
git checkout a3f4ae6cd24d5ecdf49f213d77b3513dd509a06c
git apply /root/pre_state.patch
