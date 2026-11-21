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
diff --git a/django/forms/models.py b/django/forms/models.py
--- a/django/forms/models.py
+++ b/django/forms/models.py
@@ -83,7 +83,7 @@ def model_to_dict(instance, fields=None, exclude=None):
     for f in chain(opts.concrete_fields, opts.private_fields, opts.many_to_many):
         if not getattr(f, 'editable', False):
             continue
-        if fields and f.name not in fields:
+        if fields is not None and f.name not in fields:
             continue
         if exclude and f.name in exclude:
             continue

EOF_114329324912
git apply -v - <<'EOF_114329324912'
diff --git a/tests/model_forms/tests.py b/tests/model_forms/tests.py
index f4f3169..9503ebc 100644
--- a/tests/model_forms/tests.py
+++ b/tests/model_forms/tests.py
@@ -2912,3 +2912,16 @@ class ModelToDictTests(TestCase):
         # If data were a QuerySet, it would be reevaluated here and give "red"
         # instead of the original value.
         self.assertEqual(data, [blue])
+
+    def test_empty_fields(self):
+        """An empty list of fields returns an empty dict."""
+        instance = ColourfulItem.objects.create()
+        self.assertEqual(model_to_dict(instance, fields=[]), {})
+
+    def test_fields(self):
+        instance = ColourfulItem.objects.create()
+        self.assertEqual(sorted(model_to_dict(instance, fields=['id'])), ['id'])
+
+    def test_exclude(self):
+        instance = ColourfulItem.objects.create()
+        self.assertEqual(model_to_dict(instance, exclude=['id', 'name', 'colours']), {})

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/forms/models\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 model_forms.tests
cat coverage.cover
git checkout e6588aa4e793b7f56f4cadbfa155b581e0efc59a
git apply /root/pre_state.patch
