#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD dd1615c59dc6fff633e27dbb3861f2d27e1fb976 >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff dd1615c59dc6fff633e27dbb3861f2d27e1fb976
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .[test]
git apply -v - <<'EOF_114329324912'
diff --git a/tests/roots/test-ext-autodoc/target/inherited_attributes.py b/tests/roots/test-ext-autodoc/target/inherited_attributes.py
new file mode 100644
index 0000000..d2d2d94
--- /dev/null
+++ b/tests/roots/test-ext-autodoc/target/inherited_attributes.py
@@ -0,0 +1,7 @@
+class Base(object):
+    #: docstring of inherited class attribute
+    inherited_attr = 1
+
+
+class Derived(Base):
+    pass
diff --git a/tests/test_ext_autodoc_inherited_attributes.py b/tests/test_ext_autodoc_inherited_attributes.py
new file mode 100644
index 0000000..87b1432
--- /dev/null
+++ b/tests/test_ext_autodoc_inherited_attributes.py
@@ -0,0 +1,46 @@
+"""
+    test_ext_autodoc_inherited_attributes
+    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
+
+    Regression tests for autodoc ``:inherited-members:`` support for
+    inherited attributes (data members) documented via ``#:`` comments in a
+    base class.
+
+    :copyright: Copyright 2007-2020 by the Sphinx team, see AUTHORS.
+    :license: BSD, see LICENSE for details.
+"""
+
+import pytest
+
+from .test_ext_autodoc import do_autodoc
+
+
+@pytest.mark.sphinx('html', testroot='ext-autodoc')
+def test_autodoc_inherited_attribute(app):
+    # An attribute documented with a ``#:`` comment in a base class must be
+    # picked up (with its docstring) when documenting a subclass with
+    # ``:inherited-members:``.
+    options = {'members': None, 'inherited-members': True}
+    actual = do_autodoc(app, 'class', 'target.inherited_attributes.Derived', options)
+    assert list(actual) == [
+        '',
+        '.. py:class:: Derived()',
+        '   :module: target.inherited_attributes',
+        '',
+        '',
+        '   .. py:attribute:: Derived.inherited_attr',
+        '      :module: target.inherited_attributes',
+        '      :value: 1',
+        '',
+        '      docstring of inherited class attribute',
+        '',
+    ]
+
+
+@pytest.mark.sphinx('html', testroot='ext-autodoc')
+def test_autodoc_inherited_attribute_not_shown_without_inherited_members(app):
+    # Without ``:inherited-members:`` the inherited attribute must not be
+    # documented on the subclass.
+    options = {'members': None}
+    actual = do_autodoc(app, 'class', 'target.inherited_attributes.Derived', options)
+    assert '.. py:attribute:: Derived.inherited_attr' not in actual

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/ext/autodoc/__init__\.py|sphinx/ext/autodoc/importer\.py)' -m tox -epy39 -v -- tests/roots/test-ext-autodoc/target/inherited_attributes.py tests/test_ext_autodoc_inherited_attributes.py
cat coverage.cover
git checkout dd1615c59dc6fff633e27dbb3861f2d27e1fb976
git apply /root/pre_state.patch
