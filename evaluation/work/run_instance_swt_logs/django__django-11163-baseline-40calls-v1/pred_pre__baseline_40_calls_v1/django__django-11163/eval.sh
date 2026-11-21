#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD e6588aa4e793b7f56f4cadbfa155b581e0efc59a >> /root/pre_state.patch
sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff e6588aa4e793b7f56f4cadbfa155b581e0efc59a
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/tests/model_forms/tests.py b/tests/model_forms/tests.py
index f4f3169..dab2c24 100644
--- a/tests/model_forms/tests.py
+++ b/tests/model_forms/tests.py
@@ -2912,3 +2912,18 @@ class ModelToDictTests(TestCase):
         # If data were a QuerySet, it would be reevaluated here and give "red"
         # instead of the original value.
         self.assertEqual(data, [blue])
+
+    def test_empty_fields(self):
+        """An empty list of fields returns an empty dict."""
+        item = ColourfulItem.objects.create()
+        self.assertEqual(model_to_dict(item, fields=[]), {})
+
+    def test_fields(self):
+        item = ColourfulItem.objects.create()
+        data = model_to_dict(item, fields=['id'])
+        self.assertEqual(data, {'id': item.pk})
+
+    def test_exclude(self):
+        item = ColourfulItem.objects.create()
+        data = model_to_dict(item, exclude=['id', 'colours'])
+        self.assertEqual(data, {'name': ''})

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/forms/models\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 model_forms.tests
cat coverage.cover
git checkout e6588aa4e793b7f56f4cadbfa155b581e0efc59a
git apply /root/pre_state.patch
