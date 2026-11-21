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
index 0000000..c40aaaa
--- /dev/null
+++ b/tests/test_extension.py
@@ -0,0 +1,129 @@
+"""
+    test_extension
+    ~~~~~~~~~~~~~~
+
+    Test the sphinx.extension module, in particular the handling of the
+    ``needs_extensions`` configuration value.
+
+    :copyright: Copyright 2007-2021 by the Sphinx team, see AUTHORS.
+    :license: BSD, see LICENSE for details.
+"""
+
+from unittest import mock
+
+import pytest
+
+from sphinx.errors import VersionRequirementError
+from sphinx.extension import verify_needs_extensions
+from sphinx.testing.path import path
+
+
+@pytest.fixture
+def make_app_with_empty_project(make_app, tempdir):
+    (tempdir / 'conf.py').write_text('')
+
+    def _make_app(*args, **kw):
+        kw.setdefault('srcdir', path(tempdir))
+        return make_app(*args, **kw)
+    return _make_app
+
+
+def _make_extension(version):
+    extension = mock.Mock()
+    extension.version = version
+    return extension
+
+
+def _verify(version, reqversion):
+    """Run verify_needs_extensions() with a fake extension of *version*."""
+    app = mock.Mock()
+    app.extensions = {'dummy': _make_extension(version)}
+    config = mock.Mock()
+    config.needs_extensions = {'dummy': reqversion}
+    verify_needs_extensions(app, config)
+
+
+@pytest.mark.parametrize('version,reqversion', [
+    # equal versions are fine
+    ('0.6', '0.6'),
+    ('0.6.0', '0.6.0'),
+    ('1.0', '1.0'),
+    # loaded version is newer (numeric comparison, not string comparison)
+    ('0.10', '0.6'),
+    ('0.10.0', '0.6.0'),
+    ('0.10', '0.9'),
+    ('0.10.0', '0.9.0'),
+    ('0.10', '0.6.0'),
+    ('1.0', '0.10'),
+    ('1.10', '1.9'),
+    ('2.0', '1.10'),
+    ('10.0', '9.0'),
+    ('0.6.1', '0.6'),
+    ('0.6', '0.6.0'),
+])
+def test_needs_extensions_ok(version, reqversion):
+    # should not raise
+    _verify(version, reqversion)
+
+
+@pytest.mark.parametrize('version,reqversion', [
+    ('0.6', '0.10'),
+    ('0.6.0', '0.10.0'),
+    ('0.9', '0.10'),
+    ('0.9.0', '0.10.0'),
+    ('0.6', '0.6.1'),
+    ('0.10', '1.0'),
+    ('1.9', '1.10'),
+    ('9.0', '10.0'),
+])
+def test_needs_extensions_too_old(version, reqversion):
+    with pytest.raises(VersionRequirementError):
+        _verify(version, reqversion)
+
+
+def test_needs_extensions_unknown_version():
+    with pytest.raises(VersionRequirementError):
+        _verify('unknown version', '0.6')
+
+
+def test_needs_extensions_not_loaded():
+    app = mock.Mock()
+    app.extensions = {}
+    config = mock.Mock()
+    config.needs_extensions = {'dummy': '0.6'}
+    with mock.patch('sphinx.extension.logger') as logger:
+        verify_needs_extensions(app, config)
+    assert logger.warning.called
+
+
+def test_needs_extensions_none():
+    app = mock.Mock()
+    app.extensions = {}
+    config = mock.Mock()
+    config.needs_extensions = None
+    # should not raise nor warn
+    with mock.patch('sphinx.extension.logger') as logger:
+        verify_needs_extensions(app, config)
+    assert not logger.warning.called
+
+
+def test_needs_extensions_via_app(make_app_with_empty_project):
+    """Integration test: a newer extension version satisfies a lower requirement."""
+    make_app = make_app_with_empty_project
+
+    def setup(app):
+        return {'version': '0.10.0', 'parallel_read_safe': True}
+
+    with mock.patch.dict('sys.modules', {'dummy_ext': mock.Mock(setup=setup)}):
+        # 0.10.0 >= 0.6.0 (string comparison would wrongly reject this)
+        make_app(confoverrides={
+            'extensions': ['dummy_ext'],
+            'needs_extensions': {'dummy_ext': '0.6.0'},
+        })
+
+        # 0.10.0 < 1.0.0
+        with pytest.raises(VersionRequirementError):
+            make_app(confoverrides={
+                'extensions': ['dummy_ext'],
+                'needs_extensions': {'dummy_ext': '1.0.0'},
+            })

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/extension\.py)' -m tox -epy39 -v -- tests/test_extension.py
cat coverage.cover
git checkout 81a4fd973d4cfcb25d01a7b0be62cdb28f82406d
git apply /root/pre_state.patch
