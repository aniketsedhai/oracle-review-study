"""Launch one isolated generation/review run. --help never makes API calls."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

from methods import METHODS

ROOT = Path(__file__).resolve().parents[1]


def shell(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--method", choices=list(METHODS), required=True)
    parser.add_argument("--instance", type=Path, required=True, help="Generation-facing JSON only")
    parser.add_argument("--image", required=True, help="Installed buggy benchmark image")
    parser.add_argument("--config", type=Path, default=ROOT / "configs/study.json")
    parser.add_argument("--framework", type=Path, default=ROOT.parent / "mini-swe-agent")
    parser.add_argument("--key-file", type=Path, help="Optional local .env file; never copied to Docker")
    parser.add_argument("--output-dir", type=Path, help="New artifact directory; existing directories are refused")
    parser.add_argument("--discover-test-roots", action="store_true",
                        help="Discover tests/testing directories from the buggy snapshot if not configured")
    parser.add_argument("--no-start-docker", action="store_true", help="Fail rather than opening Docker Desktop")
    parser.add_argument("--docker-startup-timeout", type=float, default=120,
                        help="Seconds to wait for Docker readiness before the experiment (default: 120)")
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    instance = json.loads(args.instance.read_text())
    allowed = {"instance_id", "repo", "base_commit", "problem_statement", "dataset", "dataset_revision"}
    if not set(instance).issubset(allowed):
        raise SystemExit("Input includes non-generation fields; refusing to expose them")
    if not re.fullmatch(r"[0-9a-f]{40}", instance["base_commit"]):
        raise SystemExit("Expected full buggy base commit SHA")
    roots = config["test_roots_by_repo"].get(instance["repo"], [])
    if not roots and not args.discover_test_roots:
        raise SystemExit("No permitted test roots configured")
    framework = args.framework.resolve()
    if shell("git", "-C", str(framework), "status", "--porcelain"):
        raise SystemExit("Framework checkout has local changes; inspect before running")
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(framework / "src"))
    os.environ.update(MSWEA_GLOBAL_CONFIG_DIR=str(ROOT / "runs/runtime-config"),
                      MSWEA_SILENT_STARTUP="1", MSWEA_MODEL_RETRY_STOP_AFTER_ATTEMPT="1",
                      LITELLM_LOG="ERROR", LITELLM_LOCAL_MODEL_COST_MAP="True",
                      PYTHON_DOTENV_DISABLED="1")
    from dotenv import dotenv_values
    if args.key_file:
        key = dotenv_values(args.key_file).get("DEEPSEEK_API_KEY", "")
        os.environ["DEEPSEEK_API_KEY"] = key
    if not re.fullmatch(r"sk-[A-Za-z0-9_-]+", os.environ.get("DEEPSEEK_API_KEY", "")):
        raise SystemExit("Set DEEPSEEK_API_KEY or supply --key-file; no key was displayed")
    from minisweagent.environments.docker import DockerEnvironment
    from agent_session import AgentSession
    from controller import run_workflow
    from runtime import DeadlineEnvironment, GuardedModel, PhaseAllowance
    from docker_startup import ensure_docker_ready
    from isolation import protect_checkout

    ensure_docker_ready(auto_start=not args.no_start_docker, timeout=args.docker_startup_timeout)

    run_directory = (args.output_dir.resolve() if args.output_dir else ROOT / "runs" / (
        datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + "-" + args.method))
    if run_directory.exists():
        raise SystemExit("Artifact directory already exists; refusing to overwrite")
    env = None
    setup = None
    isolation = None
    try:
        env = DockerEnvironment(image=args.image, cwd="/testbed", timeout=60, pull_timeout=180,
                                run_args=["--rm", "--platform", "linux/amd64", "--network", "none"],
                                env={"PAGER": "cat", "PYTHONDONTWRITEBYTECODE": "1", "PYTHONUNBUFFERED": "1"})
        # These destructive commands affect only the disposable, unmounted
        # container checkout, never an existing host repository.
        setup = env.execute({"command": (
            f"git reset --hard {instance['base_commit']} && git clean -fd && "
            "python3 -c " + shlex.quote("import shutil; shutil.rmtree('/testbed/.git')")
            + " && git init -q && git add -A && "
            "git -c user.name=Study -c user.email=study@localhost commit -qm 'Buggy starting snapshot'")}, timeout=120)
        if setup["returncode"]:
            raise RuntimeError("Docker setup failed")
        if not roots:
            from test_layout import discover_test_roots
            layout = env.execute({"command": "git ls-tree -r --name-only -z HEAD"})
            if layout["returncode"]:
                raise RuntimeError("Cannot inspect buggy test layout")
            roots = discover_test_roots(layout["output"].split("\0"))
            if not roots:
                raise RuntimeError("No supported tests/testing directories discovered")
            config["test_roots_by_repo"][instance["repo"]] = roots
            print("Discovered permitted test roots: " + json.dumps(roots), flush=True)
        isolation = protect_checkout(env, roots)
        method_options = METHODS[args.method]
        generator_prompt = (ROOT / "prompts" / method_options["generator_prompt"]).read_text()
        reviewer_prompt = (ROOT / "prompts" / method_options["reviewer_prompt"]).read_text()

        def session_factory(role, task, budget, phase_limits, directory):
            allowance = PhaseAllowance(budget, phase_limits)
            model = GuardedModel(allowance=allowance, **config["cost_accounting"],
                                 **config["model"])
            if role == "generator":
                task = generator_prompt + "\n\nPERMITTED TEST ROOTS\n" + json.dumps(roots) + "\n\nBUG REPORT\n" + task
            return AgentSession(model=model, env=DeadlineEnvironment(env, allowance),
                                task=task, budget=budget, phase_limits=phase_limits,
                                role=role,
                                output_directory=directory,
                                system_template="You are a software testing agent using a bash tool. Every response must include at least one bash tool call.")

        print(f"Starting {args.method}: {instance['instance_id']}\nArtifacts: {run_directory}", flush=True)
        summary = run_workflow(instance=instance, method=args.method, env=env, config=config,
                               run_directory=run_directory, session_factory=session_factory,
                               reviewer_prompt=reviewer_prompt)
        print(json.dumps(summary, indent=2), flush=True)
    finally:
        # Always release the container before optional metadata work, including
        # when saving a manifest fails. Setup failures also receive a record.
        if env is not None and env.container_id:
            try:
                subprocess.run(["docker", "stop", "-t", "2", env.container_id], capture_output=True, timeout=30)
            finally:
                env.container_id = None
        if setup is not None:
            run_directory.mkdir(parents=True, exist_ok=True)
        if run_directory.exists():
            (run_directory / "instance.json").write_text(json.dumps(instance, indent=2) + "\n")
            (run_directory / "config.json").write_text(json.dumps(config, indent=2) + "\n")
            sources = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                       for folder in ("scripts", "prompts") for path in (ROOT / folder).glob("*") if path.is_file()}
            metadata = {"implementation": "shared post-study refactor; historical results use frozen source snapshots",
                        "framework_commit": shell("git", "-C", str(framework), "rev-parse", "HEAD"),
                        "python": sys.version, "source_sha256": sources,
                        "image": json.loads(shell("docker", "image", "inspect", args.image)),
                        "model_alias_warning": "Provider alias may change; record provider identity separately",
                        "pricing_note": "Configured accounting rates; verify current provider pricing before paid runs"}
            (run_directory / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
            (run_directory / "requirements.lock.txt").write_text(shell(sys.executable, "-m", "pip", "freeze") + "\n")
            (run_directory / "setup.json").write_text(json.dumps(setup, indent=2) + "\n")
            (run_directory / "isolation.json").write_text(json.dumps(isolation, indent=2) + "\n")
            for folder in ("scripts", "prompts"):
                destination = run_directory / "source" / folder
                destination.mkdir(parents=True, exist_ok=True)
                for path in (ROOT / folder).glob("*"):
                    if path.is_file():
                        (destination / path.name).write_bytes(path.read_bytes())


if __name__ == "__main__":
    main()
