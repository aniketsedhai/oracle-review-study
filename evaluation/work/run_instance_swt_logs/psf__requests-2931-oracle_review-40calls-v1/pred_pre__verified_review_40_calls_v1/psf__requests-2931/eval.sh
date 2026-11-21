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
index 137edc0..c089b23 100755
--- a/test_requests.py
+++ b/test_requests.py
@@ -1666,6 +1666,50 @@ def test_data_argument_accepts_tuples(list_of_tuples):
         assert p.body == urlencode(data)
 
 
+def test_prepare_binary_string_payload():
+    """Ensure that a binary (non-ASCII bytes) payload is passed through
+    unchanged when preparing a request.
+
+    Regression test for the bug where a request with a binary payload
+    failed because ``to_native_string`` attempted to decode the bytes as
+    ASCII.
+    """
+    payload = u('ööö').encode('utf-8')
+    p = PreparedRequest()
+    p.prepare(
+        method='PUT',
+        url='http://www.example.com/put',
+        data=payload,
+        hooks=default_hooks()
+    )
+    assert p.body == payload
+    # The body must be sent as-is: the Content-Length must reflect the
+    # number of bytes actually transmitted, not a decoded character count.
+    assert p.headers['Content-Length'] == str(len(payload))
+
+
+def test_prepare_binary_string_payload_via_request():
+    """A ``Request`` with a binary payload should prepare without error and
+    preserve the exact bytes in the body."""
+    payload = u('ööö').encode('utf-8')
+    req = requests.Request('PUT', 'http://www.example.com/put', data=payload)
+    prep = req.prepare()
+    assert prep.body == payload
+    assert prep.headers['Content-Length'] == str(len(payload))
+
+
+def test_prepare_ascii_string_payload():
+    """An ASCII ``str`` payload should still be accepted and preserved."""
+    p = PreparedRequest()
+    p.prepare(
+        method='POST',
+        url='http://www.example.com/post',
+        data='hello world',
+        hooks=default_hooks()
+    )
+    assert p.body == 'hello world'
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
