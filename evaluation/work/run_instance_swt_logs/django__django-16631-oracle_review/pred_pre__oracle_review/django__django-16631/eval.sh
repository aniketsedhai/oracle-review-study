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
index 4b491e5..07ae389 100644
--- a/tests/auth_tests/test_basic.py
+++ b/tests/auth_tests/test_basic.py
@@ -1,3 +1,4 @@
+from django.conf import settings
 from django.contrib.auth import get_user, get_user_model
 from django.contrib.auth.models import AnonymousUser, User
 from django.core.exceptions import ImproperlyConfigured
@@ -138,3 +139,36 @@ class TestGetUser(TestCase):
         user = get_user(request)
         self.assertIsInstance(user, User)
         self.assertEqual(user.username, created_user.username)
+
+
+class SessionAuthHashSecretKeyFallbacksTests(TestCase):
+    def _login_and_get_session(self, username="testuser"):
+        User.objects.create_user(username, "test@example.com", "testpw")
+        self.assertTrue(self.client.login(username=username, password="testpw"))
+        return self.client.session
+
+    @override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_session_survives_secret_key_rotation(self):
+        # A session created with the old secret key remains valid after the
+        # key is rotated and the old value is kept in SECRET_KEY_FALLBACKS.
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            session = self._login_and_get_session()
+            session_key = session.session_key
+        self.client.cookies[settings.SESSION_COOKIE_NAME] = session_key
+        request = HttpRequest()
+        request.session = self.client.session
+        user = get_user(request)
+        self.assertIsInstance(user, User)
+        self.assertEqual(user.username, "testuser")
+
+    @override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_session_invalidated_when_fallback_removed(self):
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            session = self._login_and_get_session()
+            session_key = session.session_key
+        self.client.cookies[settings.SESSION_COOKIE_NAME] = session_key
+        with override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=[]):
+            request = HttpRequest()
+            request.session = self.client.session
+            user = get_user(request)
+        self.assertIsInstance(user, AnonymousUser)
diff --git a/tests/auth_tests/test_models.py b/tests/auth_tests/test_models.py
index fe1afcb..98db817 100644
--- a/tests/auth_tests/test_models.py
+++ b/tests/auth_tests/test_models.py
@@ -236,6 +236,49 @@ class AbstractBaseUserTests(SimpleTestCase):
         user = CustomEmailField()
         self.assertEqual(user.get_email_field_name(), "email_address")
 
+    @override_settings(SECRET_KEY="secret")
+    def test_get_session_auth_hash(self):
+        user = User(password="some-password")
+        hash_ = user.get_session_auth_hash()
+        self.assertIsInstance(hash_, str)
+        self.assertEqual(len(hash_), 64)
+        # The hash is deterministic for a given password and secret.
+        self.assertEqual(hash_, user.get_session_auth_hash())
+
+    @override_settings(SECRET_KEY="secret")
+    def test_get_session_auth_hash_uses_secret_key(self):
+        user = User(password="some-password")
+        with override_settings(SECRET_KEY="other-secret"):
+            other_hash = user.get_session_auth_hash()
+        self.assertNotEqual(user.get_session_auth_hash(), other_hash)
+
+    @override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_get_session_auth_hash_fallback(self):
+        user = User(password="some-password")
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            old_hash = user.get_session_auth_hash()
+        self.assertEqual(user.get_session_auth_hash(), old_hash)
+
+    @override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_get_session_auth_hash_fallback_multiple(self):
+        user = User(password="some-password")
+        with override_settings(
+            SECRET_KEY="oldsecret2", SECRET_KEY_FALLBACKS=["oldsecret"]
+        ):
+            old_hash = user.get_session_auth_hash()
+        with override_settings(
+            SECRET_KEY="secret", SECRET_KEY_FALLBACKS=["oldsecret2", "oldsecret"]
+        ):
+            self.assertEqual(user.get_session_auth_hash(), old_hash)
+
+    @override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_get_session_auth_hash_no_fallback_match(self):
+        user = User(password="some-password")
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            old_hash = user.get_session_auth_hash()
+        with override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=["other"]):
+            self.assertNotEqual(user.get_session_auth_hash(), old_hash)
+
 
 class AbstractUserTestCase(TestCase):
     def test_email_user(self):

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/auth/__init__\.py|django/contrib/auth/base_user\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 auth_tests.test_basic auth_tests.test_models
cat coverage.cover
git checkout 9b224579875e30203d079cc2fee83b116d98eb78
git apply /root/pre_state.patch
