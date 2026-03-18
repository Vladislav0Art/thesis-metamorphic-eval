"""
Shared environment-setup logic used by both AgentStep and EvaluationStep.

The Setup class manages venv creation and dependency installation for a
sub-project (MSWE-agent or multi_swe_bench).  It is intentionally kept
stateless beyond what is given at construction time so that it can be reused
by any Step without subclassing.

Command execution model
-----------------------
`prepare` commands are run *without* the venv (the venv may not exist yet,
e.g. `uv venv` or `python3 -m venv ./venv` creates it).

`install` commands are run *with* the venv's bin/ prepended to PATH so that
`python`, `pip`, `uv`, `make install`, etc. automatically resolve to the
venv-local binaries.  VIRTUAL_ENV is also set so tools that inspect it
(e.g. uv) behave correctly.

Idempotency
-----------
`ensure()` skips `prepare` if the venv's bin/python already exists.
`install` always runs (pip/uv install with unchanged requirements is fast
and idempotent).
"""

import os
import sys
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import List

# Ensure scripts/ is on sys.path
_SCRIPTS_DIR = Path(__file__).resolve().parent.parent.parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

from common.cli import run_cli_command

logger = logging.getLogger(__name__)


# ─── Config ───────────────────────────────────────────────────────────────────

@dataclass
class SetupConfig:
    """
    Declarative spec for setting up a sub-project's Python environment.

    Attributes:
        venv:    Path to the venv directory, relative to the step's working dir.
        prepare: Shell commands run WITHOUT the venv (e.g., to create it).
        install: Shell commands run WITH the venv active (e.g., install deps).
    """
    venv: str
    prepare: List[str] = field(default_factory=list)
    install: List[str] = field(default_factory=list)


# ─── Setup ────────────────────────────────────────────────────────────────────

class Setup:
    """
    Manages idempotent environment setup for a sub-project.

    Usage:

        setup = Setup(config, working_dir=Path("/path/to/repo"))
        setup.ensure()  # creates venv if absent, then installs deps

    All commands are executed via ``bash -c`` in the step's working directory.
    """

    def __init__(self, config: SetupConfig, working_dir: Path):
        self.config = config
        self.working_dir = working_dir
        self.venv_path = working_dir / config.venv
        self.venv_bin = self.venv_path / "bin"

    def ensure(self):
        """
        Idempotently ensure the environment is ready:
          1. If venv does not exist, run ``prepare`` commands to create it.
          2. Always run ``install`` commands with venv active.
        """
        if not (self.venv_bin / "python").exists():
            logger.info(f"Venv not found at {self.venv_path}; running prepare commands...")
            self._run_commands(self.config.prepare, env=os.environ.copy(), label="prepare")
        else:
            logger.info(f"Venv already exists at {self.venv_path}; skipping prepare.")

        logger.info("Running install commands inside venv...")
        self._run_commands(self.config.install, env=self._venv_env(), label="install")

    # ─── Helpers ──────────────────────────────────────────────────────────────

    def _venv_env(self) -> dict:
        """Return a copy of the environment with venv's bin/ first on PATH."""
        env = os.environ.copy()
        env["PATH"] = f"{self.venv_bin}:{env.get('PATH', '')}"
        # VIRTUAL_ENV lets tools like uv know they are inside a venv
        env["VIRTUAL_ENV"] = str(self.venv_path)
        return env

    def _run_commands(self, commands: List[str], env: dict, label: str):
        """
        Execute each command via ``bash -c`` in the step's working directory.
        Raises RuntimeError on the first non-zero exit code.
        """
        if not commands:
            logger.info(f"[{label}] No commands defined; skipping.")
            return

        for cmd in commands:
            logger.info(f"[{label}] $ {cmd}")
            stdout, stderr, code = run_cli_command(
                "bash", ["-c", cmd],
                cwd=str(self.working_dir),
                env=env,
            )
            if stdout:
                logger.debug(f"[{label}] stdout:\n{stdout.strip()}")
            if stderr:
                logger.debug(f"[{label}] stderr:\n{stderr.strip()}")
            if code != 0:
                raise RuntimeError(
                    f"Setup command failed (exit {code}) [{label}]: `{cmd}`\n"
                    f"stderr: {stderr.strip()}"
                )

        logger.info(f"[{label}] {len(commands)} command(s) completed successfully.")
