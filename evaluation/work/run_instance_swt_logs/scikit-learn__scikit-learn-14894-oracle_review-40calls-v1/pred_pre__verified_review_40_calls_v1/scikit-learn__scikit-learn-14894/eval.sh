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
diff --git a/sklearn/svm/tests/test_svm.py b/sklearn/svm/tests/test_svm.py
index 6ba1418..cc076d8 100644
--- a/sklearn/svm/tests/test_svm.py
+++ b/sklearn/svm/tests/test_svm.py
@@ -1207,3 +1207,35 @@ def test_n_support_oneclass_svr():
     assert reg.n_support_ == reg.support_vectors_.shape[0]
     assert reg.n_support_.size == 1
     assert reg.n_support_ == 4
+
+
+def test_svr_sparse_empty_support_vectors():
+    # Non-regression test for ZeroDivisionError in _sparse_fit when the
+    # support_vectors_ attribute is empty (no support vectors found).
+    # See issue about SVR with sparse input and empty support vectors.
+    x_train = np.array([[0, 1, 0, 0],
+                        [0, 0, 0, 1],
+                        [0, 0, 1, 0],
+                        [0, 0, 0, 1]])
+    y_train = np.array([0.04, 0.04, 0.10, 0.16])
+    model = svm.SVR(C=316.227766017, cache_size=200, coef0=0.0, degree=3,
+                    epsilon=0.1, gamma=1.0, kernel='linear', max_iter=15000,
+                    shrinking=True, tol=0.001, verbose=False)
+
+    # dense fit works and yields no support vectors
+    model.fit(x_train, y_train)
+    assert model.support_vectors_.shape[0] == 0
+    assert model.dual_coef_.shape == (1, 0)
+
+    # sparse fit should not raise and should be consistent with dense fit
+    xtrain = sparse.csr_matrix(x_train)
+    model.fit(xtrain, y_train)
+    assert model.support_vectors_.shape[0] == 0
+    assert model.dual_coef_.shape == (1, 0)
+    assert model.dual_coef_.nnz == 0
+    assert model.n_support_[0] == 0
+
+    # predictions should still work for both dense and sparse inputs
+    pred_dense = model.predict(x_train)
+    pred_sparse = model.predict(xtrain)
+    assert_array_almost_equal(pred_dense, pred_sparse)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(sklearn/svm/base\.py)' -m pytest --no-header -rA  -p no:cacheprovider sklearn/svm/tests/test_svm.py
cat coverage.cover
git checkout fdbaa58acbead5a254f2e6d597dc1ab3b947f4c6
git apply /root/pre_state.patch
