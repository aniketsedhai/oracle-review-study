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
index 717e865..e439b30 100644
--- a/tests/test_config.py
+++ b/tests/test_config.py
@@ -9,6 +9,7 @@
     :license: BSD, see LICENSE for details.
 """
 
+import sys
 from unittest import mock
 
 import pytest
@@ -390,3 +391,46 @@ def test_nitpick_ignore_regex_fullmatch(app, status, warning):
     assert len(warning) == len(nitpick_warnings)
     for actual, expected in zip(warning, nitpick_warnings):
         assert expected in actual
+
+
+@pytest.mark.parametrize('reqversion,extversion,ok', [
+    ('0.6', '0.10', True),
+    ('0.6.0', '0.10.0', True),
+    ('0.6', '0.6', True),
+    ('0.6', '0.6.1', True),
+    ('0.6', '0.5', False),
+    ('0.10', '0.9', False),
+    ('1', '10', True),
+    ('1.0', '10.0', True),
+    ('1.2.3', '1.10.0', True),
+    ('1.10', '1.9', False),
+    ('2', '10', True),
+    ('0.6', 'unknown version', False),
+])
+def test_needs_extensions(make_app, tempdir, reqversion, extversion, ok):
+    (tempdir / 'conf.py').write_text(
+        'extensions = ["dummy_ext"]\n'
+        'needs_extensions = {"dummy_ext": %r}\n' % reqversion
+    )
+    (tempdir / 'dummy_ext.py').write_text(
+        'def setup(app):\n'
+        '    return {"version": %r}\n' % extversion
+    )
+    sys.path.insert(0, str(tempdir))
+    try:
+        if ok:
+            make_app(srcdir=path(tempdir))
+        else:
+            with pytest.raises(VersionRequirementError):
+                make_app(srcdir=path(tempdir))
+    finally:
+        sys.path.remove(str(tempdir))
+        sys.modules.pop('dummy_ext', None)
+
+
+def test_needs_extensions_not_loaded(make_app, tempdir):
+    (tempdir / 'conf.py').write_text(
+        'needs_extensions = {"dummy_ext": "1.0"}\n'
+    )
+    app = make_app(srcdir=path(tempdir))
+    assert 'dummy_ext extension is required by needs_extensions settings' in app._warning.getvalue()

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/extension\.py)' -m tox -epy39 -v -- tests/test_config.py
cat coverage.cover
git checkout 81a4fd973d4cfcb25d01a7b0be62cdb28f82406d
git apply /root/pre_state.patch
