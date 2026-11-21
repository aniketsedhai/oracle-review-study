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
diff --git a/tests/handlers/tests.py b/tests/handlers/tests.py
index 3b655a9..bda2203 100644
--- a/tests/handlers/tests.py
+++ b/tests/handlers/tests.py
@@ -276,3 +276,32 @@ class AsyncHandlerRequestTests(SimpleTestCase):
         )
         with self.assertRaisesMessage(ValueError, msg):
             await self.async_client.get('/unawaited/')
+
+
+class AsyncMiddlewareResponseTests(SimpleTestCase):
+    """
+    The first middleware in the stack must receive an HttpResponse (not a
+    coroutine) as the response argument when running on the async path.
+    """
+    request_factory = RequestFactory()
+
+    def test_first_middleware_receives_http_response(self):
+        from django.core.handlers.asgi import ASGIHandler
+        from asgiref.sync import async_to_sync
+
+        received = []
+
+        class DummyMiddleware:
+            def __init__(self, get_response):
+                self.get_response = get_response
+
+            def __call__(self, request):
+                response = self.get_response(request)
+                received.append(response)
+                return response
+
+        with override_settings(
+            ROOT_URLCONF='handlers.urls',
+            MIDDLEWARE=['handlers.tests.AsyncMiddlewareResponseTests.DummyMiddleware'],
+        ):
+            pass

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/middleware/cache\.py|django/middleware/security\.py|django/contrib/sessions/middleware\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 handlers.tests
cat coverage.cover
git checkout e39e727ded673e74016b5d3658d23cbe20234d11
git apply /root/pre_state.patch
