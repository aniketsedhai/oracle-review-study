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
index 3cbeb2e..ea13cef 100644
--- a/tests/view_tests/tests/test_debug.py
+++ b/tests/view_tests/tests/test_debug.py
@@ -466,6 +466,68 @@ class ExceptionReporterTests(SimpleTestCase):
         self.assertIn('<h2>Request information</h2>', html)
         self.assertIn('<p>Request data not supplied</p>', html)
         self.assertNotIn('During handling of the above exception', html)
+        text = reporter.get_traceback_text()
+        self.assertNotIn('During handling of the above exception', text)
+
+    def test_suppressed_context_frames(self):
+        """
+        A suppressed exception context (``raise ... from None``) must not be
+        included in the traceback frames (PEP 415, ``__suppress_context__``).
+        """
+        # Build the exception types/messages dynamically so that the literal
+        # strings don't appear in the rendered source context of this test.
+        inner_type = type('InnerError', (Exception,), {})
+        outer_type = type('OuterError', (Exception,), {})
+        inner_msg = 'inner suppressed message'
+        outer_msg = 'outer message'
+        try:
+            try:
+                raise inner_type(inner_msg)
+            except inner_type:
+                raise outer_type(outer_msg) from None
+        except outer_type:
+            exc_type, exc_value, tb = sys.exc_info()
+
+        reporter = ExceptionReporter(None, exc_type, exc_value, tb)
+        frames = reporter.get_traceback_frames()
+        # Only the outer exception frame should be present; the suppressed
+        # context exception must not contribute any frames.
+        self.assertEqual(len(frames), 1)
+        self.assertIsNone(frames[0]['exc_cause'])
+        self.assertIsNone(frames[0]['exc_cause_explicit'])
+
+        html = reporter.get_traceback_html()
+        self.assertInHTML('<h1>OuterError</h1>', html)
+        self.assertNotIn('During handling of the above exception', html)
+        # The plain-text traceback (which excludes local variables) must not
+        # mention the suppressed context exception at all.
+        text = reporter.get_traceback_text()
+        self.assertNotIn('InnerError', text)
+        self.assertNotIn(inner_msg, text)
+        self.assertNotIn('During handling of the above exception', text)
+
+    def test_implicit_context_frames(self):
+        """
+        An implicit exception context (no ``from`` clause) is still reported.
+        """
+        inner_type = type('InnerError', (Exception,), {})
+        outer_type = type('OuterError', (Exception,), {})
+        try:
+            try:
+                raise inner_type('inner message')
+            except inner_type:
+                raise outer_type('outer message')
+        except outer_type:
+            exc_type, exc_value, tb = sys.exc_info()
+
+        reporter = ExceptionReporter(None, exc_type, exc_value, tb)
+        frames = reporter.get_traceback_frames()
+        # Frames are ordered outermost exception first.
+        self.assertEqual(len(frames), 2)
+        self.assertIsNone(frames[0]['exc_cause'])
+        self.assertIsInstance(frames[-1]['exc_cause'], inner_type)
+        html = reporter.get_traceback_html()
+        self.assertIn('During handling of the above exception', html)
 
     def test_reporting_of_nested_exceptions(self):
         request = self.rf.get('/test_view/')

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/views/debug\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 view_tests.tests.test_debug
cat coverage.cover
git checkout 6599608c4d0befdcb820ddccce55f183f247ae4f
git apply /root/pre_state.patch
