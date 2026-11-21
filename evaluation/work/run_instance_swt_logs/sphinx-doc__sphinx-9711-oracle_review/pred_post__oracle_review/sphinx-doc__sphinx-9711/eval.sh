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
diff --git a/sphinx/extension.py b/sphinx/extension.py
--- a/sphinx/extension.py
+++ b/sphinx/extension.py
@@ -10,6 +10,8 @@
 
 from typing import TYPE_CHECKING, Any, Dict
 
+from packaging.version import InvalidVersion, Version
+
 from sphinx.config import Config
 from sphinx.errors import VersionRequirementError
 from sphinx.locale import __
@@ -51,7 +53,18 @@ def verify_needs_extensions(app: "Sphinx", config: Config) -> None:
                               'but it is not loaded.'), extname)
             continue
 
-        if extension.version == 'unknown version' or reqversion > extension.version:
+        fulfilled = True
+        if extension.version == 'unknown version':
+            fulfilled = False
+        else:
+            try:
+                if Version(reqversion) > Version(extension.version):
+                    fulfilled = False
+            except InvalidVersion:
+                if reqversion > extension.version:
+                    fulfilled = False
+
+        if not fulfilled:
             raise VersionRequirementError(__('This project needs the extension %s at least in '
                                              'version %s and therefore cannot be built with '
                                              'the loaded version (%s).') %

EOF_114329324912
git apply -v - <<'EOF_114329324912'
diff --git a/tests/test_extension.py b/tests/test_extension.py
new file mode 100644
index 0000000..edce2cd
--- /dev/null
+++ b/tests/test_extension.py
@@ -0,0 +1,56 @@
+"""
+    test_extension
+    ~~~~~~~~~~~~~~
+
+    Test the sphinx.extension module.
+
+    :copyright: Copyright 2007-2021 by the Sphinx team, see AUTHORS.
+    :license: BSD, see LICENSE for details.
+"""
+
+import pytest
+
+from sphinx.errors import VersionRequirementError
+from sphinx.testing.path import path
+
+
+def _make_app(make_app, tmp_path, needs_extensions, ext_version='0.10.0'):
+    srcdir = tmp_path / 'src'
+    srcdir.mkdir()
+    # A dummy extension whose reported version is controlled by the test, so
+    # that the version comparison is exercised independently of the version of
+    # any real extension bundled with Sphinx.
+    (srcdir / 'myext.py').write_text(
+        'def setup(app):\n'
+        '    return {"version": %r}\n' % (ext_version,)
+    )
+    (srcdir / 'conf.py').write_text(
+        'import sys\n'
+        'sys.path.insert(0, %r)\n'
+        'extensions = ["myext"]\n'
+        'needs_extensions = %r\n' % (str(srcdir), needs_extensions)
+    )
+    (srcdir / 'index.rst').write_text('test\n====\n')
+    return make_app(srcdir=path(str(srcdir)))
+
+
+def test_needs_extensions_accepts_newer_version(make_app, tmp_path):
+    # A loaded version of 0.10.0 must satisfy a requirement of 0.6
+    # (string comparison would incorrectly reject it: '0.6' > '0.10.0').
+    app = _make_app(make_app, tmp_path, {'myext': '0.6'}, ext_version='0.10.0')
+    assert app.extensions['myext'].version == '0.10.0'
+
+
+def test_needs_extensions_accepts_equal_version(make_app, tmp_path):
+    app = _make_app(make_app, tmp_path, {'myext': '0.10.0'}, ext_version='0.10.0')
+    assert app.extensions['myext'].version == '0.10.0'
+
+
+def test_needs_extensions_rejects_older_version(make_app, tmp_path):
+    with pytest.raises(VersionRequirementError):
+        _make_app(make_app, tmp_path, {'myext': '0.11.0'}, ext_version='0.10.0')
+
+
+def test_needs_extensions_unknown_extension(make_app, tmp_path):
+    app = _make_app(make_app, tmp_path, {'sphinx.ext.nonexistent': '1.0'})
+    assert 'sphinx.ext.nonexistent' not in app.extensions

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/extension\.py)' -m tox -epy39 -v -- tests/test_extension.py
cat coverage.cover
git checkout 81a4fd973d4cfcb25d01a7b0be62cdb28f82406d
git apply /root/pre_state.patch
