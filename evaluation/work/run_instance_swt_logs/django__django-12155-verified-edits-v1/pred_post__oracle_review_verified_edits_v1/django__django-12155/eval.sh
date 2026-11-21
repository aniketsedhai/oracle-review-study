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
diff --git a/django/contrib/admindocs/utils.py b/django/contrib/admindocs/utils.py
--- a/django/contrib/admindocs/utils.py
+++ b/django/contrib/admindocs/utils.py
@@ -3,6 +3,7 @@
 import re
 from email.errors import HeaderParseError
 from email.parser import HeaderParser
+from inspect import cleandoc
 
 from django.urls import reverse
 from django.utils.regex_helper import _lazy_re_compile
@@ -24,26 +25,13 @@ def get_view_name(view_func):
     return mod_name + '.' + view_name
 
 
-def trim_docstring(docstring):
-    """
-    Uniformly trim leading/trailing whitespace from docstrings.
-
-    Based on https://www.python.org/dev/peps/pep-0257/#handling-docstring-indentation
-    """
-    if not docstring or not docstring.strip():
-        return ''
-    # Convert tabs to spaces and split into lines
-    lines = docstring.expandtabs().splitlines()
-    indent = min(len(line) - len(line.lstrip()) for line in lines if line.lstrip())
-    trimmed = [lines[0].lstrip()] + [line[indent:].rstrip() for line in lines[1:]]
-    return "\n".join(trimmed).strip()
-
-
 def parse_docstring(docstring):
     """
     Parse out the parts of a docstring.  Return (title, body, metadata).
     """
-    docstring = trim_docstring(docstring)
+    if not docstring:
+        return '', '', {}
+    docstring = cleandoc(docstring)
     parts = re.split(r'\n{2,}', docstring)
     title = parts[0]
     if len(parts) == 1:
diff --git a/django/contrib/admindocs/views.py b/django/contrib/admindocs/views.py
--- a/django/contrib/admindocs/views.py
+++ b/django/contrib/admindocs/views.py
@@ -1,5 +1,6 @@
 import inspect
 from importlib import import_module
+from inspect import cleandoc
 from pathlib import Path
 
 from django.apps import apps
@@ -256,7 +257,7 @@ def get_context_data(self, **kwargs):
                     continue
                 verbose = func.__doc__
                 verbose = verbose and (
-                    utils.parse_rst(utils.trim_docstring(verbose), 'model', _('model:') + opts.model_name)
+                    utils.parse_rst(cleandoc(verbose), 'model', _('model:') + opts.model_name)
                 )
                 # Show properties and methods without arguments as fields.
                 # Otherwise, show as a 'method with arguments'.

EOF_114329324912
git apply -v - <<'EOF_114329324912'
diff --git a/tests/admin_docs/test_utils.py b/tests/admin_docs/test_utils.py
index 17ea912..1eaa17e 100644
--- a/tests/admin_docs/test_utils.py
+++ b/tests/admin_docs/test_utils.py
@@ -44,6 +44,41 @@ class TestUtils(AdminDocsSimpleTestCase):
         )
         self.assertEqual(trim_docstring_output, trimmed_docstring)
 
+    def test_trim_docstring_first_line_not_empty(self):
+        docstring = (
+            'test tests something.\n'
+            '    More text here.\n'
+            '    '
+        )
+        self.assertEqual(
+            trim_docstring(docstring),
+            'test tests something.\nMore text here.',
+        )
+
+    def test_trim_docstring_first_line_not_empty_with_common_indent(self):
+        docstring = (
+            'test tests something.\n'
+            '    More text here.\n'
+            '        Even more indented.\n'
+            '    '
+        )
+        self.assertEqual(
+            trim_docstring(docstring),
+            'test tests something.\nMore text here.\n    Even more indented.',
+        )
+
+    def test_parse_docstring_first_line_not_empty(self):
+        docstring = (
+            'test tests something.\n'
+            '\n'
+            '    Body text.\n'
+            '    '
+        )
+        title, description, metadata = parse_docstring(docstring)
+        self.assertEqual(title, 'test tests something.')
+        self.assertEqual(description, 'Body text.')
+        self.assertEqual(metadata, {})
+
     def test_parse_docstring(self):
         title, description, metadata = parse_docstring(self.docstring)
         docstring_title = (
diff --git a/tests/admin_docs/test_views.py b/tests/admin_docs/test_views.py
index fb021f3..36ab7d5 100644
--- a/tests/admin_docs/test_views.py
+++ b/tests/admin_docs/test_views.py
@@ -75,6 +75,24 @@ class AdminDocViewTests(TestDataMixin, AdminDocsTestCase):
         # View docstring
         self.assertContains(response, 'Base view for admindocs views.')
 
+    def test_view_detail_docstring_starts_on_first_line(self):
+        url = reverse(
+            'django-admindocs-views-detail',
+            args=['admin_docs.views.docstring_starts_on_first_line'],
+        )
+        response = self.client.get(url)
+        self.assertEqual(response.status_code, 200)
+        self.assertContains(response, 'Docstring starts on the first line.')
+        self.assertContains(
+            response,
+            '<p>Body text with a <a class="reference external" '
+            'href="/admindocs/views/admin_docs.views.xview/">'
+            'admin_docs.views.xview</a> reference.</p>',
+            html=True,
+        )
+        self.assertNotContains(response, 'Error in "default-role" directive')
+        self.assertNotContains(response, 'System Message')
+
     @override_settings(ROOT_URLCONF='admin_docs.namespace_urls')
     def test_namespaced_view_detail(self):
         url = reverse('django-admindocs-views-detail', args=['admin_docs.views.XViewClass'])
diff --git a/tests/admin_docs/urls.py b/tests/admin_docs/urls.py
index f535afc..a36e943 100644
--- a/tests/admin_docs/urls.py
+++ b/tests/admin_docs/urls.py
@@ -15,4 +15,5 @@ urlpatterns = [
     path('xview/class/', views.xview_dec(views.XViewClass.as_view())),
     path('xview/callable_object/', views.xview_dec(views.XViewCallableObject())),
     path('xview/callable_object_without_xview/', views.XViewCallableObject()),
+    path('docstring_starts_on_first_line/', views.docstring_starts_on_first_line),
 ]
diff --git a/tests/admin_docs/views.py b/tests/admin_docs/views.py
index 21fe382..4331341 100644
--- a/tests/admin_docs/views.py
+++ b/tests/admin_docs/views.py
@@ -18,3 +18,11 @@ class XViewClass(View):
 class XViewCallableObject(View):
     def __call__(self, request):
         return HttpResponse()
+
+
+def docstring_starts_on_first_line(request):
+    """Docstring starts on the first line.
+
+    Body text with a :view:`admin_docs.views.xview` reference.
+    """
+    return HttpResponse()

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/admindocs/utils\.py|django/contrib/admindocs/views\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 admin_docs.test_utils admin_docs.test_views admin_docs.urls admin_docs.views
cat coverage.cover
git checkout e8fcdaad5c428878d0a5d6ba820d957013f75595
git apply /root/pre_state.patch
