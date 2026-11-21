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
diff --git a/django/utils/translation/trans_real.py b/django/utils/translation/trans_real.py
--- a/django/utils/translation/trans_real.py
+++ b/django/utils/translation/trans_real.py
@@ -43,7 +43,7 @@
     re.IGNORECASE
 )
 
-language_code_prefix_re = _lazy_re_compile(r'^/(\w+([@-]\w+)?)(/|$)')
+language_code_prefix_re = _lazy_re_compile(r'^/(\w+([@-]\w+){0,2})(/|$)')
 
 
 @receiver(setting_changed)

EOF_114329324912
git apply -v - <<'EOF_114329324912'
diff --git a/tests/i18n/tests.py b/tests/i18n/tests.py
index bb6ea15..9a4de22 100644
--- a/tests/i18n/tests.py
+++ b/tests/i18n/tests.py
@@ -1610,6 +1610,22 @@ class MiscTests(SimpleTestCase):
         self.assertEqual(g('/de-ch/'), 'de')
         self.assertIsNone(g('/de-simple-page/'))
 
+    @override_settings(
+        LANGUAGES=[
+            ('en-us', 'English'),
+            ('en-latn-us', 'Latin English'),
+            ('en-Latn-US', 'BCP 47 case format'),
+        ],
+    )
+    def test_get_language_from_path_with_script_and_region(self):
+        g = trans_real.get_language_from_path
+        self.assertEqual(g('/en-us/'), 'en-us')
+        self.assertEqual(g('/en-latn-us/'), 'en-latn-us')
+        self.assertEqual(g('/en-Latn-US/'), 'en-Latn-US')
+        self.assertEqual(g('/en-latn-us'), 'en-latn-us')
+        self.assertEqual(g('/en-Latn-US'), 'en-Latn-US')
+        self.assertIsNone(g('/en-latn-us-extra/'))
+
     def test_get_language_from_path_null(self):
         g = trans_null.get_language_from_path
         self.assertIsNone(g('/pl/'))
@@ -1844,6 +1860,32 @@ class UnprefixedDefaultLanguageTests(SimpleTestCase):
     ],
     ROOT_URLCONF='i18n.urls'
 )
+@override_settings(
+    USE_I18N=True,
+    LANGUAGES=[
+        ('en-us', 'English'),
+        ('en-latn-us', 'Latin English'),
+        ('en-Latn-US', 'BCP 47 case format'),
+    ],
+    MIDDLEWARE=[
+        'django.middleware.locale.LocaleMiddleware',
+        'django.middleware.common.CommonMiddleware',
+    ],
+    ROOT_URLCONF='i18n.urls_script_region',
+    LANGUAGE_CODE='en-us',
+)
+class ScriptAndRegionLanguagePrefixTests(SimpleTestCase):
+    def test_language_prefix_with_script_and_region(self):
+        for lang_code in ('en-us', 'en-latn-us', 'en-Latn-US'):
+            with self.subTest(lang_code=lang_code):
+                response = self.client.get('/%s/simple/' % lang_code)
+                self.assertEqual(response.status_code, 200)
+
+    def test_unknown_language_prefix(self):
+        response = self.client.get('/en-latn-us-extra/simple/')
+        self.assertEqual(response.status_code, 404)
+
+
 class CountrySpecificLanguageTests(SimpleTestCase):
     rf = RequestFactory()
 
diff --git a/tests/i18n/urls_script_region.py b/tests/i18n/urls_script_region.py
new file mode 100644
index 0000000..f4da8d1
--- /dev/null
+++ b/tests/i18n/urls_script_region.py
@@ -0,0 +1,7 @@
+from django.conf.urls.i18n import i18n_patterns
+from django.http import HttpResponse
+from django.urls import path
+
+urlpatterns = i18n_patterns(
+    path('simple/', lambda r: HttpResponse('U!')),
+)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/utils/translation/trans_real\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 i18n.tests i18n.urls_script_region
cat coverage.cover
git checkout 2c7846d992ca512d36a73f518205015c88ed088c
git apply /root/pre_state.patch
