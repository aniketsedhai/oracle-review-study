#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git diff HEAD 361bb8f786f112ee275be136795c0b1ecefff928 >> /root/pre_state.patch
git config --global --add safe.directory /testbed
cd /testbed
git status
git show
git diff 361bb8f786f112ee275be136795c0b1ecefff928
source /opt/miniconda3/bin/activate
conda activate testbed
python -m pip install -e .
git apply -v - <<'EOF_114329324912'
diff --git a/tests/migrations/test_loader.py b/tests/migrations/test_loader.py
index 03a9850..22ada5d 100644
--- a/tests/migrations/test_loader.py
+++ b/tests/migrations/test_loader.py
@@ -8,7 +8,7 @@ from django.db.migrations.exceptions import (
 )
 from django.db.migrations.loader import MigrationLoader
 from django.db.migrations.recorder import MigrationRecorder
-from django.test import TestCase, modify_settings, override_settings
+from django.test import TestCase, TransactionTestCase, modify_settings, override_settings
 
 from .test_base import MigrationTestBase
 
@@ -46,6 +46,79 @@ class RecorderTests(TestCase):
         )
 
 
+class RecorderRouterTests(TransactionTestCase):
+    """
+    The migration recorder obeys the database router's allow_migrate() rules.
+    """
+    available_apps = ['migrations']
+    databases = {'default', 'other'}
+
+    def _drop_migrations_table(self, alias):
+        """Drop the django_migrations table on the given database."""
+        connection = connections[alias]
+        with connection.cursor() as cursor:
+            tables = connection.introspection.table_names(cursor)
+        if MigrationRecorder.Migration._meta.db_table in tables:
+            with connection.schema_editor() as editor:
+                editor.delete_model(MigrationRecorder.Migration)
+
+    def test_record_applied_skips_router_disallowed_database(self):
+        """
+        record_applied() doesn't create the django_migrations table on a
+        database where the router disallows migrating.
+        """
+        self._drop_migrations_table('other')
+        recorder = MigrationRecorder(connections['other'])
+        self.assertFalse(recorder.has_table())
+        with override_settings(DATABASE_ROUTERS=['migrations.routers.TestRouter']):
+            recorder.record_applied('myapp', '0432_ponies')
+        self.assertFalse(recorder.has_table())
+        self.assertEqual(recorder.applied_migrations(), {})
+
+    def test_record_unapplied_skips_router_disallowed_database(self):
+        """
+        record_unapplied() doesn't create the django_migrations table on a
+        database where the router disallows migrating.
+        """
+        self._drop_migrations_table('other')
+        recorder = MigrationRecorder(connections['other'])
+        self.assertFalse(recorder.has_table())
+        with override_settings(DATABASE_ROUTERS=['migrations.routers.TestRouter']):
+            recorder.record_unapplied('myapp', '0432_ponies')
+        self.assertFalse(recorder.has_table())
+
+    def test_ensure_schema_skips_router_disallowed_database(self):
+        """
+        ensure_schema() doesn't create the django_migrations table on a
+        database where the router disallows migrating.
+        """
+        self._drop_migrations_table('other')
+        recorder = MigrationRecorder(connections['other'])
+        self.assertFalse(recorder.has_table())
+        with override_settings(DATABASE_ROUTERS=['migrations.routers.TestRouter']):
+            recorder.ensure_schema()
+        self.assertFalse(recorder.has_table())
+
+    def test_record_applied_allowed_database(self):
+        """
+        The recorder still creates the table and records migrations on a
+        database where the router allows migrating.
+        """
+        self._drop_migrations_table('other')
+        recorder = MigrationRecorder(connections['other'])
+        self.assertFalse(recorder.has_table())
+        with override_settings(DATABASE_ROUTERS=['migrations.routers.DefaultOtherRouter']):
+            recorder.record_applied('myapp', '0432_ponies')
+        try:
+            self.assertTrue(recorder.has_table())
+            self.assertEqual(
+                {(x, y) for (x, y) in recorder.applied_migrations() if x == 'myapp'},
+                {('myapp', '0432_ponies')},
+            )
+        finally:
+            recorder.record_unapplied('myapp', '0432_ponies')
+
+
 class LoaderTests(TestCase):
     """
     Tests the disk and database loader, and running through migrations

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/db/migrations/executor\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 migrations.test_loader
cat coverage.cover
git checkout 361bb8f786f112ee275be136795c0b1ecefff928
git apply /root/pre_state.patch
