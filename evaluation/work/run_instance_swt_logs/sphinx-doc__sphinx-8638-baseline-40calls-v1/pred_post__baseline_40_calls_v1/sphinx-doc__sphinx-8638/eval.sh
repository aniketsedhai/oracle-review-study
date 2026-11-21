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
index e0c6905..30a71c5 100644
--- a/tests/test_domain_py.py
+++ b/tests/test_domain_py.py
@@ -929,3 +929,29 @@ def test_warn_missing_reference(app, status, warning):
     assert 'index.rst:6: WARNING: undefined label: no-label' in warning.getvalue()
     assert ('index.rst:6: WARNING: Failed to create a cross reference. A title or caption not found: existing-label'
             in warning.getvalue())
+
+
+@pytest.mark.sphinx('html', testroot='domain-py')
+def test_domain_py_attr_does_not_link_to_unrelated_variable(app, status, warning):
+    # An attribute documented inside a class must not be automatically linked
+    # to an unrelated variable of the same name defined elsewhere in the
+    # project (e.g. a module level variable or an attribute of another class).
+    app.builder.build_all()
+
+    domain = app.env.domains['py']
+    objects = domain.data['objects']
+
+    # sanity check: the unrelated module level variable exists
+    assert 'module_a.submodule.attr1' in objects
+    assert objects['module_a.submodule.attr1'][2] == 'attribute'
+
+    # a reference to an attribute of a class must not resolve to the
+    # module level variable of the same name
+    matches = domain.find_obj(app.env, 'module_b.submodule', 'ModTopLevel',
+                              'attr1', 'attr', 1)
+    assert matches == []
+
+    # nor should it resolve to an attribute of a different class
+    matches = domain.find_obj(app.env, 'module_b.submodule', 'ModTopLevel',
+                              'attr1', 'attr', 0)
+    assert matches == []

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/domains/python\.py)' -m tox -epy39 -v -- tests/test_domain_py.py
cat coverage.cover
git checkout 4b452338f914d4f6b54704222d70ae8a746e3db5
git apply /root/pre_state.patch
