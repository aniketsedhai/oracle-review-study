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
diff --git a/tests/migrations/routers.py b/tests/migrations/routers.py
index bc03638..ffdaa08 100644
--- a/tests/migrations/routers.py
+++ b/tests/migrations/routers.py
@@ -12,3 +12,13 @@ class TestRouter:
             return db == 'other'
         elif db != 'default':
             return False
+
+
+class MigrateNothingRouter:
+    def allow_migrate(self, db, app_label, model_name=None, **hints):
+        return False
+
+
+class MigrateEverythingRouter:
+    def allow_migrate(self, db, app_label, model_name=None, **hints):
+        return True
diff --git a/tests/migrations/test_commands.py b/tests/migrations/test_commands.py
index bf78b60..65df95e 100644
--- a/tests/migrations/test_commands.py
+++ b/tests/migrations/test_commands.py
@@ -205,6 +205,49 @@ class MigrateTests(MigrationTestBase):
             self.assertTableNotExists("migrations_tribble", using=db)
             self.assertTableNotExists("migrations_book", using=db)
 
+    def _drop_migrations_table(self, alias):
+        recorder = MigrationRecorder(connections[alias])
+        if recorder.has_table():
+            with connections[alias].cursor() as cursor:
+                cursor.execute(
+                    'DROP TABLE %s' % connections[alias].ops.quote_name(
+                        recorder.Migration._meta.db_table
+                    )
+                )
+        self.assertTableNotExists("django_migrations", using=alias)
+
+    @override_settings(
+        MIGRATION_MODULES={"migrations": "migrations.test_migrations"},
+        DATABASE_ROUTERS=['migrations.routers.MigrateNothingRouter'],
+    )
+    def test_migrate_router_does_not_create_migrations_table(self):
+        """
+        The django_migrations table isn't created on a database where the
+        router disallows migrating.
+        """
+        self._drop_migrations_table("other")
+        call_command("migrate", verbosity=0, database="other")
+        self.assertTableNotExists("django_migrations", using="other")
+        self.assertTableNotExists("migrations_author", using="other")
+        self.assertTableNotExists("migrations_book", using="other")
+
+    @override_settings(
+        MIGRATION_MODULES={"migrations": "migrations.test_migrations"},
+        DATABASE_ROUTERS=['migrations.routers.MigrateEverythingRouter'],
+    )
+    def test_migrate_router_creates_migrations_table(self):
+        """
+        The django_migrations table is created on a database where the router
+        allows migrating.
+        """
+        self._drop_migrations_table("other")
+        try:
+            call_command("migrate", verbosity=0, database="other")
+            self.assertTableExists("django_migrations", using="other")
+            self.assertTableExists("migrations_author", using="other")
+        finally:
+            call_command("migrate", "migrations", "zero", verbosity=0, database="other")
+
     @skipUnlessDBFeature('ignores_table_name_case')
     def test_migrate_fake_initial_case_insensitive(self):
         with override_settings(MIGRATION_MODULES={
diff --git a/tests/migrations/test_loader.py b/tests/migrations/test_loader.py
index 03a9850..fad0d9e 100644
--- a/tests/migrations/test_loader.py
+++ b/tests/migrations/test_loader.py
@@ -8,15 +8,18 @@ from django.db.migrations.exceptions import (
 )
 from django.db.migrations.loader import MigrationLoader
 from django.db.migrations.recorder import MigrationRecorder
-from django.test import TestCase, modify_settings, override_settings
+from django.test import (
+    TestCase, TransactionTestCase, modify_settings, override_settings,
+)
 
 from .test_base import MigrationTestBase
 
 
-class RecorderTests(TestCase):
+class RecorderTests(TransactionTestCase):
     """
     Tests recording migrations as applied or not.
     """
+    available_apps = ['migrations']
     databases = {'default', 'other'}
 
     def test_apply(self):
@@ -45,6 +48,84 @@ class RecorderTests(TestCase):
             set(),
         )
 
+    def _drop_migrations_table(self, alias):
+        """
+        Drop the django_migrations table on the given database so that the
+        recorder has to (re)create it.
+        """
+        recorder = MigrationRecorder(connections[alias])
+        if recorder.has_table():
+            with connections[alias].cursor() as cursor:
+                cursor.execute(
+                    'DROP TABLE %s' % connections[alias].ops.quote_name(
+                        recorder.Migration._meta.db_table
+                    )
+                )
+        self.assertFalse(recorder.has_table())
+        # The table is recreated by the test database setup for the next test
+        # method, so make sure it's restored afterwards.
+        self.addCleanup(self._restore_migrations_table, alias)
+
+    def _restore_migrations_table(self, alias):
+        with override_settings(DATABASE_ROUTERS=[]):
+            MigrationRecorder(connections[alias]).ensure_schema()
+
+    @override_settings(DATABASE_ROUTERS=['migrations.routers.MigrateNothingRouter'])
+    def test_ensure_schema_router(self):
+        """
+        ensure_schema() doesn't create the django_migrations table on a
+        database where the router disallows migrating.
+        """
+        self._drop_migrations_table('other')
+        recorder = MigrationRecorder(connections['other'])
+        recorder.ensure_schema()
+        self.assertFalse(recorder.has_table())
+
+    @override_settings(DATABASE_ROUTERS=['migrations.routers.MigrateNothingRouter'])
+    def test_record_applied_router(self):
+        """
+        record_applied() doesn't create the django_migrations table nor
+        record anything on a database where the router disallows migrating.
+        """
+        self._drop_migrations_table('other')
+        recorder = MigrationRecorder(connections['other'])
+        recorder.record_applied('myapp', '0432_ponies')
+        self.assertFalse(recorder.has_table())
+        self.assertEqual(recorder.applied_migrations(), {})
+
+    @override_settings(DATABASE_ROUTERS=['migrations.routers.MigrateNothingRouter'])
+    def test_record_unapplied_router(self):
+        """
+        record_unapplied() doesn't create the django_migrations table on a
+        database where the router disallows migrating.
+        """
+        self._drop_migrations_table('other')
+        recorder = MigrationRecorder(connections['other'])
+        recorder.record_unapplied('myapp', '0432_ponies')
+        self.assertFalse(recorder.has_table())
+
+    @override_settings(DATABASE_ROUTERS=['migrations.routers.MigrateNothingRouter'])
+    def test_applied_migrations_router(self):
+        """
+        applied_migrations() doesn't create the django_migrations table on a
+        database where the router disallows migrating.
+        """
+        self._drop_migrations_table('other')
+        recorder = MigrationRecorder(connections['other'])
+        self.assertEqual(recorder.applied_migrations(), {})
+        self.assertFalse(recorder.has_table())
+
+    @override_settings(DATABASE_ROUTERS=['migrations.routers.MigrateEverythingRouter'])
+    def test_ensure_schema_router_allowed(self):
+        """
+        ensure_schema() creates the django_migrations table when the router
+        allows migrating.
+        """
+        self._drop_migrations_table('other')
+        recorder = MigrationRecorder(connections['other'])
+        recorder.ensure_schema()
+        self.assertTrue(recorder.has_table())
+
 
 class LoaderTests(TestCase):
     """

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/db/migrations/executor\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 migrations.routers migrations.test_commands migrations.test_loader
cat coverage.cover
git checkout 361bb8f786f112ee275be136795c0b1ecefff928
git apply /root/pre_state.patch
