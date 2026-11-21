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
diff --git a/tests/middleware/test_async_response.py b/tests/middleware/test_async_response.py
new file mode 100644
index 0000000..2665310
--- /dev/null
+++ b/tests/middleware/test_async_response.py
@@ -0,0 +1,40 @@
+from django.http import HttpResponse
+from django.test import SimpleTestCase, override_settings
+from django.utils.decorators import sync_and_async_middleware
+
+log = []
+
+
+@sync_and_async_middleware
+class DummyMiddleware:
+    def __init__(self, get_response):
+        self.get_response = get_response
+
+    def __call__(self, request):
+        response = self.get_response(request)
+        log.append(('sync', type(response)))
+        return response
+
+    async def __acall__(self, request):
+        response = await self.get_response(request)
+        log.append(('async', type(response)))
+        return response
+
+
+@override_settings(
+    ROOT_URLCONF='middleware.urls',
+    MIDDLEWARE=['middleware.test_async_response.DummyMiddleware'],
+)
+class AsyncResponseMiddlewareTests(SimpleTestCase):
+    def tearDown(self):
+        log.clear()
+
+    async def test_first_middleware_receives_http_response(self):
+        """
+        The first middleware in the stack receives an HttpResponse (not a
+        coroutine) as its response when running on the async path.
+        """
+        response = await self.async_client.get('/slash/')
+        self.assertEqual(response.status_code, 200)
+        self.assertEqual(len(log), 1)
+        self.assertIsInstance(log[0][1], HttpResponse)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/middleware/cache\.py|django/contrib/sessions/middleware\.py|django/middleware/security\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 middleware.test_async_response
cat coverage.cover
git checkout e39e727ded673e74016b5d3658d23cbe20234d11
git apply /root/pre_state.patch
