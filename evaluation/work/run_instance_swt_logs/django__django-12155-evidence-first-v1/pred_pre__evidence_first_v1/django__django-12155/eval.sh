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
index 17ea912..700d1ee 100644
--- a/tests/admin_docs/test_utils.py
+++ b/tests/admin_docs/test_utils.py
@@ -118,3 +118,15 @@ class TestUtils(AdminDocsSimpleTestCase):
         markup = '<p>reST, <cite>interpreted text</cite>, default role.</p>\n'
         parts = docutils.core.publish_parts(source=source, writer_name="html4css1")
         self.assertEqual(parts['fragment'], markup)
+
+    def test_trim_docstring_first_line_not_empty(self):
+        docstring = (
+            'test tests something.\n'
+            '\n'
+            '    Body text here.\n'
+            '    '
+        )
+        self.assertEqual(
+            trim_docstring(docstring),
+            'test tests something.\n\nBody text here.',
+        )
diff --git a/tests/admin_docs/test_views.py b/tests/admin_docs/test_views.py
index fb021f3..bfc38ea 100644
--- a/tests/admin_docs/test_views.py
+++ b/tests/admin_docs/test_views.py
@@ -362,3 +362,11 @@ class AdminDocViewFunctionsTests(SimpleTestCase):
         for pattern, output in tests:
             with self.subTest(pattern=pattern):
                 self.assertEqual(simplify_regex(pattern), output)
+
+    def test_view_detail_docstring_first_line_not_empty(self):
+        url = reverse('django-admindocs-views-detail', args=['admin_docs.views.docstring_starts_on_first_line'])
+        response = self.client.get(url)
+        self.assertEqual(response.status_code, 200)
+        self.assertNotContains(response, 'no content permitted')
+        self.assertContains(response, 'test tests something.')
+        self.assertContains(response, 'Body text here.')
diff --git a/tests/admin_docs/urls.py b/tests/admin_docs/urls.py
index f535afc..faacf06 100644
--- a/tests/admin_docs/urls.py
+++ b/tests/admin_docs/urls.py
@@ -15,4 +15,5 @@ urlpatterns = [
     path('xview/class/', views.xview_dec(views.XViewClass.as_view())),
     path('xview/callable_object/', views.xview_dec(views.XViewCallableObject())),
     path('xview/callable_object_without_xview/', views.XViewCallableObject()),
+    path('docstring/first_line/', views.docstring_starts_on_first_line),
 ]
diff --git a/tests/admin_docs/views.py b/tests/admin_docs/views.py
index 21fe382..92ee5ab 100644
--- a/tests/admin_docs/views.py
+++ b/tests/admin_docs/views.py
@@ -18,3 +18,11 @@ class XViewClass(View):
 class XViewCallableObject(View):
     def __call__(self, request):
         return HttpResponse()
+
+
+def docstring_starts_on_first_line(request):
+    """test tests something.
+
+    Body text here.
+    """
+    return HttpResponse()

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/admindocs/views\.py|django/contrib/admindocs/utils\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 admin_docs.test_utils admin_docs.test_views admin_docs.urls admin_docs.views
cat coverage.cover
git checkout e8fcdaad5c428878d0a5d6ba820d957013f75595
git apply /root/pre_state.patch
