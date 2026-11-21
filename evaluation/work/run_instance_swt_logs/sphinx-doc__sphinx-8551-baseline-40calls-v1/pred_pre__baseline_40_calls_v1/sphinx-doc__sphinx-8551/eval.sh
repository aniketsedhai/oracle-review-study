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
index 2dc97be..c44a47f 100644
--- a/tests/test_domain_py.py
+++ b/tests/test_domain_py.py
@@ -865,3 +865,30 @@ def test_warn_missing_reference(app, status, warning):
     assert 'index.rst:6: WARNING: undefined label: no-label' in warning.getvalue()
     assert ('index.rst:6: WARNING: Failed to create a cross reference. A title or caption not found: existing-label'
             in warning.getvalue())
+
+
+@pytest.mark.sphinx('dummy', testroot='domain-py')
+def test_type_field_links_use_current_module(app, status, warning):
+    """Type fields (:param:, :type:, :rtype:) should resolve unqualified names
+    relative to the current module, like explicit cross-references do."""
+    text = (".. py:class:: mod.A\n"
+            ".. py:class:: mod.submod.A\n"
+            "\n"
+            ".. py:currentmodule:: mod.submod\n"
+            "\n"
+            ".. py:function:: f()\n"
+            "\n"
+            "   :param A a:\n"
+            "   :type a: A\n"
+            "   :rtype: A\n")
+    doctree = restructuredtext.parse(app, text)
+
+    refnodes = list(doctree.traverse(pending_xref))
+    assert len(refnodes) == 3
+    for refnode in refnodes:
+        assert_node(refnode, pending_xref, refdomain='py', reftype='class',
+                    reftarget='A', **{'py:module': 'mod.submod'})
+        assert 'refspecific' in refnode
+
+    # the type fields must not produce ambiguous lookup warnings
+    assert 'more than one target found' not in warning.getvalue()

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/util/docfields\.py|sphinx/domains/python\.py)' -m tox -epy39 -v -- tests/test_domain_py.py
cat coverage.cover
git checkout 57ed10c68057c96491acbd3e62254ccfaf9e3861
git apply /root/pre_state.patch
