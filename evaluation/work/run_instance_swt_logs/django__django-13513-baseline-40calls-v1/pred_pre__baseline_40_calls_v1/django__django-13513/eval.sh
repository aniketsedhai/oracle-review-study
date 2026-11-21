#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 6599608c4d0befdcb820ddccce55f183f247ae4f >> /root/pre_state.patch
sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 6599608c4d0befdcb820ddccce55f183f247ae4f
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/tests/view_tests/tests/test_debug.py b/tests/view_tests/tests/test_debug.py
index 3cbeb2e..b506192 100644
--- a/tests/view_tests/tests/test_debug.py
+++ b/tests/view_tests/tests/test_debug.py
@@ -618,6 +618,63 @@ class ExceptionReporterTests(SimpleTestCase):
         self.assertEqual(last_frame['filename'], __file__)
         self.assertEqual(last_frame['function'], 'test_func')
 
+    def test_reporting_frames_with_suppressed_context(self):
+        try:
+            try:
+                raise RuntimeError('inner')
+            except RuntimeError:
+                raise ValueError('outer') from None
+        except Exception:
+            exc_type, exc_value, tb = sys.exc_info()
+        request = self.rf.get('/test_view/')
+        reporter = ExceptionReporter(request, exc_type, exc_value, tb)
+        frames = reporter.get_traceback_frames()
+        # The suppressed RuntimeError context isn't reported.
+        self.assertEqual(len(frames), 1)
+        self.assertIsNone(frames[0]['exc_cause'])
+        html = reporter.get_traceback_html()
+        self.assertNotIn('During handling of the above exception', html)
+        self.assertNotIn('was the direct cause of the following exception', html)
+        text = reporter.get_traceback_text()
+        self.assertNotIn('During handling of the above exception', text)
+        self.assertNotIn('was the direct cause of the following exception', text)
+
+    def test_reporting_frames_with_explicit_cause(self):
+        try:
+            try:
+                raise RuntimeError('inner')
+            except RuntimeError as exc:
+                raise ValueError('outer') from exc
+        except Exception:
+            exc_type, exc_value, tb = sys.exc_info()
+        request = self.rf.get('/test_view/')
+        reporter = ExceptionReporter(request, exc_type, exc_value, tb)
+        frames = reporter.get_traceback_frames()
+        self.assertEqual(len(frames), 2)
+        self.assertEqual(str(frames[-1]['exc_cause']), 'inner')
+        self.assertIs(frames[-1]['exc_cause_explicit'], frames[-1]['exc_cause'])
+        self.assertIsNone(frames[0]['exc_cause_explicit'])
+        html = reporter.get_traceback_html()
+        self.assertIn('was the direct cause of the following exception', html)
+
+    def test_reporting_frames_with_implicit_context(self):
+        try:
+            try:
+                raise RuntimeError('inner')
+            except RuntimeError:
+                raise ValueError('outer')
+        except Exception:
+            exc_type, exc_value, tb = sys.exc_info()
+        request = self.rf.get('/test_view/')
+        reporter = ExceptionReporter(request, exc_type, exc_value, tb)
+        frames = reporter.get_traceback_frames()
+        self.assertEqual(len(frames), 2)
+        self.assertEqual(str(frames[-1]['exc_cause']), 'inner')
+        self.assertIsNone(frames[-1]['exc_cause_explicit'])
+        self.assertIsNone(frames[0]['exc_cause_explicit'])
+        html = reporter.get_traceback_html()
+        self.assertIn('During handling of the above exception', html)
+
     def test_request_and_message(self):
         "A message can be provided in addition to a request"
         request = self.rf.get('/test_view/')

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/views/debug\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 view_tests.tests.test_debug
cat coverage.cover
git checkout 6599608c4d0befdcb820ddccce55f183f247ae4f
git apply /root/pre_state.patch
