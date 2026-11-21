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
index bb6ea15..9d2f153 100644
--- a/tests/i18n/tests.py
+++ b/tests/i18n/tests.py
@@ -18,6 +18,7 @@ from django.conf import settings
 from django.conf.locale import LANG_INFO
 from django.conf.urls.i18n import i18n_patterns
 from django.template import Context, Template
+from django.urls import reverse
 from django.test import (
     RequestFactory, SimpleTestCase, TestCase, ignore_warnings,
     override_settings,
@@ -1610,6 +1611,21 @@ class MiscTests(SimpleTestCase):
         self.assertEqual(g('/de-ch/'), 'de')
         self.assertIsNone(g('/de-simple-page/'))
 
+    @override_settings(
+        LANGUAGES=[
+            ('en-us', 'English'),
+            ('en-latn-us', 'Latin English'),
+            ('en-Latn-US', 'BCP 47 case format'),
+        ],
+    )
+    def test_get_language_from_path_real_script_and_region(self):
+        g = trans_real.get_language_from_path
+        self.assertEqual(g('/en-us/'), 'en-us')
+        self.assertEqual(g('/en-latn-us/'), 'en-latn-us')
+        self.assertEqual(g('/en-Latn-US/'), 'en-Latn-US')
+        self.assertEqual(g('/en-latn-us'), 'en-latn-us')
+        self.assertEqual(g('/en-Latn-US'), 'en-Latn-US')
+
     def test_get_language_from_path_null(self):
         g = trans_null.get_language_from_path
         self.assertIsNone(g('/pl/'))
@@ -1635,6 +1651,24 @@ class MiscTests(SimpleTestCase):
         with override_settings(USE_I18N=True):
             self.assertIsInstance(i18n_patterns([]), list)
 
+    @override_settings(
+        LANGUAGES=[
+            ('en-us', 'English'),
+            ('en-latn-us', 'Latin English'),
+            ('en-Latn-US', 'BCP 47 case format'),
+        ],
+        LANGUAGE_CODE='en-us',
+        ROOT_URLCONF='i18n.urls_script_region',
+    )
+    def test_i18n_patterns_script_and_region(self):
+        for lang_code in ['en-us', 'en-latn-us', 'en-Latn-US']:
+            with self.subTest(lang_code=lang_code):
+                with translation.override(lang_code):
+                    self.assertEqual(reverse('script-region'), '/%s/' % lang_code.lower())
+                response = self.client.get('/%s/' % lang_code)
+                self.assertEqual(response.status_code, 200)
+                self.assertEqual(response.content, b'U!')
+
 
 class ResolutionOrderI18NTests(SimpleTestCase):
 
diff --git a/tests/i18n/urls_script_region.py b/tests/i18n/urls_script_region.py
new file mode 100644
index 0000000..3a1c1d0
--- /dev/null
+++ b/tests/i18n/urls_script_region.py
@@ -0,0 +1,12 @@
+from django.conf.urls.i18n import i18n_patterns
+from django.http import HttpResponse
+from django.urls import path
+
+
+def bangiah(request):
+    return HttpResponse('U!')
+
+
+urlpatterns = i18n_patterns(
+    path('', bangiah, name='script-region'),
+)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/utils/translation/trans_real\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 i18n.tests i18n.urls_script_region
cat coverage.cover
git checkout 2c7846d992ca512d36a73f518205015c88ed088c
git apply /root/pre_state.patch
