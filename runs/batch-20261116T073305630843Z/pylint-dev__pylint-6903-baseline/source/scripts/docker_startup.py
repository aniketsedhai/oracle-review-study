"""Ensure Docker is ready before beginning an experiment."""

import platform
import subprocess
import time


def ensure_docker_ready(*, auto_start=True, timeout=120):
    """On macOS, start Docker Desktop if the configured daemon is unavailable.

    Readiness means a successful Docker API query, not just an open GUI window.
    Does not change Docker context or start model requests.
    """
    if timeout <= 0:
        raise ValueError("Docker startup timeout must be positive")
    deadline = time.monotonic() + timeout

    def ready():
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        try:
            result = subprocess.run(
                ["docker", "info", "--format", "{{.ServerVersion}}"],
                capture_output=True, text=True, timeout=min(5, remaining))
        except FileNotFoundError:
            raise RuntimeError("Docker CLI not found; install Docker Desktop first") from None
        except subprocess.TimeoutExpired:
            return False
        return result.returncode == 0

    if ready():
        return
    if not auto_start:
        raise RuntimeError("Docker engine is unavailable; start it or enable automatic startup")
    if platform.system() != "Darwin":
        raise RuntimeError("Automatic Docker Desktop startup is supported on macOS; start Docker manually")
    # Avoid opening the local app for an explicitly selected remote Docker host.
    import os
    if os.environ.get("DOCKER_HOST", "").startswith(("tcp://", "ssh://", "http://", "https://")):
        raise RuntimeError("Configured remote Docker host is unavailable; local startup would not fix it")
    print("Opening Docker Desktop; waiting for the engine...", flush=True)
    try:
        opened = subprocess.run(["open", "-a", "Docker"], capture_output=True,
                                text=True, timeout=max(.001, min(10, deadline - time.monotonic())))
    except subprocess.TimeoutExpired:
        raise RuntimeError("Opening Docker Desktop timed out") from None
    if opened.returncode:
        raise RuntimeError("Could not open Docker Desktop; check that it is installed")
    while time.monotonic() < deadline:
        if ready():
            print("Docker engine is ready.", flush=True)
            return
        time.sleep(max(0, min(1, deadline - time.monotonic())))
    raise RuntimeError(f"Docker engine did not become ready within {timeout} seconds; inspect Docker Desktop")
