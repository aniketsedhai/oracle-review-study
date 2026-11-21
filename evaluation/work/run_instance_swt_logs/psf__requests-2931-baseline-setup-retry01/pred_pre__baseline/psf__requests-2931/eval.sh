#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 5f7a3a74aab1625c2bb65f643197ee885e3da576 >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 5f7a3a74aab1625c2bb65f643197ee885e3da576
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install .
git apply -v - <<'EOF_114329324912'
diff --git a/test_requests.py b/test_requests.py
index 137edc0..b906ac9 100755
--- a/test_requests.py
+++ b/test_requests.py
@@ -1699,6 +1699,42 @@ def test_prepared_request_complete_copy():
     assert_copy(p, p.copy())
 
 
+def test_prepare_binary_string_payload():
+    """A bytes payload must be passed through unchanged (issue #2844)."""
+    payload = u('ööö').encode('utf-8')
+    p = PreparedRequest()
+    p.prepare(
+        method='PUT',
+        url='http://www.example.com',
+        data=payload,
+    )
+    assert p.body == payload
+
+
+def test_prepare_unicode_string_payload():
+    """A native (unicode) string payload must be preserved as-is."""
+    payload = u('ööö')
+    p = PreparedRequest()
+    p.prepare(
+        method='PUT',
+        url='http://www.example.com',
+        data=payload,
+    )
+    assert p.body == payload
+
+
+def test_prepare_ascii_binary_string_payload():
+    """An ASCII-only bytes payload must also be passed through unchanged."""
+    payload = b'hello world'
+    p = PreparedRequest()
+    p.prepare(
+        method='PUT',
+        url='http://www.example.com',
+        data=payload,
+    )
+    assert p.body == payload
+
+
 def test_prepare_unicode_url():
     p = PreparedRequest()
     p.prepare(

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(requests/models\.py)' -m pytest --no-header -rA  -p no:cacheprovider test_requests.py
cat coverage.cover
git checkout 5f7a3a74aab1625c2bb65f643197ee885e3da576
git apply /root/pre_state.patch
