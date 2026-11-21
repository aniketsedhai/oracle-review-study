#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 57ed10c68057c96491acbd3e62254ccfaf9e3861 >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 57ed10c68057c96491acbd3e62254ccfaf9e3861
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .[test]
git apply -v - <<'EOF_114329324912'
diff --git a/tests/test_domain_py.py b/tests/test_domain_py.py
index 2dc97be..23503f6 100644
--- a/tests/test_domain_py.py
+++ b/tests/test_domain_py.py
@@ -865,3 +865,31 @@ def test_warn_missing_reference(app, status, warning):
     assert 'index.rst:6: WARNING: undefined label: no-label' in warning.getvalue()
     assert ('index.rst:6: WARNING: Failed to create a cross reference. A title or caption not found: existing-label'
             in warning.getvalue())
+
+
+@pytest.mark.sphinx('dummy', testroot='domain-py')
+def test_domain_py_info_field_xrefs_use_current_module(app, status, warning):
+    """Info field type xrefs (:type:/:rtype:) must resolve relative to the
+    current module, like explicit xref roles, instead of searching every
+    (sub)module and emitting ambiguous-lookup warnings."""
+    text = (".. py:class:: mod.A\n"
+            ".. py:class:: mod.submod.A\n"
+            "\n"
+            ".. py:currentmodule:: mod.submod\n"
+            "\n"
+            ".. py:function:: f()\n"
+            "\n"
+            "   :param A a:\n"
+            "   :rtype: A\n")
+    restructuredtext.parse(app, text)
+    app.builder.build_all()
+
+    assert "more than one target found for cross-reference 'A'" not in warning.getvalue()
+
+    doctree = app.env.get_doctree('index')
+    refnodes = list(doctree.traverse(pending_xref))
+    targets = [node['reftarget'] for node in refnodes]
+    assert targets == ['A', 'A']
+    for node in refnodes:
+        assert node['py:module'] == 'mod.submod'
+        assert node['refspecific'] is True

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/util/docfields\.py|sphinx/domains/python\.py)' -m tox -epy39 -v -- tests/test_domain_py.py
cat coverage.cover
git checkout 57ed10c68057c96491acbd3e62254ccfaf9e3861
git apply /root/pre_state.patch
