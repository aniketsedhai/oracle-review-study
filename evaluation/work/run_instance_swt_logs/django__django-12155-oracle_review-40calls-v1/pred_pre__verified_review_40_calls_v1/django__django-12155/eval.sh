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
index 17ea912..7245d52 100644
--- a/tests/admin_docs/test_utils.py
+++ b/tests/admin_docs/test_utils.py
@@ -44,6 +44,18 @@ class TestUtils(AdminDocsSimpleTestCase):
         )
         self.assertEqual(trim_docstring_output, trimmed_docstring)
 
+    def test_trim_docstring_first_line_not_empty(self):
+        docstring = (
+            "test tests something.\n"
+            "\n"
+            "    More text.\n"
+            "    "
+        )
+        self.assertEqual(
+            trim_docstring(docstring),
+            "test tests something.\n\nMore text.",
+        )
+
     def test_parse_docstring(self):
         title, description, metadata = parse_docstring(self.docstring)
         docstring_title = (
diff --git a/tests/admin_docs/test_views.py b/tests/admin_docs/test_views.py
index fb021f3..3009bdc 100644
--- a/tests/admin_docs/test_views.py
+++ b/tests/admin_docs/test_views.py
@@ -75,6 +75,22 @@ class AdminDocViewTests(TestDataMixin, AdminDocsTestCase):
         # View docstring
         self.assertContains(response, 'Base view for admindocs views.')
 
+    def test_view_detail_docstring_first_line_not_empty(self):
+        """
+        A view docstring whose first line isn't empty is rendered without
+        docutils errors (#regression).
+        """
+        url = reverse(
+            'django-admindocs-views-detail',
+            args=['admin_docs.views.XViewClassWithDocstring'],
+        )
+        response = self.client.get(url)
+        self.assertEqual(response.status_code, 200)
+        self.assertContains(response, 'test tests something.')
+        self.assertContains(response, 'More text.')
+        self.assertNotContains(response, 'System Message')
+        self.assertNotContains(response, 'Error in "default-role" directive')
+
     @override_settings(ROOT_URLCONF='admin_docs.namespace_urls')
     def test_namespaced_view_detail(self):
         url = reverse('django-admindocs-views-detail', args=['admin_docs.views.XViewClass'])
diff --git a/tests/admin_docs/urls.py b/tests/admin_docs/urls.py
index f535afc..1ef7e46 100644
--- a/tests/admin_docs/urls.py
+++ b/tests/admin_docs/urls.py
@@ -15,4 +15,5 @@ urlpatterns = [
     path('xview/class/', views.xview_dec(views.XViewClass.as_view())),
     path('xview/callable_object/', views.xview_dec(views.XViewCallableObject())),
     path('xview/callable_object_without_xview/', views.XViewCallableObject()),
+    path('xview/class_with_docstring/', views.XViewClassWithDocstring.as_view()),
 ]
diff --git a/tests/admin_docs/views.py b/tests/admin_docs/views.py
index 21fe382..1a353df 100644
--- a/tests/admin_docs/views.py
+++ b/tests/admin_docs/views.py
@@ -18,3 +18,14 @@ class XViewClass(View):
 class XViewCallableObject(View):
     def __call__(self, request):
         return HttpResponse()
+
+
+class XViewClassWithDocstring(View):
+    """test tests something.
+
+    .. default-role:: cmsreference
+
+    More text.
+    """
+    def get(self, request):
+        return HttpResponse()

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/admindocs/views\.py|django/contrib/admindocs/utils\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 admin_docs.test_utils admin_docs.test_views admin_docs.urls admin_docs.views
cat coverage.cover
git checkout e8fcdaad5c428878d0a5d6ba820d957013f75595
git apply /root/pre_state.patch
