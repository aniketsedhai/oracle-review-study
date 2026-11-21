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
diff --git a/tests/migrations/test_executor.py b/tests/migrations/test_executor.py
index ca2c03c..9c60ef2 100644
--- a/tests/migrations/test_executor.py
+++ b/tests/migrations/test_executor.py
@@ -760,6 +760,65 @@ class ExecutorTests(MigrationTestBase):
         )
 
 
+    def _drop_migrations_table(self):
+        """Drop the django_migrations table to simulate a fresh database."""
+        recorder = MigrationRecorder(connection)
+        with connection.cursor() as cursor:
+            cursor.execute(
+                'DROP TABLE %s' % recorder.Migration._meta.db_table
+            )
+        self.assertFalse(recorder.has_table())
+
+    @override_settings(MIGRATION_MODULES={"migrations": "migrations.test_migrations"})
+    def test_migrate_skipped_if_router_disallows(self):
+        """The recorder doesn't create its table on databases where the
+        router disallows migrating the migrations app."""
+        class DisallowMigrationsRouter:
+            def allow_migrate(self, db, app_label, **hints):
+                return app_label != 'migrations'
+
+        self._drop_migrations_table()
+        recorder = MigrationRecorder(connection)
+        with override_settings(DATABASE_ROUTERS=[DisallowMigrationsRouter()]):
+            executor = MigrationExecutor(connection)
+            executor.migrate([("migrations", "0001_initial")])
+            self.assertFalse(recorder.has_table())
+            self.assertEqual(recorder.applied_migrations(), {})
+            self.assertTableNotExists("migrations_author")
+            self.assertTableNotExists("migrations_tribble")
+            executor.loader.build_graph()
+            executor.migrate([("migrations", None)])
+            self.assertFalse(recorder.has_table())
+
+    @override_settings(MIGRATION_MODULES={"migrations": "migrations.test_migrations"})
+    def test_migrate_allowed_if_router_allows(self):
+        """The recorder creates its table when the router allows migrating."""
+        class AllowMigrationsRouter:
+            def allow_migrate(self, db, app_label, **hints):
+                return app_label == 'migrations'
+
+        self._drop_migrations_table()
+        recorder = MigrationRecorder(connection)
+        with override_settings(DATABASE_ROUTERS=[AllowMigrationsRouter()]):
+            executor = MigrationExecutor(connection)
+            executor.migrate([("migrations", "0001_initial")])
+            self.assertTrue(recorder.has_table())
+            self.assertIn(
+                ("migrations", "0001_initial"),
+                recorder.applied_migrations(),
+            )
+            self.assertTableExists("migrations_author")
+            self.assertTableExists("migrations_tribble")
+            executor.loader.build_graph()
+            executor.migrate([("migrations", None)])
+            self.assertNotIn(
+                ("migrations", "0001_initial"),
+                recorder.applied_migrations(),
+            )
+            self.assertTableNotExists("migrations_author")
+            self.assertTableNotExists("migrations_tribble")
+
+
 class FakeLoader:
     def __init__(self, graph, applied):
         self.graph = graph
diff --git a/tests/migrations/test_loader.py b/tests/migrations/test_loader.py
index 03a9850..f75696c 100644
--- a/tests/migrations/test_loader.py
+++ b/tests/migrations/test_loader.py
@@ -8,7 +8,9 @@ from django.db.migrations.exceptions import (
 )
 from django.db.migrations.loader import MigrationLoader
 from django.db.migrations.recorder import MigrationRecorder
-from django.test import TestCase, modify_settings, override_settings
+from django.test import (
+    TestCase, TransactionTestCase, modify_settings, override_settings,
+)
 
 from .test_base import MigrationTestBase
 
@@ -46,6 +48,60 @@ class RecorderTests(TestCase):
         )
 
 
+class RecorderRouterTests(TransactionTestCase):
+    """
+    Tests that the migration recorder obeys database router allow_migrate()
+    rules for the migrations app.
+    """
+    databases = {'default', 'other'}
+
+    def _drop_migrations_table(self, alias):
+        """Drop the django_migrations table to simulate a fresh database."""
+        recorder = MigrationRecorder(connections[alias])
+        with connections[alias].cursor() as cursor:
+            cursor.execute(
+                'DROP TABLE %s' % recorder.Migration._meta.db_table
+            )
+        self.assertFalse(recorder.has_table())
+
+    def test_migrate_skipped_if_router_disallows(self):
+        """The recorder doesn't create its table on databases where the
+        router disallows migrating the migrations app."""
+        class DisallowMigrationsRouter:
+            def allow_migrate(self, db, app_label, **hints):
+                return app_label != 'migrations'
+
+        self._drop_migrations_table('other')
+        recorder = MigrationRecorder(connections['other'])
+        with override_settings(DATABASE_ROUTERS=[DisallowMigrationsRouter()]):
+            recorder.record_applied('myapp', '0432_ponies')
+            self.assertFalse(recorder.has_table())
+            self.assertEqual(recorder.applied_migrations(), {})
+            recorder.record_unapplied('myapp', '0432_ponies')
+            self.assertFalse(recorder.has_table())
+
+    def test_migrate_allowed_if_router_allows(self):
+        """The recorder creates its table when the router allows migrating."""
+        class AllowMigrationsRouter:
+            def allow_migrate(self, db, app_label, **hints):
+                return app_label == 'migrations'
+
+        self._drop_migrations_table('other')
+        recorder = MigrationRecorder(connections['other'])
+        with override_settings(DATABASE_ROUTERS=[AllowMigrationsRouter()]):
+            recorder.record_applied('myapp', '0432_ponies')
+            self.assertTrue(recorder.has_table())
+            self.assertIn(
+                ('myapp', '0432_ponies'),
+                recorder.applied_migrations(),
+            )
+            recorder.record_unapplied('myapp', '0432_ponies')
+            self.assertNotIn(
+                ('myapp', '0432_ponies'),
+                recorder.applied_migrations(),
+            )
+
+
 class LoaderTests(TestCase):
     """
     Tests the disk and database loader, and running through migrations

EOF_114329324912
python3 /root/trace.py --count -C coverage.cover --include-pattern '/testbed/(django/db/migrations/executor\.py)' ./tests/runtests.py --verbosity 2 --settings=test_sqlite --parallel 1 migrations.test_executor migrations.test_loader
cat coverage.cover
git checkout 361bb8f786f112ee275be136795c0b1ecefff928
git apply /root/pre_state.patch
