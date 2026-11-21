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
diff --git a/tests/middleware/tests.py b/tests/middleware/tests.py
index 14c9284..013d846 100644
--- a/tests/middleware/tests.py
+++ b/tests/middleware/tests.py
@@ -19,6 +19,7 @@ from django.middleware.common import (
 from django.middleware.gzip import GZipMiddleware
 from django.middleware.http import ConditionalGetMiddleware
 from django.test import RequestFactory, SimpleTestCase, override_settings
+from django.utils.deprecation import MiddlewareMixin
 
 int2byte = struct.Struct(">B").pack
 
@@ -953,3 +954,25 @@ class ETagGZipMiddlewareTest(SimpleTestCase):
         next_request = self.rf.get('/', HTTP_ACCEPT_ENCODING='gzip, deflate', HTTP_IF_NONE_MATCH=gzip_etag)
         next_response = ConditionalGetMiddleware(get_response)(next_request)
         self.assertEqual(next_response.status_code, 304)
+
+
+class AsyncMiddlewareMixinResponseTests(SimpleTestCase):
+    """The first middleware receives an HttpResponse, not a coroutine."""
+
+    async def test_first_middleware_process_response_receives_response(self):
+        received = []
+
+        class DummyMiddleware(MiddlewareMixin):
+            def process_response(self, request, response):
+                received.append(response)
+                return response
+
+        async def get_response(request):
+            return HttpResponse('ok')
+
+        middleware = DummyMiddleware(get_response)
+        request = RequestFactory().get('/')
+        response = await middleware(request)
+        self.assertIsInstance(response, HttpResponse)
+        self.assertEqual(len(received), 1)
+        self.assertIsInstance(received[0], HttpResponse)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/sessions/middleware\.py|django/middleware/cache\.py|django/middleware/security\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 middleware.tests
cat coverage.cover
git checkout e39e727ded673e74016b5d3658d23cbe20234d11
git apply /root/pre_state.patch
