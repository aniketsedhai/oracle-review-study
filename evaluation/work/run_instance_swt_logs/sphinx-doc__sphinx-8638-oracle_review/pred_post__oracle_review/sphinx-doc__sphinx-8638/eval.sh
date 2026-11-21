#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 4b452338f914d4f6b54704222d70ae8a746e3db5 >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 4b452338f914d4f6b54704222d70ae8a746e3db5
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .[test]
git apply -v - <<'EOF_114329324912'
diff --git a/sphinx/domains/python.py b/sphinx/domains/python.py
--- a/sphinx/domains/python.py
+++ b/sphinx/domains/python.py
@@ -354,7 +354,7 @@ class PyObject(ObjectDescription):
                             'keyword', 'kwarg', 'kwparam'),
                      typerolename='class', typenames=('paramtype', 'type'),
                      can_collapse=True),
-        PyTypedField('variable', label=_('Variables'), rolename='obj',
+        PyTypedField('variable', label=_('Variables'),
                      names=('var', 'ivar', 'cvar'),
                      typerolename='class', typenames=('vartype',),
                      can_collapse=True),

EOF_114329324912
git apply -v - <<'EOF_114329324912'
diff --git a/tests/test_domain_py.py b/tests/test_domain_py.py
index e0c6905..ba81bfd 100644
--- a/tests/test_domain_py.py
+++ b/tests/test_domain_py.py
@@ -929,3 +929,38 @@ def test_warn_missing_reference(app, status, warning):
     assert 'index.rst:6: WARNING: undefined label: no-label' in warning.getvalue()
     assert ('index.rst:6: WARNING: Failed to create a cross reference. A title or caption not found: existing-label'
             in warning.getvalue())
+
+
+@pytest.mark.sphinx('dummy', testroot='domain-py')
+def test_domain_py_find_obj_does_not_match_unrelated_attributes(app, status, warning):
+    """Instance variables must not link to unrelated variables of the same name.
+
+    Regression test: a class attribute ``Foo.limit`` must not be resolved to a
+    global ``limit`` (or to ``Bar.limit``) merely because they share a name.
+    """
+    from sphinx.domains.python import ObjectEntry
+
+    app.builder.build_all()
+    domain = app.env.domains['py']
+    domain.data['objects'] = {
+        'limit': ObjectEntry('doc', 'limit', 'data', False),
+        'Foo': ObjectEntry('doc', 'Foo', 'class', False),
+        'Foo.limit': ObjectEntry('doc', 'Foo.limit', 'attribute', False),
+        'Bar': ObjectEntry('doc', 'Bar', 'class', False),
+        'Bar.limit': ObjectEntry('doc', 'Bar.limit', 'attribute', False),
+    }
+
+    def find_obj(modname, classname, name, objtype, searchmode=1):
+        return domain.find_obj(app.env, modname, classname, name, objtype, searchmode)
+
+    # With a class context, the attribute of that class must be preferred and
+    # must not be confused with the global variable or another class's attribute.
+    assert find_obj(None, 'Foo', 'limit', 'attr') == [
+        ('Foo.limit', ObjectEntry('doc', 'Foo.limit', 'attribute', False))]
+    assert find_obj(None, 'Bar', 'limit', 'attr') == [
+        ('Bar.limit', ObjectEntry('doc', 'Bar.limit', 'attribute', False))]
+
+    # Without a class context, the global variable must be preferred over the
+    # unrelated class attributes.
+    assert find_obj(None, None, 'limit', 'attr') == [
+        ('limit', ObjectEntry('doc', 'limit', 'data', False))]

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/domains/python\.py)' -m tox -epy39 -v -- tests/test_domain_py.py
cat coverage.cover
git checkout 4b452338f914d4f6b54704222d70ae8a746e3db5
git apply /root/pre_state.patch
