#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 81a4fd973d4cfcb25d01a7b0be62cdb28f82406d >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 81a4fd973d4cfcb25d01a7b0be62cdb28f82406d
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .[test]
git apply -v - <<'EOF_114329324912'
diff --git a/tests/test_config.py b/tests/test_config.py
index 717e865..933c5a4 100644
--- a/tests/test_config.py
+++ b/tests/test_config.py
@@ -390,3 +390,18 @@ def test_nitpick_ignore_regex_fullmatch(app, status, warning):
     assert len(warning) == len(nitpick_warnings)
     for actual, expected in zip(warning, nitpick_warnings):
         assert expected in actual
+
+
+@pytest.mark.sphinx('html', testroot='config')
+def test_needs_extensions(make_app, app_params):
+    args, kwargs = app_params
+    # version comparison is done as versions, not as strings
+    # (e.g. '0.10' is newer than '0.6')
+    make_app(*args, confoverrides={'needs_extensions': {
+        'sphinx.ext.autodoc': '0.6',
+    }}, **kwargs)
+
+    with pytest.raises(VersionRequirementError):
+        make_app(*args, confoverrides={'needs_extensions': {
+            'sphinx.ext.autodoc': '999',
+        }}, **kwargs)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/extension\.py)' -m tox -epy39 -v -- tests/test_config.py
cat coverage.cover
git checkout 81a4fd973d4cfcb25d01a7b0be62cdb28f82406d
git apply /root/pre_state.patch
