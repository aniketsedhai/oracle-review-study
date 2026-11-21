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
diff --git a/tests/test_ext_autodoc.py b/tests/test_ext_autodoc.py
index 392ad1a..a33fc3f 100644
--- a/tests/test_ext_autodoc.py
+++ b/tests/test_ext_autodoc.py
@@ -2234,3 +2234,16 @@ def test_name_mangling(app):
         '      name of Foo',
         '',
     ]
+
+
+@pytest.mark.sphinx('html', testroot='ext-autodoc')
+def test_autodoc_inherited_members_with_attr_docstring(app):
+    # inherited attributes documented via comments in the base class should
+    # be found even though the docstring is cached under the base namespace
+    options = {"members": None,
+               "inherited-members": True}
+    actual = do_autodoc(app, 'class', 'target.typed_vars.Derived', options)
+    assert '   .. py:attribute:: Derived.attr4' in actual
+    assert '      attr4' in actual
+    assert '   .. py:attribute:: Derived.attr5' in actual
+    assert '      attr5' in actual

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/ext/autodoc/__init__\.py|sphinx/ext/autodoc/importer\.py)' -m tox -epy39 -v -- tests/test_ext_autodoc.py
cat coverage.cover
git checkout dd1615c59dc6fff633e27dbb3861f2d27e1fb976
git apply /root/pre_state.patch
