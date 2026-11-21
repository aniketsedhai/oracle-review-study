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
index a8f4e11..4da6e80 100644
--- a/astropy/io/fits/tests/test_header.py
+++ b/astropy/io/fits/tests/test_header.py
@@ -147,6 +147,73 @@ class TestHeaderFunctions(FitsTestCase):
         if str(c) != f1 and str(c) != f2:
             assert str(c) == f3
 
+    def test_float_value_card_uses_shortest_representation(self):
+        """
+        Regression test for a bug where ``Card`` would use an unnecessarily
+        long string representation of a float value, which could force the
+        comment to be truncated.
+
+        The value ``0.009125`` is exactly representable as a float, so its
+        shortest round-tripping representation (``"0.009125"``) should be
+        used instead of an expanded form such as ``"0.009124999999999999"``.
+        """
+        c = fits.Card(
+            "HIERARCH ESO IFM CL RADIUS",
+            0.009125,
+            "[m] radius arround actuator to avoid",
+        )
+        assert str(c) == _pad(
+            "HIERARCH ESO IFM CL RADIUS = 0.009125"
+            " / [m] radius arround actuator to avoid"
+        )
+        assert c.value == 0.009125
+        assert c.comment == "[m] radius arround actuator to avoid"
+
+    def test_float_value_card_roundtrip_shortest_representation(self):
+        """
+        A ``Card`` created from a float value should be able to be re-read
+        without changing the value, and the value string should be no longer
+        than the shortest representation that round-trips.
+        """
+        for value in (0.009125, 0.1, 1.5, -2.25, 1e-10, 123456.789):
+            c = fits.Card("TEST", value)
+            # The value field occupies columns 10-30 (0-indexed 10:30) and is
+            # right-justified, so strip the padding to get the value string.
+            value_str = str(c)[10:30].strip()
+            # The value string must round-trip to the original value.
+            assert float(value_str) == value
+            # And it should not be longer than the shortest repr.
+            assert len(value_str) <= len(repr(value))
+
+    def test_float_value_card_comment_not_truncated(self):
+        """
+        A card whose value has a short representation should not have its
+        comment truncated, even if the expanded representation would have
+        been too long.
+        """
+        comment = "[m] radius arround actuator to avoid"
+        c = fits.Card("HIERARCH ESO IFM CL RADIUS", 0.009125, comment)
+        with warnings.catch_warnings():
+            warnings.simplefilter("error", VerifyWarning)
+            # Accessing the card image must not emit a truncation warning.
+            image = str(c)
+        assert image.startswith("HIERARCH ESO IFM CL RADIUS = 0.009125 / ")
+        assert comment in image
+
+    def test_float_value_card_from_string_preserved(self):
+        """
+        Reading a card from a string and re-creating it from its
+        keyword/value/comment should produce the same card image.
+        """
+        original = fits.Card.fromstring(
+            "HIERARCH ESO IFM CL RADIUS = 0.009125"
+            " / [m] radius arround actuator to avoid"
+        )
+        new = fits.Card(
+            f"HIERARCH {original.keyword}", original.value, original.comment
+        )
+        assert str(new) == str(original)
+
     def test_card_image_constructed_too_long(self):
         """Test that over-long cards truncate the comment"""
 

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(astropy/io/fits/card\.py)' -m pytest --no-header -rA  -p no:cacheprovider astropy/io/fits/tests/test_header.py
cat coverage.cover
git checkout a3f4ae6cd24d5ecdf49f213d77b3513dd509a06c
git apply /root/pre_state.patch
