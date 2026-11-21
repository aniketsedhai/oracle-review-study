#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 82ef497a8c88f0f6e50d84520e7276bfbf65025d >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 82ef497a8c88f0f6e50d84520e7276bfbf65025d
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .[test]
git apply -v - <<'EOF_114329324912'
diff --git a/tests/test_ext_viewcode.py b/tests/test_ext_viewcode.py
index 7986409..f88a384 100644
--- a/tests/test_ext_viewcode.py
+++ b/tests/test_ext_viewcode.py
@@ -102,3 +102,39 @@ def test_local_source_files(app, status, warning):
 
     assert result.count('href="_modules/not_a_package/submodule.html#not_a_package.submodule.Class3.class_attr"') == 1
     assert result.count('This is the class attribute class_attr') == 1
+
+
+@pytest.mark.sphinx('epub', testroot='ext-viewcode')
+def test_viewcode_epub_default(app, status, warning):
+    # By default, viewcode must not generate module pages for epub builders
+    # (viewcode_enable_epub defaults to False).
+    assert app.config.viewcode_enable_epub is False
+
+    app.builder.build_all()
+
+    # no module pages are collected for the epub builder
+    assert getattr(app.env, '_viewcode_modules', {}) == {}
+    assert not (app.outdir / '_modules').exists()
+    assert not (app.outdir / '_modules' / 'index.xhtml').exists()
+    assert not (app.outdir / '_modules' / 'spam' / 'mod1.xhtml').exists()
+
+    # no [source] links are emitted into the epub documents
+    result = (app.outdir / 'index.xhtml').read_text()
+    assert 'viewcode-link' not in result
+    assert '_modules/' not in result
+
+
+@pytest.mark.sphinx('epub', testroot='ext-viewcode',
+                    confoverrides={'viewcode_enable_epub': True})
+def test_viewcode_epub_enabled(app, status, warning):
+    # When explicitly enabled, viewcode generates module pages for epub.
+    assert app.config.viewcode_enable_epub is True
+
+    app.builder.build_all()
+
+    assert (app.outdir / '_modules' / 'index.xhtml').exists()
+    assert (app.outdir / '_modules' / 'spam' / 'mod1.xhtml').exists()
+    assert (app.outdir / '_modules' / 'spam' / 'mod2.xhtml').exists()
+
+    result = (app.outdir / '_modules' / 'spam' / 'mod1.xhtml').read_text()
+    assert 'Source code for spam.mod1' in result

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/ext/viewcode\.py)' -m tox -epy39 -v -- tests/test_ext_viewcode.py
cat coverage.cover
git checkout 82ef497a8c88f0f6e50d84520e7276bfbf65025d
git apply /root/pre_state.patch
