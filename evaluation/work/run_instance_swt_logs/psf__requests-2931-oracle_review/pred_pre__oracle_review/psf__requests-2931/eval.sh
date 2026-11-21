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
index 137edc0..83297ac 100755
--- a/test_requests.py
+++ b/test_requests.py
@@ -1107,6 +1107,17 @@ class TestRequests(object):
         prep = r.prepare()
         assert 'stuff=elixr' == prep.body
 
+    def test_binary_data_is_not_decoded(self):
+        # Regression test: a bytes payload must be passed through unchanged
+        # rather than being coerced with to_native_string (which assumes
+        # ASCII and raises UnicodeDecodeError on non-ASCII bytes).
+        payload = u('\u00f6\u00f6\u00f6').encode('utf-8')
+        r = requests.Request(method='PUT', url='http://example.com',
+                             data=payload)
+        prep = r.prepare()
+        assert prep.body == payload
+        assert isinstance(prep.body, bytes)
+
     def test_response_iter_lines(self, httpbin):
         r = requests.get(httpbin('stream/4'), stream=True)
         assert r.status_code == 200
@@ -1666,6 +1677,39 @@ def test_data_argument_accepts_tuples(list_of_tuples):
         assert p.body == urlencode(data)
 
 
+def test_prepare_binary_data_body():
+    """
+    Ensure that a bytes payload is preserved verbatim when preparing a
+    request, regardless of whether it contains non-ASCII bytes.
+    """
+    payload = u('\u00f6\u00f6\u00f6').encode('utf-8')
+    p = PreparedRequest()
+    p.prepare(
+        method='PUT',
+        url='http://www.example.com',
+        data=payload,
+        hooks=default_hooks()
+    )
+    assert p.body == payload
+    assert isinstance(p.body, bytes)
+
+
+def test_prepare_ascii_bytes_data_body():
+    """
+    Ensure that an ASCII-only bytes payload is also preserved verbatim.
+    """
+    payload = b'foo=bar'
+    p = PreparedRequest()
+    p.prepare(
+        method='POST',
+        url='http://www.example.com',
+        data=payload,
+        hooks=default_hooks()
+    )
+    assert p.body == payload
+    assert isinstance(p.body, bytes)
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
