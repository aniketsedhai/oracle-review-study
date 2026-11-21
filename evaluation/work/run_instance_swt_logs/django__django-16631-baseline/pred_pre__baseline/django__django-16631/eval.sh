#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 9b224579875e30203d079cc2fee83b116d98eb78 >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 9b224579875e30203d079cc2fee83b116d98eb78
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/tests/auth_tests/test_basic.py b/tests/auth_tests/test_basic.py
index 4b491e5..8ae25fb 100644
--- a/tests/auth_tests/test_basic.py
+++ b/tests/auth_tests/test_basic.py
@@ -138,3 +138,71 @@ class TestGetUser(TestCase):
         user = get_user(request)
         self.assertIsInstance(user, User)
         self.assertEqual(user.username, created_user.username)
+
+
+class TestGetSessionAuthHash(TestCase):
+    def test_get_session_auth_hash_uses_secret_key(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        with override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=[]):
+            hash_ = user.get_session_auth_hash()
+        with override_settings(SECRET_KEY="othersecret", SECRET_KEY_FALLBACKS=[]):
+            self.assertNotEqual(user.get_session_auth_hash(), hash_)
+
+    @override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_get_session_auth_hash_uses_secret_key_fallbacks(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            old_hash = user.get_session_auth_hash()
+        # The hash generated with the old secret key is still valid after
+        # rotating SECRET_KEY and moving the old value to SECRET_KEY_FALLBACKS.
+        self.assertEqual(user.get_session_auth_hash(), old_hash)
+
+    @override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_get_session_auth_hash_ignores_unrelated_fallbacks(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        with override_settings(SECRET_KEY="othersecret", SECRET_KEY_FALLBACKS=[]):
+            other_hash = user.get_session_auth_hash()
+        self.assertNotEqual(user.get_session_auth_hash(), other_hash)
+
+    @override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_get_session_auth_hash_multiple_fallbacks(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        with override_settings(SECRET_KEY="oldsecret2", SECRET_KEY_FALLBACKS=[]):
+            old_hash = user.get_session_auth_hash()
+        with override_settings(
+            SECRET_KEY="secret",
+            SECRET_KEY_FALLBACKS=["oldsecret", "oldsecret2"],
+        ):
+            self.assertEqual(user.get_session_auth_hash(), old_hash)
+
+    @override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_get_session_auth_hash_removed_fallback(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            old_hash = user.get_session_auth_hash()
+        # Once the old key is removed from SECRET_KEY_FALLBACKS, the hash is no
+        # longer valid.
+        with override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=[]):
+            self.assertNotEqual(user.get_session_auth_hash(), old_hash)
+
+
+class TestGetUserSecretKeyFallbacks(TestCase):
+    def _login_with_old_secret_key(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            self.client.force_login(user)
+        return user
+
+    @override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_get_user_with_secret_key_fallbacks(self):
+        user = self._login_with_old_secret_key()
+        request = HttpRequest()
+        request.session = self.client.session
+        self.assertEqual(get_user(request), user)
+
+    @override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=[])
+    def test_get_user_without_secret_key_fallbacks(self):
+        self._login_with_old_secret_key()
+        request = HttpRequest()
+        request.session = self.client.session
+        self.assertIsInstance(get_user(request), AnonymousUser)
diff --git a/tests/auth_tests/test_tokens.py b/tests/auth_tests/test_tokens.py
index fa82e64..fbcb07e 100644
--- a/tests/auth_tests/test_tokens.py
+++ b/tests/auth_tests/test_tokens.py
@@ -175,3 +175,16 @@ class TokenGeneratorTest(TestCase):
         p2 = PasswordResetTokenGenerator()
         p2.secret_fallbacks = []
         self.assertIs(p2.check_token(user, tk), False)
+
+    @override_settings(
+        SECRET_KEY="secret",
+        SECRET_KEY_FALLBACKS=["oldsecret"],
+    )
+    def test_check_token_secret_key_fallbacks_multiple(self):
+        user = User.objects.create_user("tokentestuser", "test2@example.com", "testpw")
+        p1 = PasswordResetTokenGenerator()
+        p1.secret = "oldsecret2"
+        tk = p1.make_token(user)
+        p2 = PasswordResetTokenGenerator()
+        p2.secret_fallbacks = ["oldsecret", "oldsecret2"]
+        self.assertIs(p2.check_token(user, tk), True)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/auth/__init__\.py|django/contrib/auth/base_user\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 auth_tests.test_basic auth_tests.test_tokens
cat coverage.cover
git checkout 9b224579875e30203d079cc2fee83b116d98eb78
git apply /root/pre_state.patch
