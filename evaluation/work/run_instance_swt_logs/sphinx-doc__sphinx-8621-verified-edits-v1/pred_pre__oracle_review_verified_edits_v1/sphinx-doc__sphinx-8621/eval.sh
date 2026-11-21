#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 21698c14461d27933864d73e6fba568a154e83b3 >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 21698c14461d27933864d73e6fba568a154e83b3
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .[test]
git apply -v - <<'EOF_114329324912'
diff --git a/tests/test_markup.py b/tests/test_markup.py
index a2bcb2d..0656fe2 100644
--- a/tests/test_markup.py
+++ b/tests/test_markup.py
@@ -572,3 +572,70 @@ def test_default_role2(app, status, warning):
     assert_node(doctree[0][1], nodes.paragraph)
     assert_node(doctree[0][1][0], nodes.inline, classes=["guilabel"])
     assert_node(doctree[0][1][1], nodes.Text)
+
+
+@pytest.mark.parametrize('rst,html_expected', [
+    (
+        # standalone separator characters are single keystrokes
+        ':kbd:`-`',
+        ('<p><kbd class="kbd docutils literal notranslate">-</kbd></p>'),
+    ),
+    (
+        ':kbd:`+`',
+        ('<p><kbd class="kbd docutils literal notranslate">+</kbd></p>'),
+    ),
+    (
+        ':kbd:`^`',
+        ('<p><kbd class="kbd docutils literal notranslate">^</kbd></p>'),
+    ),
+    (
+        # separator characters used as keystrokes in compound keystrokes
+        ':kbd:`Shift-+`',
+        ('<p><kbd class="kbd docutils literal notranslate">'
+         '<kbd class="kbd docutils literal notranslate">Shift</kbd>'
+         '-'
+         '<kbd class="kbd docutils literal notranslate">+</kbd>'
+         '</kbd></p>'),
+    ),
+    (
+        ':kbd:`Shift--`',
+        ('<p><kbd class="kbd docutils literal notranslate">'
+         '<kbd class="kbd docutils literal notranslate">Shift</kbd>'
+         '-'
+         '<kbd class="kbd docutils literal notranslate">-</kbd>'
+         '</kbd></p>'),
+    ),
+    (
+        ':kbd:`Ctrl+Shift-+`',
+        ('<p><kbd class="kbd docutils literal notranslate">'
+         '<kbd class="kbd docutils literal notranslate">Ctrl</kbd>'
+         '+'
+         '<kbd class="kbd docutils literal notranslate">Shift</kbd>'
+         '-'
+         '<kbd class="kbd docutils literal notranslate">+</kbd>'
+         '</kbd></p>'),
+    ),
+    (
+        # regular compound keystrokes still work
+        ':kbd:`Control+X`',
+        ('<p><kbd class="kbd docutils literal notranslate">'
+         '<kbd class="kbd docutils literal notranslate">Control</kbd>'
+         '+'
+         '<kbd class="kbd docutils literal notranslate">X</kbd>'
+         '</kbd></p>'),
+    ),
+    (
+        ':kbd:`M-x  M-s`',
+        ('<p><kbd class="kbd docutils literal notranslate">'
+         '<kbd class="kbd docutils literal notranslate">M</kbd>'
+         '-'
+         '<kbd class="kbd docutils literal notranslate">x</kbd>'
+         '  '
+         '<kbd class="kbd docutils literal notranslate">M</kbd>'
+         '-'
+         '<kbd class="kbd docutils literal notranslate">s</kbd>'
+         '</kbd></p>'),
+    ),
+])
+def test_kbd_role(verify, rst, html_expected):
+    verify(rst, html_expected, None)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/builders/html/transforms\.py)' -m tox -epy39 -v -- tests/test_markup.py
cat coverage.cover
git checkout 21698c14461d27933864d73e6fba568a154e83b3
git apply /root/pre_state.patch
