#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 2c7846d992ca512d36a73f518205015c88ed088c >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 2c7846d992ca512d36a73f518205015c88ed088c
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/tests/i18n/patterns/tests.py b/tests/i18n/patterns/tests.py
index ebd2430..2c411e0 100644
--- a/tests/i18n/patterns/tests.py
+++ b/tests/i18n/patterns/tests.py
@@ -393,3 +393,27 @@ class URLTagTests(URLTestCaseBase):
             {% language 'pt-br' %}{% url 'no-prefix-translated-slug' slug='apo' %}{% endlanguage %}""")
         self.assertEqual(tpl.render(Context({})).strip().split(),
                          ['/vertaald/apo/', '/traduzidos/apo/'])
+
+
+@override_settings(
+    USE_I18N=True,
+    LANGUAGE_CODE='en-us',
+    LANGUAGES=[
+        ('en-us', 'English'),
+        ('en-latn-us', 'Latin English'),
+        ('en-Latn-US', 'BCP 47 case format'),
+    ],
+    MIDDLEWARE=[
+        'django.middleware.locale.LocaleMiddleware',
+        'django.middleware.common.CommonMiddleware',
+    ],
+    ROOT_URLCONF='i18n.patterns.urls.script_region',
+)
+class URLScriptRegionTests(URLTestCaseBase):
+    """Language codes containing both a script and a region subtag."""
+    def test_script_region_url(self):
+        for language in ('en-latn-us', 'en-Latn-US'):
+            response = self.client.get('/%s/' % language)
+            self.assertEqual(response.status_code, 200)
+            self.assertEqual(response.headers['content-language'], language)
+            self.assertEqual(response.context['LANGUAGE_CODE'], language)
diff --git a/tests/i18n/patterns/urls/script_region.py b/tests/i18n/patterns/urls/script_region.py
new file mode 100644
index 0000000..0e23b8f
--- /dev/null
+++ b/tests/i18n/patterns/urls/script_region.py
@@ -0,0 +1,9 @@
+from django.conf.urls.i18n import i18n_patterns
+from django.urls import path
+from django.views.generic import TemplateView
+
+view = TemplateView.as_view(template_name='dummy.html')
+
+urlpatterns = i18n_patterns(
+    path('', view, name='script-region'),
+)
diff --git a/tests/i18n/tests.py b/tests/i18n/tests.py
index bb6ea15..807cf86 100644
--- a/tests/i18n/tests.py
+++ b/tests/i18n/tests.py
@@ -1610,6 +1610,18 @@ class MiscTests(SimpleTestCase):
         self.assertEqual(g('/de-ch/'), 'de')
         self.assertIsNone(g('/de-simple-page/'))
 
+    @override_settings(
+        LANGUAGES=[
+            ('en-us', 'English'),
+            ('en-latn-us', 'Latin English'),
+            ('en-Latn-US', 'BCP 47 case format'),
+        ],
+    )
+    def test_get_language_from_path_script_region(self):
+        g = trans_real.get_language_from_path
+        self.assertEqual(g('/en-latn-us/'), 'en-latn-us')
+        self.assertEqual(g('/en-Latn-US/'), 'en-Latn-US')
+
     def test_get_language_from_path_null(self):
         g = trans_null.get_language_from_path
         self.assertIsNone(g('/pl/'))

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/utils/translation/trans_real\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 i18n.patterns.tests i18n.patterns.urls.script_region i18n.tests
cat coverage.cover
git checkout 2c7846d992ca512d36a73f518205015c88ed088c
git apply /root/pre_state.patch
