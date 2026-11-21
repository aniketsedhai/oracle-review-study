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
diff --git a/tests/roots/test-ext-autodoc/target/inheritance.py b/tests/roots/test-ext-autodoc/target/inheritance.py
index ffac84b..634f76e 100644
--- a/tests/roots/test-ext-autodoc/target/inheritance.py
+++ b/tests/roots/test-ext-autodoc/target/inheritance.py
@@ -15,3 +15,12 @@ class Derived(Base):
     def inheritedmeth(self):
         # no docstring here
         pass
+
+
+class BaseWithAttr(object):
+    #: docstring for inherited attribute
+    attr = None
+
+
+class DerivedWithAttr(BaseWithAttr):
+    pass
diff --git a/tests/test_ext_autodoc.py b/tests/test_ext_autodoc.py
index 392ad1a..f0dca0c 100644
--- a/tests/test_ext_autodoc.py
+++ b/tests/test_ext_autodoc.py
@@ -649,6 +649,17 @@ def test_autodoc_inherited_members_None(app):
     assert '   .. py:method:: Derived.__str__()' in actual
 
 
+@pytest.mark.sphinx('html', testroot='ext-autodoc')
+def test_autodoc_inherited_members_with_docstring_attr(app):
+    # regression test for inherited attributes documented via comments in the
+    # base class (the docstring is cached under the base class namespace)
+    options = {"members": None,
+               "inherited-members": True}
+    actual = do_autodoc(app, 'class', 'target.inheritance.DerivedWithAttr', options)
+    assert '   .. py:attribute:: DerivedWithAttr.attr' in actual
+    assert '      docstring for inherited attribute' in actual
+
+
 @pytest.mark.sphinx('html', testroot='ext-autodoc')
 def test_autodoc_imported_members(app):
     options = {"members": None,

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/ext/autodoc/importer\.py|sphinx/ext/autodoc/__init__\.py)' -m tox -epy39 -v -- tests/roots/test-ext-autodoc/target/inheritance.py tests/test_ext_autodoc.py
cat coverage.cover
git checkout dd1615c59dc6fff633e27dbb3861f2d27e1fb976
git apply /root/pre_state.patch
