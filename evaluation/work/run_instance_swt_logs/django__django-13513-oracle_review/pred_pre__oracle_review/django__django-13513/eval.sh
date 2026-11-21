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
index 3cbeb2e..a7a63c6 100644
--- a/tests/view_tests/tests/test_debug.py
+++ b/tests/view_tests/tests/test_debug.py
@@ -467,6 +467,64 @@ class ExceptionReporterTests(SimpleTestCase):
         self.assertIn('<p>Request data not supplied</p>', html)
         self.assertNotIn('During handling of the above exception', html)
 
+    def test_reporting_frames_with_suppressed_context(self):
+        try:
+            try:
+                raise RuntimeError('my error')
+            except Exception:
+                raise ValueError('my new error') from None
+        except ValueError:
+            exc_type, exc_value, tb = sys.exc_info()
+        request = self.rf.get('/test_view/')
+        reporter = ExceptionReporter(request, exc_type, exc_value, tb)
+        frames = reporter.get_traceback_frames()
+        # Only the ValueError is reported, the suppressed RuntimeError isn't.
+        self.assertEqual(len(frames), 1)
+        self.assertIsNone(frames[0]['exc_cause'])
+        html = reporter.get_traceback_html()
+        self.assertNotIn('During handling of the above exception', html)
+        self.assertNotIn('was the direct cause of the following exception', html)
+        text = reporter.get_traceback_text()
+        self.assertNotIn('During handling of the above exception', text)
+        self.assertNotIn('was the direct cause of the following exception', text)
+
+    def test_reporting_frames_with_explicit_cause_and_suppressed_context(self):
+        try:
+            try:
+                raise RuntimeError('my error')
+            except Exception:
+                raise ValueError('my new error') from KeyError('explicit cause')
+        except ValueError:
+            exc_type, exc_value, tb = sys.exc_info()
+        request = self.rf.get('/test_view/')
+        reporter = ExceptionReporter(request, exc_type, exc_value, tb)
+        frames = reporter.get_traceback_frames()
+        # The explicit cause is reported, the suppressed context isn't.
+        self.assertEqual(len(frames), 2)
+        self.assertEqual(frames[0]['exc_cause'], KeyError('explicit cause'))
+        self.assertIs(frames[0]['exc_cause_explicit'], exc_value.__cause__)
+        html = reporter.get_traceback_html()
+        self.assertNotIn('During handling of the above exception', html)
+        self.assertIn('The above exception (explicit cause) was the direct cause', html)
+
+    def test_reporting_frames_with_implicit_context(self):
+        try:
+            try:
+                raise RuntimeError('my error')
+            except Exception:
+                raise ValueError('my new error')
+        except ValueError:
+            exc_type, exc_value, tb = sys.exc_info()
+        request = self.rf.get('/test_view/')
+        reporter = ExceptionReporter(request, exc_type, exc_value, tb)
+        frames = reporter.get_traceback_frames()
+        # Without suppression, the implicit context is still reported.
+        self.assertEqual(len(frames), 2)
+        self.assertEqual(frames[0]['exc_cause'], exc_value.__context__)
+        self.assertIsInstance(frames[0]['exc_cause'], RuntimeError)
+        html = reporter.get_traceback_html()
+        self.assertIn('During handling of the above exception (my error)', html)
+
     def test_reporting_of_nested_exceptions(self):
         request = self.rf.get('/test_view/')
         try:

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/views/debug\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 view_tests.tests.test_debug
cat coverage.cover
git checkout 6599608c4d0befdcb820ddccce55f183f247ae4f
git apply /root/pre_state.patch
