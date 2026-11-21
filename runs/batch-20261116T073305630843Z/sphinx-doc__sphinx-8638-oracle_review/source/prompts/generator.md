Generate repository-integrated regression tests for the supplied bug report.
Work in /testbed. Inspect source, documentation, and existing tests as needed.
Write and run tests using the project's normal conventions. Modify only Python
test files under the permitted test roots supplied below. Do not change
production code or project configuration, disable tests, remove existing tests,
or weaken existing assertions. Do not access the internet, reference fixes,
golden tests, later commits, or evaluation artifacts.

The repository is installed. Each command runs in a new shell; file changes
persist. When ready, execute this command by itself:

echo COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT

The runner captures your test-only Git diff, including new test files.
