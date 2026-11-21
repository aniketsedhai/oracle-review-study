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
index f4f3169..69506b0 100644
--- a/tests/model_forms/tests.py
+++ b/tests/model_forms/tests.py
@@ -1820,6 +1820,16 @@ class ModelOneToOneFieldTests(TestCase):
         bw2 = form.save()
         self.assertEqual(bw2.score, 12)
 
+    def test_model_to_dict_empty_fields(self):
+        bw = BetterWriter.objects.create(name='Joe Better', score=10)
+        self.assertEqual(model_to_dict(bw, fields=[]), {})
+        self.assertEqual(model_to_dict(bw, exclude=[]), {
+            'id': bw.id,
+            'name': 'Joe Better',
+            'score': 10,
+            'writer_ptr': bw.writer_ptr_id,
+        })
+
     def test_onetoonefield(self):
         class WriterProfileForm(forms.ModelForm):
             class Meta:

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/forms/models\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 model_forms.tests
cat coverage.cover
git checkout e6588aa4e793b7f56f4cadbfa155b581e0efc59a
git apply /root/pre_state.patch
