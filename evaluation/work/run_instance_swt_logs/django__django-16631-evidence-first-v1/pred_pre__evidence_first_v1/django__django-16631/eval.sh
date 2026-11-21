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
index a535f32..8e81f9b 100644
--- a/tests/auth_tests/test_auth_backends.py
+++ b/tests/auth_tests/test_auth_backends.py
@@ -4,6 +4,7 @@ from unittest import mock
 
 from django.contrib.auth import (
     BACKEND_SESSION_KEY,
+    HASH_SESSION_KEY,
     SESSION_KEY,
     _clean_credentials,
     authenticate,
@@ -23,6 +24,7 @@ from django.test import (
     modify_settings,
     override_settings,
 )
+from django.utils.crypto import salted_hmac
 from django.views.debug import technical_500_response
 from django.views.decorators.debug import sensitive_variables
 
@@ -417,6 +419,30 @@ class UUIDUserTests(TestCase):
         )
 
 
+class SessionAuthHashSecretKeyFallbacksTests(TestCase):
+    @override_settings(
+        SECRET_KEY="newsecret",
+        SECRET_KEY_FALLBACKS=["oldsecret"],
+    )
+    def test_session_survives_secret_key_rotation(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        # Simulate a session created before the secret key was rotated: the
+        # stored session auth hash was computed with the old secret key.
+        session = self.client.session
+        session[SESSION_KEY] = str(user.pk)
+        session[BACKEND_SESSION_KEY] = "django.contrib.auth.backends.ModelBackend"
+        session[HASH_SESSION_KEY] = salted_hmac(
+            "django.contrib.auth.models.AbstractBaseUser.get_session_auth_hash",
+            user.password,
+            secret="oldsecret",
+            algorithm="sha256",
+        ).hexdigest()
+        session.save()
+        request = HttpRequest()
+        request.session = session
+        self.assertEqual(get_user(request), user)
+
+
 class TestObj:
     pass
 
diff --git a/tests/auth_tests/test_basic.py b/tests/auth_tests/test_basic.py
index 4b491e5..dcb931b 100644
--- a/tests/auth_tests/test_basic.py
+++ b/tests/auth_tests/test_basic.py
@@ -5,6 +5,7 @@ from django.db import IntegrityError
 from django.http import HttpRequest
 from django.test import TestCase, override_settings
 from django.utils import translation
+from django.utils.crypto import salted_hmac
 
 from .models import CustomUser
 
@@ -121,6 +122,23 @@ class BasicTestCase(TestCase):
             self.assertEqual(User._meta.verbose_name_plural, "usuarios")
 
 
+class GetSessionAuthHashTests(TestCase):
+    @override_settings(
+        SECRET_KEY="newsecret",
+        SECRET_KEY_FALLBACKS=["oldsecret"],
+    )
+    def test_get_session_auth_hash_secret_key_fallbacks(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        key_salt = "django.contrib.auth.models.AbstractBaseUser.get_session_auth_hash"
+        old_session_auth_hash = salted_hmac(
+            key_salt,
+            user.password,
+            secret="oldsecret",
+            algorithm="sha256",
+        ).hexdigest()
+        self.assertEqual(user.get_session_auth_hash(), old_session_auth_hash)
+
+
 class TestGetUser(TestCase):
     def test_get_user_anonymous(self):
         request = HttpRequest()
diff --git a/tests/utils_tests/test_crypto.py b/tests/utils_tests/test_crypto.py
index ed3ed25..d69a7e2 100644
--- a/tests/utils_tests/test_crypto.py
+++ b/tests/utils_tests/test_crypto.py
@@ -1,7 +1,7 @@
 import hashlib
 import unittest
 
-from django.test import SimpleTestCase
+from django.test import SimpleTestCase, override_settings
 from django.utils.crypto import (
     InvalidAlgorithm,
     constant_time_compare,
@@ -52,6 +52,14 @@ class TestUtilsCryptoMisc(SimpleTestCase):
             with self.subTest(args=args, kwargs=kwargs):
                 self.assertEqual(salted_hmac(*args, **kwargs).hexdigest(), digest)
 
+    @override_settings(
+        SECRET_KEY="secret",
+        SECRET_KEY_FALLBACKS=["oldsecret"],
+    )
+    def test_salted_hmac_secret_key_fallbacks(self):
+        old_digest = salted_hmac("salt", "value", secret="oldsecret").hexdigest()
+        self.assertEqual(salted_hmac("salt", "value").hexdigest(), old_digest)
+
     def test_invalid_algorithm(self):
         msg = "'whatever' is not an algorithm accepted by the hashlib module."
         with self.assertRaisesMessage(InvalidAlgorithm, msg):

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/auth/__init__\.py|django/contrib/auth/base_user\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 auth_tests.test_auth_backends auth_tests.test_basic utils_tests.test_crypto
cat coverage.cover
git checkout 9b224579875e30203d079cc2fee83b116d98eb78
git apply /root/pre_state.patch
