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
index 4b491e5..daef4f1 100644
--- a/tests/auth_tests/test_basic.py
+++ b/tests/auth_tests/test_basic.py
@@ -5,6 +5,7 @@ from django.db import IntegrityError
 from django.http import HttpRequest
 from django.test import TestCase, override_settings
 from django.utils import translation
+from django.utils.crypto import salted_hmac
 
 from .models import CustomUser
 
@@ -138,3 +139,55 @@ class TestGetUser(TestCase):
         user = get_user(request)
         self.assertIsInstance(user, User)
         self.assertEqual(user.username, created_user.username)
+
+
+class GetSessionAuthHashTests(TestCase):
+    @classmethod
+    def setUpTestData(cls):
+        cls.user = User.objects.create_user(
+            "sessionauthuser", "sessionauth@example.com", "testpw"
+        )
+
+    def test_get_session_auth_hash_uses_secret_key(self):
+        with override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=[]):
+            hash_ = self.user.get_session_auth_hash()
+        self.assertEqual(
+            hash_,
+            salted_hmac(
+                "django.contrib.auth.models.AbstractBaseUser.get_session_auth_hash",
+                self.user.password,
+                secret="secret",
+                algorithm="sha256",
+            ).hexdigest(),
+        )
+
+    @override_settings(SECRET_KEY="newsecret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_get_session_auth_hash_secret_key_fallbacks(self):
+        """
+        A session auth hash generated with a fallback secret key is still
+        accepted after rotating SECRET_KEY.
+        """
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            old_hash = self.user.get_session_auth_hash()
+        self.assertNotEqual(old_hash, self.user.get_session_auth_hash())
+        self.assertTrue(self.user.check_session_auth_hash(old_hash))
+
+    @override_settings(SECRET_KEY="newsecret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_get_session_auth_hash_secret_key_fallbacks_multiple(self):
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            old_hash = self.user.get_session_auth_hash()
+        with override_settings(
+            SECRET_KEY="newsecret", SECRET_KEY_FALLBACKS=["other", "oldsecret"]
+        ):
+            self.assertTrue(self.user.check_session_auth_hash(old_hash))
+
+    @override_settings(SECRET_KEY="newsecret", SECRET_KEY_FALLBACKS=[])
+    def test_get_session_auth_hash_no_secret_key_fallbacks(self):
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            old_hash = self.user.get_session_auth_hash()
+        self.assertFalse(self.user.check_session_auth_hash(old_hash))
+
+    @override_settings(SECRET_KEY="newsecret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_get_session_auth_hash_invalid_hash(self):
+        self.assertFalse(self.user.check_session_auth_hash("invalid"))
+        self.assertFalse(self.user.check_session_auth_hash(""))
diff --git a/tests/auth_tests/test_views.py b/tests/auth_tests/test_views.py
index d15a166..d40ecd9 100644
--- a/tests/auth_tests/test_views.py
+++ b/tests/auth_tests/test_views.py
@@ -8,7 +8,12 @@ from urllib.parse import quote, urljoin
 from django.apps import apps
 from django.conf import settings
 from django.contrib.admin.models import LogEntry
-from django.contrib.auth import BACKEND_SESSION_KEY, REDIRECT_FIELD_NAME, SESSION_KEY
+from django.contrib.auth import (
+    BACKEND_SESSION_KEY,
+    REDIRECT_FIELD_NAME,
+    SESSION_KEY,
+    update_session_auth_hash,
+)
 from django.contrib.auth.forms import (
     AuthenticationForm,
     PasswordChangeForm,
@@ -875,6 +880,57 @@ class LoginTest(AuthViewsTestCase):
         self.login()
         self.assertNotEqual(original_session_key, self.client.session.session_key)
 
+    @override_settings(SECRET_KEY="newsecret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_login_session_survives_secret_key_rotation(self):
+        """
+        A session created with a secret key that has since been moved to
+        SECRET_KEY_FALLBACKS is still valid.
+        """
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            self.login()
+        self.assertEqual(self.client.get("/login/").status_code, 200)
+        self.assertEqual(self.client.session[SESSION_KEY], str(self.u1.pk))
+        # The user is still authenticated.
+        response = self.client.get("/login/")
+        self.assertEqual(response.context["user"].pk, self.u1.pk)
+
+    @override_settings(SECRET_KEY="newsecret", SECRET_KEY_FALLBACKS=[])
+    def test_login_session_invalidated_without_secret_key_fallback(self):
+        """
+        A session created with a secret key that is neither SECRET_KEY nor in
+        SECRET_KEY_FALLBACKS is invalidated.
+        """
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            self.login()
+        self.client.get("/login/")
+        self.assertNotIn(SESSION_KEY, self.client.session)
+
+    @override_settings(SECRET_KEY="newsecret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_login_session_survives_secret_key_rotation_multiple_fallbacks(self):
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            self.login()
+        with override_settings(
+            SECRET_KEY="newsecret", SECRET_KEY_FALLBACKS=["other", "oldsecret"]
+        ):
+            self.client.get("/login/")
+            self.assertEqual(self.client.session[SESSION_KEY], str(self.u1.pk))
+
+    @override_settings(SECRET_KEY="newsecret", SECRET_KEY_FALLBACKS=["oldsecret"])
+    def test_update_session_auth_hash_after_secret_key_rotation(self):
+        """
+        update_session_auth_hash() keeps the session valid after a secret key
+        rotation.
+        """
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            self.login()
+        request = HttpRequest()
+        request.session = self.client.session
+        request.user = self.u1
+        update_session_auth_hash(request, self.u1)
+        self.client.cookies[settings.SESSION_COOKIE_NAME] = request.session.session_key
+        self.client.get("/login/")
+        self.assertEqual(self.client.session[SESSION_KEY], str(self.u1.pk))
+
     def test_login_get_default_redirect_url(self):
         response = self.login(url="/login/get_default_redirect_url/")
         self.assertRedirects(response, "/custom/", fetch_redirect_response=False)

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/auth/base_user\.py|django/contrib/auth/__init__\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 auth_tests.test_basic auth_tests.test_views
cat coverage.cover
git checkout 9b224579875e30203d079cc2fee83b116d98eb78
git apply /root/pre_state.patch
