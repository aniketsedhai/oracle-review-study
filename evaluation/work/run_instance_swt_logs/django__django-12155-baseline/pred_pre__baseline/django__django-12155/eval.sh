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
index 17ea912..35f12a6 100644
--- a/tests/admin_docs/test_utils.py
+++ b/tests/admin_docs/test_utils.py
@@ -44,6 +44,19 @@ class TestUtils(AdminDocsSimpleTestCase):
         )
         self.assertEqual(trim_docstring_output, trimmed_docstring)
 
+    def test_trim_docstring_first_line_not_empty(self):
+        docstring = (
+            "Docstring starting on the first line.\n"
+            "\n"
+            "    Indented paragraph.\n"
+            "    Second indented line.\n"
+        )
+        self.assertEqual(
+            trim_docstring(docstring),
+            "Docstring starting on the first line.\n\n"
+            "Indented paragraph.\nSecond indented line.",
+        )
+
     def test_parse_docstring(self):
         title, description, metadata = parse_docstring(self.docstring)
         docstring_title = (
diff --git a/tests/admin_docs/test_views.py b/tests/admin_docs/test_views.py
index fb021f3..db059ec 100644
--- a/tests/admin_docs/test_views.py
+++ b/tests/admin_docs/test_views.py
@@ -75,6 +75,22 @@ class AdminDocViewTests(TestDataMixin, AdminDocsTestCase):
         # View docstring
         self.assertContains(response, 'Base view for admindocs views.')
 
+    def test_view_detail_docstring_starting_on_first_line(self):
+        """
+        A view docstring whose first line is not empty is rendered without
+        docutils errors (#30565).
+        """
+        url = reverse(
+            'django-admindocs-views-detail',
+            args=['admin_docs.views.docstring_starting_on_first_line'],
+        )
+        with captured_stderr() as stderr:
+            response = self.client.get(url)
+        self.assertEqual(response.status_code, 200)
+        self.assertNotIn('Error in "default-role" directive', stderr.getvalue())
+        self.assertContains(response, 'Docstring starting on the first line.')
+        self.assertContains(response, '<p>Second paragraph.</p>', html=True)
+
     @override_settings(ROOT_URLCONF='admin_docs.namespace_urls')
     def test_namespaced_view_detail(self):
         url = reverse('django-admindocs-views-detail', args=['admin_docs.views.XViewClass'])
diff --git a/tests/admin_docs/urls.py b/tests/admin_docs/urls.py
index f535afc..6f744de 100644
--- a/tests/admin_docs/urls.py
+++ b/tests/admin_docs/urls.py
@@ -15,4 +15,5 @@ urlpatterns = [
     path('xview/class/', views.xview_dec(views.XViewClass.as_view())),
     path('xview/callable_object/', views.xview_dec(views.XViewCallableObject())),
     path('xview/callable_object_without_xview/', views.XViewCallableObject()),
+    path('docstring/first_line/', views.docstring_starting_on_first_line),
 ]
diff --git a/tests/admin_docs/views.py b/tests/admin_docs/views.py
index 21fe382..c612acb 100644
--- a/tests/admin_docs/views.py
+++ b/tests/admin_docs/views.py
@@ -18,3 +18,11 @@ class XViewClass(View):
 class XViewCallableObject(View):
     def __call__(self, request):
         return HttpResponse()
+
+
+def docstring_starting_on_first_line(request):
+    """Docstring starting on the first line.
+
+    Second paragraph.
+    """
+    return HttpResponse()

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/admindocs/views\.py|django/contrib/admindocs/utils\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 admin_docs.test_utils admin_docs.test_views admin_docs.urls admin_docs.views
cat coverage.cover
git checkout e8fcdaad5c428878d0a5d6ba820d957013f75595
git apply /root/pre_state.patch
