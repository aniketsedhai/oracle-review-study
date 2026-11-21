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
index 3cbeb2e..9bf29a0 100644
--- a/tests/view_tests/tests/test_debug.py
+++ b/tests/view_tests/tests/test_debug.py
@@ -467,6 +467,62 @@ class ExceptionReporterTests(SimpleTestCase):
         self.assertIn('<p>Request data not supplied</p>', html)
         self.assertNotIn('During handling of the above exception', html)
 
+    def test_reporting_frames_for_suppressed_context(self):
+        try:
+            try:
+                raise RuntimeError("Can't find my keys")
+            except RuntimeError:
+                raise ValueError("Can't find my keys") from None
+        except ValueError:
+            exc_type, exc_value, tb = sys.exc_info()
+
+        reporter = ExceptionReporter(None, exc_type, exc_value, tb)
+        frames = reporter.get_traceback_frames()
+        self.assertEqual(len(frames), 1)
+        self.assertIsNone(frames[0]['exc_cause'])
+        self.assertIsNone(frames[0]['exc_cause_explicit'])
+        html = reporter.get_traceback_html()
+        text = reporter.get_traceback_text()
+        # The suppressed exception's traceback isn't rendered.
+        self.assertNotIn('RuntimeError: ', html)
+        self.assertNotIn('RuntimeError: ', text)
+
+    def test_reporting_frames_for_explicit_cause(self):
+        try:
+            try:
+                raise RuntimeError('my error')
+            except RuntimeError as exc:
+                raise ValueError('my new error') from exc
+        except ValueError:
+            exc_type, exc_value, tb = sys.exc_info()
+
+        reporter = ExceptionReporter(None, exc_type, exc_value, tb)
+        frames = reporter.get_traceback_frames()
+        self.assertEqual(len(frames), 2)
+        self.assertIsNone(frames[0]['exc_cause'])
+        self.assertIsNone(frames[0]['exc_cause_explicit'])
+        self.assertEqual(str(frames[1]['exc_cause']), 'my error')
+        html = reporter.get_traceback_html()
+        self.assertIn('The above exception (my error) was the direct cause', html)
+        self.assertNotIn('During handling of the above exception', html)
+
+    def test_reporting_frames_for_implicit_context(self):
+        try:
+            try:
+                raise RuntimeError('my error')
+            except RuntimeError:
+                raise ValueError('my new error')
+        except ValueError:
+            exc_type, exc_value, tb = sys.exc_info()
+
+        reporter = ExceptionReporter(None, exc_type, exc_value, tb)
+        frames = reporter.get_traceback_frames()
+        self.assertEqual(len(frames), 2)
+        self.assertIsNone(frames[0]['exc_cause'])
+        self.assertEqual(str(frames[1]['exc_cause']), 'my error')
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
