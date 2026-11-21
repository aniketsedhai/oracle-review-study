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
diff --git a/sphinx/builders/html/transforms.py b/sphinx/builders/html/transforms.py
--- a/sphinx/builders/html/transforms.py
+++ b/sphinx/builders/html/transforms.py
@@ -37,7 +37,7 @@ class KeyboardTransform(SphinxPostTransform):
     """
     default_priority = 400
     builders = ('html',)
-    pattern = re.compile(r'(-|\+|\^|\s+)')
+    pattern = re.compile(r'(?<=.)(-|\+|\^|\s+)(?=.)')
 
     def run(self, **kwargs: Any) -> None:
         matcher = NodeMatcher(nodes.literal, classes=["kbd"])

EOF_114329324912
git apply -v - <<'EOF_114329324912'
diff --git a/tests/test_markup.py b/tests/test_markup.py
index a2bcb2d..cc65c89 100644
--- a/tests/test_markup.py
+++ b/tests/test_markup.py
@@ -411,6 +411,127 @@ def test_samp_role(parse):
     assert_node(doctree[0], [nodes.paragraph, nodes.literal, "code   sample"])
 
 
+def test_kbd_role(parse):
+    # single keystroke
+    text = ':kbd:`space`'
+    doctree = parse(text)
+    assert_node(doctree[0], [nodes.paragraph, nodes.literal, "space"])
+
+    # compound keystroke
+    text = ':kbd:`Control+X`'
+    doctree = parse(text)
+    assert_node(doctree[0], [nodes.paragraph, nodes.literal, "Control+X"])
+
+
+@pytest.mark.parametrize('type,rst,html_expected', [
+    (
+        # single keystroke using a compound-key separator
+        'verify',
+        ':kbd:`-`',
+        '<p><kbd class="kbd docutils literal notranslate">-</kbd></p>',
+    ),
+    (
+        # single keystroke using a compound-key separator
+        'verify',
+        ':kbd:`+`',
+        '<p><kbd class="kbd docutils literal notranslate">+</kbd></p>',
+    ),
+    (
+        # single keystroke using a compound-key separator
+        'verify',
+        ':kbd:`^`',
+        '<p><kbd class="kbd docutils literal notranslate">^</kbd></p>',
+    ),
+    (
+        # compound keystroke whose last key is a separator
+        'verify',
+        ':kbd:`Shift-+`',
+        ('<p><kbd class="kbd docutils literal notranslate">'
+         '<kbd class="kbd docutils literal notranslate">Shift</kbd>'
+         '-'
+         '<kbd class="kbd docutils literal notranslate">+</kbd>'
+         '</kbd></p>'),
+    ),
+    (
+        # compound keystroke whose last key is a separator
+        'verify',
+        ':kbd:`Shift--`',
+        ('<p><kbd class="kbd docutils literal notranslate">'
+         '<kbd class="kbd docutils literal notranslate">Shift</kbd>'
+         '-'
+         '<kbd class="kbd docutils literal notranslate">-</kbd>'
+         '</kbd></p>'),
+    ),
+    (
+        # compound keystroke whose last key is a separator
+        'verify',
+        ':kbd:`Ctrl-^`',
+        ('<p><kbd class="kbd docutils literal notranslate">'
+         '<kbd class="kbd docutils literal notranslate">Ctrl</kbd>'
+         '-'
+         '<kbd class="kbd docutils literal notranslate">^</kbd>'
+         '</kbd></p>'),
+    ),
+    (
+        # compound keystroke with a separator as a standalone key
+        'verify',
+        ':kbd:`- -`',
+        ('<p><kbd class="kbd docutils literal notranslate">'
+         '<kbd class="kbd docutils literal notranslate">-</kbd>'
+         ' '
+         '<kbd class="kbd docutils literal notranslate">-</kbd>'
+         '</kbd></p>'),
+    ),
+    (
+        # compound keystroke with a separator as a standalone key
+        'verify',
+        ':kbd:`+ +`',
+        ('<p><kbd class="kbd docutils literal notranslate">'
+         '<kbd class="kbd docutils literal notranslate">+</kbd>'
+         ' '
+         '<kbd class="kbd docutils literal notranslate">+</kbd>'
+         '</kbd></p>'),
+    ),
+    (
+        # compound keystroke with a separator as a standalone key
+        'verify',
+        ':kbd:`^ ^`',
+        ('<p><kbd class="kbd docutils literal notranslate">'
+         '<kbd class="kbd docutils literal notranslate">^</kbd>'
+         ' '
+         '<kbd class="kbd docutils literal notranslate">^</kbd>'
+         '</kbd></p>'),
+    ),
+    (
+        # regular compound keystroke is still split
+        'verify',
+        ':kbd:`Control+X`',
+        ('<p><kbd class="kbd docutils literal notranslate">'
+         '<kbd class="kbd docutils literal notranslate">Control</kbd>'
+         '+'
+         '<kbd class="kbd docutils literal notranslate">X</kbd>'
+         '</kbd></p>'),
+    ),
+    (
+        # regular compound keystroke is still split
+        'verify',
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
+def test_kbd_role_html(get_verifier, type, rst, html_expected):
+    verifier = get_verifier(type)
+    verifier(rst, html_expected, None)
+
+
 def test_download_role(parse):
     # implicit
     text = ':download:`sphinx.rst`'

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sphinx/builders/html/transforms\.py)' -m tox -epy39 -v -- tests/test_markup.py
cat coverage.cover
git checkout 21698c14461d27933864d73e6fba568a154e83b3
git apply /root/pre_state.patch
