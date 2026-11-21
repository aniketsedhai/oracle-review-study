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
diff --git a/tests/auth_tests/test_auth_backends.py b/tests/auth_tests/test_auth_backends.py
index a535f32..6f87a5d 100644
--- a/tests/auth_tests/test_auth_backends.py
+++ b/tests/auth_tests/test_auth_backends.py
@@ -2,6 +2,7 @@ import sys
 from datetime import date
 from unittest import mock
 
+from django.conf import settings
 from django.contrib.auth import (
     BACKEND_SESSION_KEY,
     SESSION_KEY,
@@ -932,3 +933,81 @@ class AllowAllUsersModelBackendTest(TestCase):
         request.session = self.client.session
         user = get_user(request)
         self.assertEqual(user, self.user)
+
+
+class SessionAuthHashSecretKeyFallbacksTests(TestCase):
+    """
+    Sessions created with an old SECRET_KEY remain valid while that key is
+    listed in SECRET_KEY_FALLBACKS.
+    """
+
+    @classmethod
+    def setUpTestData(cls):
+        cls.user = User.objects.create_user("test", "test@example.com", "test")
+
+    def _login_with_secret(self, secret):
+        with override_settings(SECRET_KEY=secret, SECRET_KEY_FALLBACKS=[]):
+            self.assertTrue(
+                self.client.login(username="test", password="test")
+            )
+            session = self.client.session
+            session.save()
+            return session.session_key
+
+    def _get_user_with_settings(self, session_key, **settings_overrides):
+        self.client.cookies[settings.SESSION_COOKIE_NAME] = session_key
+        request = HttpRequest()
+        request.session = self.client.session
+        with override_settings(**settings_overrides):
+            return get_user(request)
+
+    @override_settings(
+        SECRET_KEY="new_secret_key",
+        SECRET_KEY_FALLBACKS=["old_secret_key"],
+    )
+    def test_session_valid_with_secret_key_fallback(self):
+        session_key = self._login_with_secret("old_secret_key")
+        user = self._get_user_with_settings(session_key)
+        self.assertIsInstance(user, User)
+        self.assertEqual(user.pk, self.user.pk)
+
+    @override_settings(
+        SECRET_KEY="new_secret_key",
+        SECRET_KEY_FALLBACKS=["old_secret_key"],
+    )
+    def test_session_invalid_without_secret_key_fallback(self):
+        session_key = self._login_with_secret("old_secret_key")
+        user = self._get_user_with_settings(
+            session_key, SECRET_KEY_FALLBACKS=[]
+        )
+        self.assertIsInstance(user, AnonymousUser)
+
+    @override_settings(
+        SECRET_KEY="new_secret_key",
+        SECRET_KEY_FALLBACKS=["old_secret_key"],
+    )
+    def test_session_valid_with_current_secret_key(self):
+        session_key = self._login_with_secret("new_secret_key")
+        user = self._get_user_with_settings(session_key)
+        self.assertIsInstance(user, User)
+        self.assertEqual(user.pk, self.user.pk)
+
+    @override_settings(
+        SECRET_KEY="new_secret_key",
+        SECRET_KEY_FALLBACKS=["old_secret_key"],
+    )
+    def test_session_invalid_with_unrelated_secret_key(self):
+        session_key = self._login_with_secret("other_secret_key")
+        user = self._get_user_with_settings(session_key)
+        self.assertIsInstance(user, AnonymousUser)
+
+    @override_settings(
+        SECRET_KEY="new_secret_key",
+        SECRET_KEY_FALLBACKS=["old_secret_key"],
+    )
+    def test_session_invalid_after_password_change(self):
+        session_key = self._login_with_secret("old_secret_key")
+        self.user.set_password("new_password")
+        self.user.save()
+        user = self._get_user_with_settings(session_key)
+        self.assertIsInstance(user, AnonymousUser)
diff --git a/tests/auth_tests/test_basic.py b/tests/auth_tests/test_basic.py
index 4b491e5..dbc9cb7 100644
--- a/tests/auth_tests/test_basic.py
+++ b/tests/auth_tests/test_basic.py
@@ -5,6 +5,7 @@ from django.db import IntegrityError
 from django.http import HttpRequest
 from django.test import TestCase, override_settings
 from django.utils import translation
+from django.utils.crypto import salted_hmac
 
 from .models import CustomUser
 
@@ -138,3 +139,64 @@ class TestGetUser(TestCase):
         user = get_user(request)
         self.assertIsInstance(user, User)
         self.assertEqual(user.username, created_user.username)
+
+
+class GetSessionAuthHashTests(TestCase):
+    @override_settings(
+        SECRET_KEY="new_secret_key",
+        SECRET_KEY_FALLBACKS=["old_secret_key"],
+    )
+    def test_get_session_auth_hash_uses_secret_key(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        key_salt = "django.contrib.auth.models.AbstractBaseUser.get_session_auth_hash"
+        expected = salted_hmac(
+            key_salt,
+            user.password,
+            secret="new_secret_key",
+            algorithm="sha256",
+        ).hexdigest()
+        self.assertEqual(user.get_session_auth_hash(), expected)
+
+    @override_settings(
+        SECRET_KEY="new_secret_key",
+        SECRET_KEY_FALLBACKS=["old_secret_key"],
+    )
+    def test_get_session_auth_hash_uses_secret_key_fallbacks(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        key_salt = "django.contrib.auth.models.AbstractBaseUser.get_session_auth_hash"
+        old_hash = salted_hmac(
+            key_salt,
+            user.password,
+            secret="old_secret_key",
+            algorithm="sha256",
+        ).hexdigest()
+        new_hash = salted_hmac(
+            key_salt,
+            user.password,
+            secret="new_secret_key",
+            algorithm="sha256",
+        ).hexdigest()
+        self.assertNotEqual(old_hash, new_hash)
+        self.assertEqual(
+            user.get_session_auth_hash(secret="old_secret_key"),
+            old_hash,
+        )
+        self.assertEqual(
+            user.get_session_auth_hash(secret="new_secret_key"),
+            new_hash,
+        )
+
+    @override_settings(
+        SECRET_KEY="new_secret_key",
+        SECRET_KEY_FALLBACKS=["old_secret_key"],
+    )
+    def test_get_session_auth_hash_ignores_secret_key_fallbacks_by_default(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        key_salt = "django.contrib.auth.models.AbstractBaseUser.get_session_auth_hash"
+        old_hash = salted_hmac(
+            key_salt,
+            user.password,
+            secret="old_secret_key",
+            algorithm="sha256",
+        ).hexdigest()
+        self.assertNotEqual(user.get_session_auth_hash(), old_hash)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/auth/base_user\.py|django/contrib/auth/__init__\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 auth_tests.test_auth_backends auth_tests.test_basic
cat coverage.cover
git checkout 9b224579875e30203d079cc2fee83b116d98eb78
git apply /root/pre_state.patch
