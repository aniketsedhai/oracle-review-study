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
diff --git a/tests/handlers/tests.py b/tests/handlers/tests.py
index 1d445cd..0480abe 100644
--- a/tests/handlers/tests.py
+++ b/tests/handlers/tests.py
@@ -1,4 +1,4 @@
-from django.core.exceptions import ImproperlyConfigured
+from django.core.exceptions import ImproperlyConfigured, MiddlewareNotUsed
 from django.core.handlers.wsgi import WSGIHandler, WSGIRequest, get_script_name
 from django.core.signals import request_finished, request_started
 from django.db import close_old_connections, connection
@@ -163,6 +163,17 @@ def empty_middleware(get_response):
     pass
 
 
+class SyncMiddlewareNotUsed:
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
 @override_settings(ROOT_URLCONF='handlers.urls')
 class HandlerRequestTests(SimpleTestCase):
     request_factory = RequestFactory()
@@ -259,6 +270,15 @@ class AsyncHandlerRequestTests(SimpleTestCase):
         response = await self.async_client.get('/async_regular/')
         self.assertEqual(response.status_code, 200)
 
+    @override_settings(MIDDLEWARE=['handlers.tests.SyncMiddlewareNotUsed'])
+    async def test_middleware_not_used_does_not_poison_async_chain(self):
+        """
+        A sync-only middleware raising MiddlewareNotUsed must not leave the
+        handler adapted for the wrong mode for the remaining middleware.
+        """
+        response = await self.async_client.get('/regular/')
+        self.assertEqual(response.status_code, 200)
+
     async def test_suspiciousop_in_view_returns_400(self):
         response = await self.async_client.get('/suspicious/')
         self.assertEqual(response.status_code, 400)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/core/handlers/base\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 handlers.tests
cat coverage.cover
git checkout 429d089d0a8fbd400e0c010708df4f0d16218970
git apply /root/pre_state.patch
