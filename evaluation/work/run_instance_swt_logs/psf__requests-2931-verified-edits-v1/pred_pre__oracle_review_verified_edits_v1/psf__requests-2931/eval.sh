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
index 137edc0..f0f2e19 100755
--- a/test_requests.py
+++ b/test_requests.py
@@ -660,6 +660,14 @@ class TestRequests(object):
         prep = s.prepare_request(req)
         assert prep.url == "https://httpbin.org/"
 
+    def test_request_with_binary_payload(self, httpbin):
+        # Regression test: a bytes payload containing non-ASCII bytes must
+        # not be passed through to_native_string (which assumes ASCII).
+        payload = u('ööö').encode('utf-8')
+        r = requests.put(httpbin('put'), data=payload)
+        assert r.status_code == 200
+        assert r.json()['data'] == payload.decode('utf-8')
+
     def test_links(self):
         r = requests.Response()
         r.headers = {
@@ -1666,6 +1674,37 @@ def test_data_argument_accepts_tuples(list_of_tuples):
         assert p.body == urlencode(data)
 
 
+def test_prepare_binary_data_payload():
+    """
+    A bytes payload containing non-ASCII bytes should be preserved verbatim
+    when preparing a request, rather than being decoded as ASCII.
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
+def test_prepare_ascii_bytes_payload():
+    """
+    A plain ASCII bytes payload should still be accepted and preserved.
+    """
+    payload = b'foo=bar'
+    p = PreparedRequest()
+    p.prepare(
+        method='POST',
+        url='http://www.example.com',
+        data=payload,
+        hooks=default_hooks()
+    )
+    assert p.body == 'foo=bar'
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
