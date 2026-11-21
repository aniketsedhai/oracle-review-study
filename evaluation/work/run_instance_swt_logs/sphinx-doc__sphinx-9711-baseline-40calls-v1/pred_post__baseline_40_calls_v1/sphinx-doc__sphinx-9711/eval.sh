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
index 0000000..70fbb0e
--- /dev/null
+++ b/tests/test_extension.py
@@ -0,0 +1,108 @@
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
+from sphinx.extension import Extension, verify_needs_extensions
+
+
+class _FakeConfig:
+    def __init__(self, needs_extensions):
+        self.needs_extensions = needs_extensions
+
+
+class _FakeApp:
+    def __init__(self, extensions):
+        self.extensions = extensions
+
+
+def _make_app(extname, version):
+    return _FakeApp({extname: Extension(extname, None, version=version)})
+
+
+@pytest.mark.parametrize(
+    'reqversion,loadedversion',
+    [
+        # numeric comparison, not string comparison (the reported bug)
+        ('0.6', '0.10'),
+        ('0.6.0', '0.10.0'),
+        ('0.9', '0.10'),
+        ('1.0', '10.0'),
+        ('1.0', '2.0'),
+        # equal versions are accepted
+        ('0.6', '0.6'),
+        ('0.10', '0.10'),
+        ('1.2.3', '1.2.3'),
+        # loaded version is newer
+        ('0.6', '0.7'),
+        ('0.6', '1.0'),
+        ('1.2', '1.10'),
+        ('1.2.3', '1.2.10'),
+        ('1.2.3', '1.3.0'),
+        ('1.2.3', '2.0.0'),
+        # pre-release / post-release style versions
+        ('1.0', '1.0.1'),
+        ('1.0', '1.0.post1'),
+        ('1.0', '1.0.dev1'),
+    ],
+)
+def test_needs_extensions_accepts_newer_versions(reqversion, loadedversion):
+    app = _make_app('dummy', loadedversion)
+    config = _FakeConfig({'dummy': reqversion})
+    # should not raise
+    verify_needs_extensions(app, config)
+
+
+@pytest.mark.parametrize(
+    'reqversion,loadedversion',
+    [
+        ('0.10', '0.6'),
+        ('0.10.0', '0.6.0'),
+        ('1.0', '0.9'),
+        ('2.0', '1.0'),
+        ('1.10', '1.2'),
+        ('1.2.10', '1.2.3'),
+        ('1.3.0', '1.2.3'),
+        ('2.0.0', '1.2.3'),
+        ('1.0.1', '1.0'),
+        ('1.0.post1', '1.0'),
+    ],
+)
+def test_needs_extensions_rejects_older_versions(reqversion, loadedversion):
+    app = _make_app('dummy', loadedversion)
+    config = _FakeConfig({'dummy': reqversion})
+    with pytest.raises(VersionRequirementError) as excinfo:
+        verify_needs_extensions(app, config)
+    assert 'dummy' in str(excinfo.value)
+    assert reqversion in str(excinfo.value)
+    assert loadedversion in str(excinfo.value)
+
+
+def test_needs_extensions_unknown_version():
+    app = _make_app('dummy', 'unknown version')
+    config = _FakeConfig({'dummy': '0.1'})
+    with pytest.raises(VersionRequirementError):
+        verify_needs_extensions(app, config)
+
+
+def test_needs_extensions_missing_extension(warning):
+    app = _FakeApp({})
+    config = _FakeConfig({'dummy': '0.1'})
+    # missing extension only warns, does not raise
+    verify_needs_extensions(app, config)
+    assert 'dummy' in warning.getvalue()
+
+
+def test_needs_extensions_none():
+    app = _FakeApp({})
+    config = _FakeConfig(None)
+    # nothing to check
+    verify_needs_extensions(app, config)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/extension\.py)' -m tox -epy39 -v -- tests/test_extension.py
cat coverage.cover
git checkout 81a4fd973d4cfcb25d01a7b0be62cdb28f82406d
git apply /root/pre_state.patch
