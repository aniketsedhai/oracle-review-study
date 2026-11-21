#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 429d089d0a8fbd400e0c010708df4f0d16218970 >> /root/pre_state.patch
sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 429d089d0a8fbd400e0c010708df4f0d16218970
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/tests/middleware_exceptions/middleware.py b/tests/middleware_exceptions/middleware.py
index 9fb9726..ad7cb4b 100644
--- a/tests/middleware_exceptions/middleware.py
+++ b/tests/middleware_exceptions/middleware.py
@@ -1,3 +1,4 @@
+from django.core.exceptions import MiddlewareNotUsed
 from django.http import Http404, HttpResponse
 from django.template import engines
 from django.template.response import TemplateResponse
@@ -130,3 +131,14 @@ class NotSyncOrAsyncMiddleware(BaseMiddleware):
 
     def __call__(self, request):
         return self.get_response(request)
+
+
+class SyncMiddlewareNotUsed(BaseMiddleware):
+    """Synchronous middleware that is not used."""
+    async_capable = False
+
+    def __init__(self, get_response):
+        raise MiddlewareNotUsed
+
+    def __call__(self, request):
+        return self.get_response(request)
diff --git a/tests/middleware_exceptions/tests.py b/tests/middleware_exceptions/tests.py
index 8b019ba..39894ea 100644
--- a/tests/middleware_exceptions/tests.py
+++ b/tests/middleware_exceptions/tests.py
@@ -282,6 +282,25 @@ class MiddlewareSyncAsyncTests(SimpleTestCase):
         self.assertEqual(response.content, b'OK')
         self.assertEqual(response.status_code, 200)
 
+    @override_settings(MIDDLEWARE=[
+        'middleware_exceptions.middleware.SyncMiddlewareNotUsed',
+        'middleware_exceptions.middleware.async_payment_middleware',
+    ])
+    async def test_sync_middleware_not_used_async(self):
+        # A synchronous middleware raising MiddlewareNotUsed must not poison
+        # the rest of the middleware chain in an async context (#32334).
+        response = await self.async_client.get('/middleware_exceptions/view/')
+        self.assertEqual(response.status_code, 402)
+
+    @override_settings(MIDDLEWARE=[
+        'middleware_exceptions.middleware.SyncMiddlewareNotUsed',
+        'middleware_exceptions.middleware.PaymentMiddleware',
+    ])
+    def test_sync_middleware_not_used_sync(self):
+        response = self.client.get('/middleware_exceptions/view/')
+        self.assertEqual(response.status_code, 402)
+        self.assertEqual(response.content, b'OK')
+
 
 @override_settings(ROOT_URLCONF='middleware_exceptions.urls')
 class AsyncMiddlewareTests(SimpleTestCase):

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/core/handlers/base\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 middleware_exceptions.middleware middleware_exceptions.tests
cat coverage.cover
git checkout 429d089d0a8fbd400e0c010708df4f0d16218970
git apply /root/pre_state.patch
