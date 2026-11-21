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
diff --git a/django/db/migrations/executor.py b/django/db/migrations/executor.py
--- a/django/db/migrations/executor.py
+++ b/django/db/migrations/executor.py
@@ -96,8 +96,12 @@ def migrate(self, targets, plan=None, state=None, fake=False, fake_initial=False
         (un)applied and in a second step run all the database operations.
         """
         # The django_migrations table must be present to record applied
-        # migrations.
-        self.recorder.ensure_schema()
+        # migrations, but don't create it if there are no migrations to apply.
+        if plan == []:
+            if not self.recorder.has_table():
+                return self._create_project_state(with_applied_migrations=False)
+        else:
+            self.recorder.ensure_schema()
 
         if plan is None:
             plan = self.migration_plan(targets)

EOF_114329324912
git apply -v - <<'EOF_114329324912'
diff --git a/tests/migrations/routers.py b/tests/migrations/routers.py
index bc03638..6faf50d 100644
--- a/tests/migrations/routers.py
+++ b/tests/migrations/routers.py
@@ -12,3 +12,11 @@ class TestRouter:
             return db == 'other'
         elif db != 'default':
             return False
+
+
+class TestRouterSettingRouter:
+    def allow_migrate(self, db, app_label, model_name=None, **hints):
+        """
+        The router that only allows migrating on the 'default' database.
+        """
+        return db == 'default'
diff --git a/tests/migrations/test_commands.py b/tests/migrations/test_commands.py
index bf78b60..e580614 100644
--- a/tests/migrations/test_commands.py
+++ b/tests/migrations/test_commands.py
@@ -900,6 +900,37 @@ class MigrateTests(MigrationTestBase):
             self.assertGreater(len(execute.mock_calls), 2)
             self.assertIn('Synchronize unmigrated app: unmigrated_app_syncdb', stdout.getvalue())
 
+    @override_settings(
+        MIGRATION_MODULES={"migrations": "migrations.test_migrations"},
+        DATABASE_ROUTERS=['migrations.routers.TestRouterSettingRouter'],
+    )
+    def test_migrate_obeys_router(self):
+        """
+        The migrate command doesn't create the django_migrations table nor
+        apply migrations on databases where the router disallows migrating.
+        """
+        recorder = MigrationRecorder(connections['other'])
+        # Simulate a database where the django_migrations table was never
+        # created (e.g. a connection that is never migrated).
+        if recorder.has_table():
+            with connections['other'].schema_editor() as editor:
+                editor.delete_model(recorder.Migration)
+        self.assertFalse(recorder.has_table())
+        call_command('migrate', 'migrations', database='other', verbosity=0)
+        self.assertFalse(recorder.has_table())
+        self.assertTableNotExists('migrations_author', using='other')
+        self.assertTableNotExists('migrations_book', using='other')
+        # The 'default' database is still migrated.
+        call_command('migrate', 'migrations', database='default', verbosity=0)
+        self.assertTrue(MigrationRecorder(connection).has_table())
+        self.assertTableExists('migrations_author', using='default')
+        self.assertTableExists('migrations_book', using='default')
+        # Rollback changes.
+        call_command('migrate', 'migrations', 'zero', database='default', verbosity=0)
+        # Restore the django_migrations table on 'other' for tearDown().
+        with connections['other'].schema_editor() as editor:
+            editor.create_model(recorder.Migration)
+
     @override_settings(MIGRATION_MODULES={"migrations": "migrations.test_migrations_squashed"})
     def test_migrate_record_replaced(self):
         """
diff --git a/tests/migrations/test_loader.py b/tests/migrations/test_loader.py
index 03a9850..82f4f52 100644
--- a/tests/migrations/test_loader.py
+++ b/tests/migrations/test_loader.py
@@ -8,15 +8,16 @@ from django.db.migrations.exceptions import (
 )
 from django.db.migrations.loader import MigrationLoader
 from django.db.migrations.recorder import MigrationRecorder
-from django.test import TestCase, modify_settings, override_settings
+from django.test import TestCase, TransactionTestCase, modify_settings, override_settings
 
 from .test_base import MigrationTestBase
 
 
-class RecorderTests(TestCase):
+class RecorderTests(TransactionTestCase):
     """
     Tests recording migrations as applied or not.
     """
+    available_apps = ['migrations']
     databases = {'default', 'other'}
 
     def test_apply(self):
@@ -45,6 +46,32 @@ class RecorderTests(TestCase):
             set(),
         )
 
+    @override_settings(DATABASE_ROUTERS=['migrations.routers.TestRouterSettingRouter'])
+    def test_migration_recorder_obeys_router(self):
+        """
+        The migration recorder doesn't create the django_migrations table on
+        databases where the router disallows migrating.
+        """
+        recorder = MigrationRecorder(connections['other'])
+        # Simulate a database where the django_migrations table was never
+        # created (e.g. a connection that is never migrated).
+        if recorder.has_table():
+            with connections['other'].schema_editor() as editor:
+                editor.delete_model(recorder.Migration)
+        self.assertFalse(recorder.has_table())
+        recorder.record_applied('myapp', '0432_ponies')
+        self.assertFalse(recorder.has_table())
+        self.assertEqual(recorder.applied_migrations(), {})
+        recorder.record_unapplied('myapp', '0432_ponies')
+        self.assertFalse(recorder.has_table())
+        # The 'default' database is still allowed to be migrated.
+        recorder_default = MigrationRecorder(connection)
+        recorder_default.record_applied('myapp', '0432_ponies')
+        self.assertTrue(recorder_default.has_table())
+        self.assertIn(('myapp', '0432_ponies'), recorder_default.applied_migrations())
+        recorder_default.record_unapplied('myapp', '0432_ponies')
+        self.assertNotIn(('myapp', '0432_ponies'), recorder_default.applied_migrations())
+
 
 class LoaderTests(TestCase):
     """

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/db/migrations/executor\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 migrations.routers migrations.test_commands migrations.test_loader
cat coverage.cover
git checkout 361bb8f786f112ee275be136795c0b1ecefff928
git apply /root/pre_state.patch
