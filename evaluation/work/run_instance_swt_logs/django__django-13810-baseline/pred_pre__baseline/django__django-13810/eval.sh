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
index 9fb9726..28b9b81 100644
--- a/tests/middleware_exceptions/middleware.py
+++ b/tests/middleware_exceptions/middleware.py
@@ -1,3 +1,4 @@
+from django.core.exceptions import MiddlewareNotUsed
 from django.http import Http404, HttpResponse
 from django.template import engines
 from django.template.response import TemplateResponse
@@ -130,3 +131,24 @@ class NotSyncOrAsyncMiddleware(BaseMiddleware):
 
     def __call__(self, request):
         return self.get_response(request)
+
+
+class SyncMiddlewareNotUsed(BaseMiddleware):
+    """Synchronous-only middleware that raises MiddlewareNotUsed."""
+    sync_capable = True
+    async_capable = False
+
+    def __init__(self, get_response):
+        raise MiddlewareNotUsed
+
+    def __call__(self, request):
+        return self.get_response(request)
+
+
+@async_only_middleware
+class AsyncMiddleware(BaseMiddleware):
+    """Asynchronous-only middleware that marks the response."""
+    async def __call__(self, request):
+        response = await self.get_response(request)
+        response.status_code = 402
+        return response
diff --git a/tests/middleware_exceptions/tests.py b/tests/middleware_exceptions/tests.py
index 8b019ba..389403b 100644
--- a/tests/middleware_exceptions/tests.py
+++ b/tests/middleware_exceptions/tests.py
@@ -339,3 +339,34 @@ class AsyncMiddlewareTests(SimpleTestCase):
     async def test_process_view_return_response(self):
         response = await self.async_client.get('/middleware_exceptions/view/')
         self.assertEqual(response.content, b'Processed view normal_view')
+
+
+@override_settings(ROOT_URLCONF='middleware_exceptions.urls')
+class MiddlewareNotUsedAsyncTests(SimpleTestCase):
+    """
+    MiddlewareNotUsed raised while loading a sync-only middleware in an async
+    context must not leave the handler adapted to the wrong mode (#32334).
+    """
+    @override_settings(MIDDLEWARE=[
+        'middleware_exceptions.middleware.SyncMiddlewareNotUsed',
+        'middleware_exceptions.middleware.AsyncMiddleware',
+    ])
+    async def test_sync_middleware_not_used_does_not_poison_chain(self):
+        response = await self.async_client.get('/middleware_exceptions/view/')
+        self.assertEqual(response.status_code, 402)
+
+    @override_settings(MIDDLEWARE=[
+        'middleware_exceptions.middleware.SyncMiddlewareNotUsed',
+        'middleware_exceptions.middleware.AsyncMiddleware',
+    ])
+    def test_sync_middleware_not_used_does_not_poison_chain_sync(self):
+        response = self.client.get('/middleware_exceptions/view/')
+        self.assertEqual(response.status_code, 402)
+
+    @override_settings(MIDDLEWARE=[
+        'middleware_exceptions.middleware.SyncMiddlewareNotUsed',
+        'middleware_exceptions.middleware.PaymentMiddleware',
+    ])
+    async def test_sync_middleware_not_used_then_sync_middleware(self):
+        response = await self.async_client.get('/middleware_exceptions/view/')
+        self.assertEqual(response.status_code, 402)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/core/handlers/base\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 middleware_exceptions.middleware middleware_exceptions.tests
cat coverage.cover
git checkout 429d089d0a8fbd400e0c010708df4f0d16218970
git apply /root/pre_state.patch
