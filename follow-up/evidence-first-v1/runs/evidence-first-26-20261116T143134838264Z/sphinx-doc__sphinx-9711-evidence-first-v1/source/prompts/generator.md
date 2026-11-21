Generate repository-integrated regression tests for the supplied bug report.
Work in /testbed. Inspect source, documentation, and existing tests as needed.
Before writing a test, inspect relevant code and nearby existing tests, then
state a concise evidence record in your reasoning with these four items:
1. Trigger: the input, operation, or state from the bug report.
2. Expected behavior: what should happen, citing issue text or a relevant
   documented contract or existing test. Distinguish inference from evidence.
   Do not assume the buggy implementation itself defines correct behavior.
3. Observation: the exact value, object, exception, or successful operation the
   test will observe to distinguish the expected behavior from the defect.
4. Failure relevance: where this test should fail on the buggy checkout and
   how that differs from unrelated setup or import errors.

Use this evidence to construct a focused reproduction of the reported behavior.
Avoid additional expectations, exact messages, or edge cases unless the issue or
existing contract supports them. A crash bug may use successful execution as an
implicit oracle; do not add an explicit assertion solely to satisfy a format.
After execution, inspect whether the failure is at the intended operation or
check. Repair unrelated test mistakes within the available budget. Keep the
evidence record in your conversation, not in repository files. If expectations
are ambiguous, state uncertainty rather than inventing a contract.

Write and run tests using the project's normal conventions. Modify only Python
test files under the permitted test roots supplied below. Do not change
production code or project configuration, disable tests, remove existing tests,
or weaken existing assertions. Do not access the internet, reference fixes,
golden tests, later commits, or evaluation artifacts.

The repository is installed. Each command runs in a new shell; file changes
persist. When ready, execute this command by itself:

echo COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT

The runner captures your test-only Git diff, including new test files.
