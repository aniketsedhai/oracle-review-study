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
diff --git a/tests/i18n/tests.py b/tests/i18n/tests.py
index bb6ea15..8f0ba63 100644
--- a/tests/i18n/tests.py
+++ b/tests/i18n/tests.py
@@ -2058,3 +2058,48 @@ class UtilsTests(SimpleTestCase):
         for value, expected in tests:
             with self.subTest(value=value):
                 self.assertEqual(round_away_from_one(value), expected)
+
+
+@override_settings(
+    USE_I18N=True,
+    LANGUAGES=[
+        ('en-us', 'English'),
+        ('en-latn-us', 'Latin English'),
+        ('en-Latn-US', 'BCP 47 case format'),
+    ],
+    LANGUAGE_CODE='en-us',
+    MIDDLEWARE=[
+        'django.middleware.locale.LocaleMiddleware',
+        'django.middleware.common.CommonMiddleware',
+    ],
+    ROOT_URLCONF='i18n.urls',
+)
+class LanguageWithScriptAndRegionTests(SimpleTestCase):
+    """Regression tests for locales containing both script and region."""
+    rf = RequestFactory()
+
+    def test_get_language_from_path(self):
+        g = trans_real.get_language_from_path
+        self.assertEqual(g('/en-us/'), 'en-us')
+        self.assertEqual(g('/en-latn-us/'), 'en-latn-us')
+        self.assertEqual(g('/en-Latn-US/'), 'en-latn-us')
+
+    def test_get_language_from_request_check_path(self):
+        for path, expected in [
+            ('/en-us/', 'en-us'),
+            ('/en-latn-us/', 'en-latn-us'),
+            ('/en-Latn-US/', 'en-latn-us'),
+        ]:
+            with self.subTest(path=path):
+                r = self.rf.get(path)
+                r.COOKIES = {}
+                r.META = {}
+                self.assertEqual(
+                    get_language_from_request(r, check_path=True), expected,
+                )
+
+    def test_i18n_patterns_script_and_region(self):
+        for path in ('/en-us/simple/', '/en-latn-us/simple/', '/en-Latn-US/simple/'):
+            with self.subTest(path=path):
+                response = self.client.get(path)
+                self.assertEqual(response.status_code, 200)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/utils/translation/trans_real\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 i18n.tests
cat coverage.cover
git checkout 2c7846d992ca512d36a73f518205015c88ed088c
git apply /root/pre_state.patch
