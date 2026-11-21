#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD fdbaa58acbead5a254f2e6d597dc1ab3b947f4c6 >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff fdbaa58acbead5a254f2e6d597dc1ab3b947f4c6
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -v --no-use-pep517 --no-build-isolation -e .
git apply -v - <<'EOF_114329324912'
diff --git a/sklearn/svm/base.py b/sklearn/svm/base.py
--- a/sklearn/svm/base.py
+++ b/sklearn/svm/base.py
@@ -287,11 +287,14 @@ def _sparse_fit(self, X, y, sample_weight, solver_type, kernel,
         n_SV = self.support_vectors_.shape[0]
 
         dual_coef_indices = np.tile(np.arange(n_SV), n_class)
-        dual_coef_indptr = np.arange(0, dual_coef_indices.size + 1,
-                                     dual_coef_indices.size / n_class)
-        self.dual_coef_ = sp.csr_matrix(
-            (dual_coef_data, dual_coef_indices, dual_coef_indptr),
-            (n_class, n_SV))
+        if not n_SV:
+            self.dual_coef_ = sp.csr_matrix([])
+        else:
+            dual_coef_indptr = np.arange(0, dual_coef_indices.size + 1,
+                                         dual_coef_indices.size / n_class)
+            self.dual_coef_ = sp.csr_matrix(
+                (dual_coef_data, dual_coef_indices, dual_coef_indptr),
+                (n_class, n_SV))
 
     def predict(self, X):
         """Perform regression on samples in X.

EOF_114329324912
git apply -v - <<'EOF_114329324912'
diff --git a/sklearn/svm/tests/test_sparse.py b/sklearn/svm/tests/test_sparse.py
index 7cf6e8a..191deaa 100644
--- a/sklearn/svm/tests/test_sparse.py
+++ b/sklearn/svm/tests/test_sparse.py
@@ -360,3 +360,36 @@ def test_consistent_proba():
     with ignore_warnings(category=ConvergenceWarning):
         proba_2 = a.fit(X, Y).predict_proba(X)
     assert_array_almost_equal(proba_1, proba_2)
+
+
+def test_sparse_svr_empty_support_vectors():
+    # Non-regression test for ZeroDivisionError in _sparse_fit when the
+    # support_vectors_ attribute is empty (no support vectors found).
+    # See bug report: ZeroDivisionError in _sparse_fit for SVM with empty
+    # support_vectors_.
+    x_train = np.array([[0, 1, 0, 0],
+                        [0, 0, 0, 1],
+                        [0, 0, 1, 0],
+                        [0, 0, 0, 1]])
+    y_train = np.array([0.04, 0.04, 0.10, 0.16])
+
+    model = svm.SVR(C=316.227766017, cache_size=200, coef0=0.0, degree=3,
+                    epsilon=0.1, gamma=1.0, kernel='linear', max_iter=15000,
+                    shrinking=True, tol=0.001, verbose=False)
+
+    # dense fit works and yields no support vectors
+    model.fit(x_train, y_train)
+    assert model.support_vectors_.shape[0] == 0
+    assert model.dual_coef_.shape == (1, 0)
+
+    # sparse fit should not raise and should produce an empty dual_coef_
+    model.fit(sparse.csr_matrix(x_train), y_train)
+    assert model.support_vectors_.shape[0] == 0
+    assert sparse.issparse(model.dual_coef_)
+    assert model.dual_coef_.shape == (1, 0)
+    assert model.dual_coef_.nnz == 0
+
+    # prediction should still work on both dense and sparse inputs
+    pred_dense = model.predict(x_train)
+    pred_sparse = model.predict(sparse.csr_matrix(x_train))
+    assert_array_almost_equal(pred_dense, pred_sparse)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sklearn/svm/base\.py)' -m pytest --no-header -rA  -p no:cacheprovider sklearn/svm/tests/test_sparse.py
cat coverage.cover
git checkout fdbaa58acbead5a254f2e6d597dc1ab3b947f4c6
git apply /root/pre_state.patch
