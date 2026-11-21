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
index a8f4e11..7ed9eba 100644
--- a/astropy/io/fits/tests/test_header.py
+++ b/astropy/io/fits/tests/test_header.py
@@ -3176,3 +3176,44 @@ def test_subclass():
     assert copy_.comments["c"] == "no comment"
     my_header.extend((("d", 4.0),))
     assert my_header.comments["d"] == "no comment"
+
+
+def test_float_card_uses_shortest_representation():
+    """Regression test for a Card using an unnecessarily long float repr.
+
+    A float value that has a short, exact string representation should be
+    written using that representation rather than an expanded one, so that
+    the comment is not truncated.
+    """
+    c = fits.Card(
+        "HIERARCH ESO IFM CL RADIUS",
+        0.009125,
+        "[m] radius arround actuator to avoid",
+    )
+    assert str(c) == _pad(
+        "HIERARCH ESO IFM CL RADIUS = 0.009125 / [m] radius arround actuator to avoid"
+    )
+    assert c.value == 0.009125
+    assert c.comment == "[m] radius arround actuator to avoid"
+
+
+def test_float_card_roundtrip_short_representation():
+    """A Card created from a value should round-trip through its string form."""
+    c = fits.Card("HIERARCH ESO IFM CL RADIUS", 0.009125, "comment")
+    c2 = fits.Card.fromstring(str(c))
+    assert c2.value == 0.009125
+    assert c2.comment == "comment"
+    assert str(c2) == str(c)
+
+
+@pytest.mark.parametrize(
+    "value",
+    [0.009125, 0.1, 0.5, 1.5, 3.14159, 1.2345678901234e10],
+)
+def test_float_card_short_values_fit(value):
+    """Short float values should be written without unnecessary expansion."""
+    c = fits.Card("TEST", value)
+    # The value string should be the shortest repr when it fits in 20 chars.
+    value_str = str(c)[10:30].strip()
+    assert value_str == str(value)
+    assert fits.Card.fromstring(str(c)).value == value

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(astropy/io/fits/card\.py)' -m pytest --no-header -rA  -p no:cacheprovider astropy/io/fits/tests/test_header.py
cat coverage.cover
git checkout a3f4ae6cd24d5ecdf49f213d77b3513dd509a06c
git apply /root/pre_state.patch
