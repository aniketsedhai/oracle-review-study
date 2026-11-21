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
index 17ea912..892ec24 100644
--- a/tests/admin_docs/test_utils.py
+++ b/tests/admin_docs/test_utils.py
@@ -118,3 +118,50 @@ class TestUtils(AdminDocsSimpleTestCase):
         markup = '<p>reST, <cite>interpreted text</cite>, default role.</p>\n'
         parts = docutils.core.publish_parts(source=source, writer_name="html4css1")
         self.assertEqual(parts['fragment'], markup)
+
+
+@unittest.skipUnless(docutils_is_available, "no docutils installed.")
+class TestTrimDocstring(AdminDocsSimpleTestCase):
+    def test_first_line_not_empty(self):
+        """Docstrings whose text starts on the first line are trimmed."""
+        docstring = (
+            "test tests something.\n"
+            "\n"
+            "    Indented body line.\n"
+            "    Another indented line.\n"
+            "    "
+        )
+        self.assertEqual(
+            trim_docstring(docstring),
+            "test tests something.\n\n    Indented body line.\n    Another indented line.",
+        )
+
+    def test_first_line_not_empty_single_line(self):
+        self.assertEqual(trim_docstring("test tests something.\n    "), "test tests something.")
+
+    def test_first_line_not_empty_parse_docstring(self):
+        docstring = (
+            "test tests something.\n"
+            "\n"
+            "    Body text.\n"
+            "\n"
+            "    some_metadata: some data\n"
+            "    "
+        )
+        title, description, metadata = parse_docstring(docstring)
+        self.assertEqual(title, "test tests something.")
+        self.assertEqual(description, "Body text.")
+        self.assertEqual(metadata, {"some_metadata": "some data"})
+
+    def test_first_line_not_empty_parse_rst(self):
+        docstring = (
+            "test tests something.\n"
+            "\n"
+            "    Body with `interpreted text`.\n"
+            "    "
+        )
+        title, description, metadata = parse_docstring(docstring)
+        self.assertEqual(title, "test tests something.")
+        output = parse_rst(description, "view", "view:admindocs")
+        self.assertIn("Body with", output)
+        self.assertNotIn("default-role", output)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/admindocs/utils\.py|django/contrib/admindocs/views\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 admin_docs.test_utils
cat coverage.cover
git checkout e8fcdaad5c428878d0a5d6ba820d957013f75595
git apply /root/pre_state.patch
