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
index 4b491e5..5885283 100644
--- a/tests/auth_tests/test_basic.py
+++ b/tests/auth_tests/test_basic.py
@@ -138,3 +138,67 @@ class TestGetUser(TestCase):
         user = get_user(request)
         self.assertIsInstance(user, User)
         self.assertEqual(user.username, created_user.username)
+
+
+class GetSessionAuthHashTests(TestCase):
+    def test_get_session_auth_hash_uses_secret_key(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        with override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=[]):
+            hash_with_secret = user.get_session_auth_hash()
+        with override_settings(SECRET_KEY="othersecret", SECRET_KEY_FALLBACKS=[]):
+            hash_with_other_secret = user.get_session_auth_hash()
+        self.assertNotEqual(hash_with_secret, hash_with_other_secret)
+
+    @override_settings(
+        SECRET_KEY="secret",
+        SECRET_KEY_FALLBACKS=["oldsecret"],
+    )
+    def test_get_session_auth_hash_secret_key_fallbacks(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            hash_with_old_secret = user.get_session_auth_hash()
+        # The hash generated with the old secret key is still valid after
+        # rotating SECRET_KEY and moving the old value to SECRET_KEY_FALLBACKS.
+        self.assertEqual(user.get_session_auth_hash(), hash_with_old_secret)
+
+    @override_settings(
+        SECRET_KEY="secret",
+        SECRET_KEY_FALLBACKS=["oldsecret"],
+    )
+    def test_get_session_auth_hash_secret_key_fallbacks_removed(self):
+        user = User.objects.create_user("testuser", "test@example.com", "testpw")
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            hash_with_old_secret = user.get_session_auth_hash()
+        with override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=[]):
+            self.assertNotEqual(user.get_session_auth_hash(), hash_with_old_secret)
+
+
+@override_settings(
+    AUTHENTICATION_BACKENDS=["django.contrib.auth.backends.ModelBackend"],
+)
+class SessionAuthHashFallbackTests(TestCase):
+    def test_session_survives_secret_key_rotation(self):
+        User.objects.create_user("testuser", "test@example.com", "testpw")
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            self.assertTrue(self.client.login(username="testuser", password="testpw"))
+            session_key = self.client.session.session_key
+        # Rotate the secret key, keeping the old one as a fallback.
+        with override_settings(
+            SECRET_KEY="newsecret", SECRET_KEY_FALLBACKS=["oldsecret"]
+        ):
+            request = HttpRequest()
+            request.session = self.client.session.__class__(session_key)
+            user = get_user(request)
+            self.assertIsInstance(user, User)
+            self.assertEqual(user.username, "testuser")
+
+    def test_session_invalidated_when_fallback_removed(self):
+        User.objects.create_user("testuser", "test@example.com", "testpw")
+        with override_settings(SECRET_KEY="oldsecret", SECRET_KEY_FALLBACKS=[]):
+            self.assertTrue(self.client.login(username="testuser", password="testpw"))
+            session_key = self.client.session.session_key
+        # The old secret key is no longer available.
+        with override_settings(SECRET_KEY="newsecret", SECRET_KEY_FALLBACKS=[]):
+            request = HttpRequest()
+            request.session = self.client.session.__class__(session_key)
+            self.assertIsInstance(get_user(request), AnonymousUser)
diff --git a/tests/utils_tests/test_crypto.py b/tests/utils_tests/test_crypto.py
index ed3ed25..f46da1d 100644
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
@@ -52,6 +52,55 @@ class TestUtilsCryptoMisc(SimpleTestCase):
             with self.subTest(args=args, kwargs=kwargs):
                 self.assertEqual(salted_hmac(*args, **kwargs).hexdigest(), digest)
 
+    @override_settings(
+        SECRET_KEY="secret",
+        SECRET_KEY_FALLBACKS=["oldsecret"],
+    )
+    def test_salted_hmac_secret_key_fallbacks(self):
+        # The current SECRET_KEY is used by default.
+        self.assertEqual(
+            salted_hmac("salt", "value").hexdigest(),
+            salted_hmac("salt", "value", secret="secret").hexdigest(),
+        )
+        # Fallback keys are used when no secret is provided.
+        self.assertEqual(
+            salted_hmac("salt", "value").hexdigest(),
+            salted_hmac("salt", "value", secret="oldsecret").hexdigest(),
+        )
+
+    @override_settings(
+        SECRET_KEY="secret",
+        SECRET_KEY_FALLBACKS=["oldsecret"],
+    )
+    def test_salted_hmac_secret_key_fallbacks_algorithm(self):
+        self.assertEqual(
+            salted_hmac("salt", "value", algorithm="sha256").hexdigest(),
+            salted_hmac(
+                "salt", "value", secret="oldsecret", algorithm="sha256"
+            ).hexdigest(),
+        )
+
+    @override_settings(
+        SECRET_KEY="secret",
+        SECRET_KEY_FALLBACKS=["oldsecret"],
+    )
+    def test_salted_hmac_explicit_secret_ignores_fallbacks(self):
+        self.assertEqual(
+            salted_hmac("salt", "value", secret="othersecret").hexdigest(),
+            salted_hmac("salt", "value", secret="othersecret").hexdigest(),
+        )
+        self.assertNotEqual(
+            salted_hmac("salt", "value", secret="othersecret").hexdigest(),
+            salted_hmac("salt", "value").hexdigest(),
+        )
+
+    @override_settings(SECRET_KEY="secret", SECRET_KEY_FALLBACKS=[])
+    def test_salted_hmac_no_secret_key_fallbacks(self):
+        self.assertEqual(
+            salted_hmac("salt", "value").hexdigest(),
+            salted_hmac("salt", "value", secret="secret").hexdigest(),
+        )
+
     def test_invalid_algorithm(self):
         msg = "'whatever' is not an algorithm accepted by the hashlib module."
         with self.assertRaisesMessage(InvalidAlgorithm, msg):

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/contrib/auth/base_user\.py|django/contrib/auth/__init__\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 auth_tests.test_basic utils_tests.test_crypto
cat coverage.cover
git checkout 9b224579875e30203d079cc2fee83b116d98eb78
git apply /root/pre_state.patch
