#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 193e3825645d93c73e31cdceb6d742cc6919624d >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 193e3825645d93c73e31cdceb6d742cc6919624d
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/sympy/polys/rings.py b/sympy/polys/rings.py
--- a/sympy/polys/rings.py
+++ b/sympy/polys/rings.py
@@ -616,10 +616,13 @@ def set_ring(self, new_ring):
             return new_ring.from_dict(self, self.ring.domain)
 
     def as_expr(self, *symbols):
-        if symbols and len(symbols) != self.ring.ngens:
-            raise ValueError("not enough symbols, expected %s got %s" % (self.ring.ngens, len(symbols)))
-        else:
+        if not symbols:
             symbols = self.ring.symbols
+        elif len(symbols) != self.ring.ngens:
+            raise ValueError(
+                "Wrong number of symbols, expected %s got %s" %
+                (self.ring.ngens, len(symbols))
+            )
 
         return expr_from_dict(self.as_expr_dict(), *symbols)
 

EOF_114329324912
git apply -v - <<'EOF_114329324912'
diff --git a/sympy/polys/tests/test_rings.py b/sympy/polys/tests/test_rings.py
index b396213..5ec0b56 100644
--- a/sympy/polys/tests/test_rings.py
+++ b/sympy/polys/tests/test_rings.py
@@ -270,6 +270,15 @@ def test_PolyElement_as_expr():
     R, = ring("", ZZ)
     assert R(3).as_expr() == 3
 
+def test_PolyElement_as_expr_custom_symbols():
+    R, x, y, z = ring("x,y,z", ZZ)
+    f = 3*x**2*y - x*y*z + 7*z**3 + 1
+
+    U, V, W = symbols("u,v,w")
+    g = 3*U**2*V - U*V*W + 7*W**3 + 1
+
+    assert f.as_expr(U, V, W) == g
+
 def test_PolyElement_from_expr():
     x, y, z = symbols("x,y,z")
     R, X, Y, Z = ring((x, y, z), ZZ)

EOF_114329324912
PYTHONWARNINGS='ignore::UserWarning,ignore::SyntaxWarning' python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sympy/polys/rings\.py)' bin/test -C --verbose sympy/polys/tests/test_rings.p
cat coverage.cover
git checkout 193e3825645d93c73e31cdceb6d742cc6919624d
git apply /root/pre_state.patch
