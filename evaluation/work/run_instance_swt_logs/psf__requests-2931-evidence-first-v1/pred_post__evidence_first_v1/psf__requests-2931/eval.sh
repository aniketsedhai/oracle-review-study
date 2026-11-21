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
diff --git a/requests/models.py b/requests/models.py
--- a/requests/models.py
+++ b/requests/models.py
@@ -81,7 +81,7 @@ def _encode_params(data):
         """
 
         if isinstance(data, (str, bytes)):
-            return to_native_string(data)
+            return data
         elif hasattr(data, 'read'):
             return data
         elif hasattr(data, '__iter__'):
@@ -385,6 +385,9 @@ def prepare_url(self, url, params):
             if isinstance(fragment, str):
                 fragment = fragment.encode('utf-8')
 
+        if isinstance(params, (str, bytes)):
+            params = to_native_string(params)
+
         enc_params = self._encode_params(params)
         if enc_params:
             if query:

EOF_114329324912
git apply -v - <<'EOF_114329324912'
diff --git a/test_requests.py b/test_requests.py
index 137edc0..10daf95 100755
--- a/test_requests.py
+++ b/test_requests.py
@@ -1666,6 +1666,22 @@ def test_data_argument_accepts_tuples(list_of_tuples):
         assert p.body == urlencode(data)
 
 
+def test_binary_data_payload_prepares_without_error():
+    """
+    A request with a binary (non-ASCII bytes) payload should be prepared
+    without raising, preserving the bytes as the request body.
+    """
+    payload = u('ööö').encode('utf-8')
+    p = PreparedRequest()
+    p.prepare(
+        method='PUT',
+        url='http://www.example.com',
+        data=payload,
+        hooks=default_hooks()
+    )
+    assert p.body == payload
+
+
 def assert_copy(p, p_copy):
     for attr in ('method', 'url', 'headers', '_cookies', 'body', 'hooks'):
         assert getattr(p, attr) == getattr(p_copy, attr)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(requests/models\.py)' -m pytest --no-header -rA  -p no:cacheprovider test_requests.py
cat coverage.cover
git checkout 5f7a3a74aab1625c2bb65f643197ee885e3da576
git apply /root/pre_state.patch
