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
diff --git a/tests/middleware_exceptions/middleware.py b/tests/middleware_exceptions/middleware.py
index 9fb9726..e1aec88 100644
--- a/tests/middleware_exceptions/middleware.py
+++ b/tests/middleware_exceptions/middleware.py
@@ -130,3 +130,9 @@ class NotSyncOrAsyncMiddleware(BaseMiddleware):
 
     def __call__(self, request):
         return self.get_response(request)
+
+
+class ProcessResponseMiddleware(BaseMiddleware):
+    def process_response(self, request, response):
+        log.append(response)
+        return response
diff --git a/tests/middleware_exceptions/tests.py b/tests/middleware_exceptions/tests.py
index 8b019ba..3a7013c 100644
--- a/tests/middleware_exceptions/tests.py
+++ b/tests/middleware_exceptions/tests.py
@@ -339,3 +339,16 @@ class AsyncMiddlewareTests(SimpleTestCase):
     async def test_process_view_return_response(self):
         response = await self.async_client.get('/middleware_exceptions/view/')
         self.assertEqual(response.content, b'Processed view normal_view')
+
+    @override_settings(MIDDLEWARE=[
+        'middleware_exceptions.middleware.ProcessResponseMiddleware',
+        'django.middleware.security.SecurityMiddleware',
+    ])
+    async def test_first_middleware_process_response_receives_response(self):
+        """
+        The first middleware in the stack receives an HttpResponse (not a
+        coroutine) in process_response() when handling an async request.
+        """
+        response = await self.async_client.get('/middleware_exceptions/view/')
+        self.assertEqual(response.content, b'OK')
+        self.assertIsInstance(mw.log[0], HttpResponse)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/sessions/middleware\.py|django/middleware/cache\.py|django/middleware/security\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 middleware_exceptions.middleware middleware_exceptions.tests
cat coverage.cover
git checkout e39e727ded673e74016b5d3658d23cbe20234d11
git apply /root/pre_state.patch
