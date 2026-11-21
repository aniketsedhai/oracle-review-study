#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD e39e727ded673e74016b5d3658d23cbe20234d11 >> /root/pre_state.patch
sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff e39e727ded673e74016b5d3658d23cbe20234d11
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/tests/deprecation/test_middleware_mixin.py b/tests/deprecation/test_middleware_mixin.py
index c90aeb8..75480ad 100644
--- a/tests/deprecation/test_middleware_mixin.py
+++ b/tests/deprecation/test_middleware_mixin.py
@@ -78,3 +78,47 @@ class MiddlewareMixinTests(SimpleTestCase):
 
         self.assertEqual(len(threads_and_connections), 4)
         self.assertEqual(len(set(threads_and_connections)), 1)
+
+
+class MiddlewareMixinAsyncResponseTests(SimpleTestCase):
+    """
+    The first middleware in the stack must receive an HttpResponse (not a
+    coroutine) in process_response() when running on the async path.
+    """
+
+    def test_process_response_receives_http_response(self):
+        seen = []
+
+        async def get_response(request):
+            return HttpResponse()
+
+        class DummyMiddleware(MiddlewareMixin):
+            def process_response(self, request, response):
+                seen.append(response)
+                return response
+
+        request = HttpRequest()
+        response = async_to_sync(DummyMiddleware(get_response))(request)
+        self.assertEqual(len(seen), 1)
+        self.assertIsInstance(seen[0], HttpResponse)
+        self.assertIs(seen[0], response)
+
+    def test_process_response_receives_http_response_with_process_request(self):
+        seen = []
+
+        async def get_response(request):
+            return HttpResponse()
+
+        class DummyMiddleware(MiddlewareMixin):
+            def process_request(self, request):
+                return None
+
+            def process_response(self, request, response):
+                seen.append(response)
+                return response
+
+        request = HttpRequest()
+        response = async_to_sync(DummyMiddleware(get_response))(request)
+        self.assertEqual(len(seen), 1)
+        self.assertIsInstance(seen[0], HttpResponse)
+        self.assertIs(seen[0], response)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/sessions/middleware\.py|django/middleware/security\.py|django/middleware/cache\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 deprecation.test_middleware_mixin
cat coverage.cover
git checkout e39e727ded673e74016b5d3658d23cbe20234d11
git apply /root/pre_state.patch
