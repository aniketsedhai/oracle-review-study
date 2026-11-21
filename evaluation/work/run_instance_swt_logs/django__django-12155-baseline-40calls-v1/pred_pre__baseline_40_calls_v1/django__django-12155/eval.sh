#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD e8fcdaad5c428878d0a5d6ba820d957013f75595 >> /root/pre_state.patch
sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff e8fcdaad5c428878d0a5d6ba820d957013f75595
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/tests/admin_docs/test_utils.py b/tests/admin_docs/test_utils.py
index 17ea912..aa23722 100644
--- a/tests/admin_docs/test_utils.py
+++ b/tests/admin_docs/test_utils.py
@@ -118,3 +118,33 @@ class TestUtils(AdminDocsSimpleTestCase):
         markup = '<p>reST, <cite>interpreted text</cite>, default role.</p>\n'
         parts = docutils.core.publish_parts(source=source, writer_name="html4css1")
         self.assertEqual(parts['fragment'], markup)
+
+
+class TestTrimDocstring(unittest.TestCase):
+    def test_first_line_not_empty(self):
+        """Docstrings whose text starts on the first line are trimmed."""
+        docstring = (
+            'test tests something.\n'
+            '\n'
+            '    More text.\n'
+            '    '
+        )
+        self.assertEqual(
+            trim_docstring(docstring),
+            'test tests something.\n\n    More text.',
+        )
+
+    def test_first_line_indented(self):
+        docstring = (
+            '    test tests something.\n'
+            '        More text.\n'
+            '    '
+        )
+        self.assertEqual(
+            trim_docstring(docstring),
+            'test tests something.\n    More text.',
+        )
+
+    def test_empty_docstring(self):
+        self.assertEqual(trim_docstring(''), '')
+        self.assertEqual(trim_docstring('   \n  '), '')

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/admindocs/views\.py|django/contrib/admindocs/utils\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 admin_docs.test_utils
cat coverage.cover
git checkout e8fcdaad5c428878d0a5d6ba820d957013f75595
git apply /root/pre_state.patch
